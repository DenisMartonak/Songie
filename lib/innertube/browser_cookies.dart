import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/log.dart';
import '../core/result.dart';
import 'yt_sign_in.dart' show YtSessionFromCookies;

/// Reads the YouTube/Google cookies from the user's own browser profile on
/// Linux, the way yt-dlp's `--cookies-from-browser` does.
///
/// - Firefox and its forks (LibreWolf, Waterfox) keep `cookies.sqlite` with
///   the values in plain text.
/// - The Chromium family keeps `Cookies` with the values encrypted: `v10`
///   with a fixed key, `v11` with a password from the keyring.
///
/// The cookie database is never opened in place: it is copied, with its
/// `-wal` and `-shm` files, into a private 0700 temp directory, the copy is
/// opened read-only and then deleted. A running browser is never locked or
/// disturbed. Cookie values never reach a log or a [Failure].

/// The browser family; the forks map onto it (LibreWolf → firefox,
/// ungoogled Chromium → chromium).
enum BrowserKind { firefox, chrome, chromium, brave, edge, vivaldi }

/// One browser profile with a cookie database.
class BrowserProfile {
  const BrowserProfile({
    required this.kind,
    required this.name,
    required this.flatpak,
    required this.profile,
    required this.cookiesPath,
  });

  final BrowserKind kind;

  /// The browser's name, e.g. "LibreWolf" or "Google Chrome Dev".
  final String name;

  /// Installed as a Flatpak (under `~/.var/app`).
  final bool flatpak;

  /// The profile's directory name, e.g. "Default" or "abc.default-release".
  final String profile;

  final String cookiesPath;

  /// The browser as the user sees it: "Firefox (Flatpak)".
  String get browser => flatpak ? '$name (Flatpak)' : name;

  bool get isFirefox => kind == BrowserKind.firefox;

  /// The `application` the keyring password of a Chromium browser is
  /// stored under (yt-dlp's mapping): Edge uses Chromium's, Vivaldi
  /// Chrome's.
  String get keyringApp => switch (kind) {
    BrowserKind.chrome || BrowserKind.vivaldi => 'chrome',
    BrowserKind.chromium || BrowserKind.edge => 'chromium',
    BrowserKind.brave => 'brave',
    BrowserKind.firefox => '',
  };

  @override
  String toString() => 'BrowserProfile($browser, $profile)';
}

typedef _Root = (BrowserKind kind, String name, bool flatpak, String dir);

const _firefoxRoots = <_Root>[
  (BrowserKind.firefox, 'Firefox', false, '.mozilla/firefox'),
  (BrowserKind.firefox, 'Firefox', false, '.config/mozilla/firefox'),
  (
    BrowserKind.firefox,
    'Firefox',
    true,
    '.var/app/org.mozilla.firefox/.mozilla/firefox',
  ),
  (
    BrowserKind.firefox,
    'Firefox',
    true,
    '.var/app/org.mozilla.firefox/config/mozilla/firefox',
  ),
  (BrowserKind.firefox, 'LibreWolf', false, '.librewolf'),
  (
    BrowserKind.firefox,
    'LibreWolf',
    true,
    '.var/app/io.gitlab.librewolf-community/.librewolf',
  ),
  (BrowserKind.firefox, 'Waterfox', false, '.waterfox'),
  (
    BrowserKind.firefox,
    'Waterfox',
    true,
    '.var/app/net.waterfox.waterfox/.waterfox',
  ),
];

const _chromiumRoots = <_Root>[
  (BrowserKind.chrome, 'Google Chrome', false, '.config/google-chrome'),
  (
    BrowserKind.chrome,
    'Google Chrome Beta',
    false,
    '.config/google-chrome-beta',
  ),
  (
    BrowserKind.chrome,
    'Google Chrome Dev',
    false,
    '.config/google-chrome-unstable',
  ),
  (
    BrowserKind.chrome,
    'Google Chrome',
    true,
    '.var/app/com.google.Chrome/config/google-chrome',
  ),
  (
    BrowserKind.chrome,
    'Google Chrome Dev',
    true,
    '.var/app/com.google.ChromeDev/config/google-chrome-unstable',
  ),
  (BrowserKind.chromium, 'Chromium', false, '.config/chromium'),
  (
    BrowserKind.chromium,
    'Chromium',
    true,
    '.var/app/org.chromium.Chromium/config/chromium',
  ),
  (
    BrowserKind.chromium,
    'ungoogled Chromium',
    true,
    '.var/app/io.github.ungoogled_software.ungoogled_chromium/config/chromium',
  ),
  (BrowserKind.brave, 'Brave', false, '.config/BraveSoftware/Brave-Browser'),
  (
    BrowserKind.brave,
    'Brave',
    true,
    '.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser',
  ),
  (BrowserKind.edge, 'Microsoft Edge', false, '.config/microsoft-edge'),
  (
    BrowserKind.edge,
    'Microsoft Edge',
    true,
    '.var/app/com.microsoft.Edge/config/microsoft-edge',
  ),
  (BrowserKind.vivaldi, 'Vivaldi', false, '.config/vivaldi'),
  (
    BrowserKind.vivaldi,
    'Vivaldi',
    true,
    '.var/app/com.vivaldi.Vivaldi/config/vivaldi',
  ),
];

/// Every browser profile under [home] (default `$HOME`) that has a cookie
/// database: native and Flatpak installs of Firefox, LibreWolf, Waterfox,
/// Chrome, Chromium, ungoogled Chromium, Brave, Edge and Vivaldi. Only file
/// names are looked at; nothing is opened.
Future<List<BrowserProfile>> findBrowserProfiles({String? home}) async {
  home ??= Platform.environment['HOME'];
  if (home == null || home.isEmpty) return const [];
  final found = <BrowserProfile>[];
  final seen = <String>{};

  Future<void> add(_Root root, String profileDir, String cookies) async {
    String key;
    try {
      key = await File(cookies).resolveSymbolicLinks();
    } catch (_) {
      key = cookies;
    }
    if (!seen.add(key)) return;
    found.add(
      BrowserProfile(
        kind: root.$1,
        name: root.$2,
        flatpak: root.$3,
        profile: p.basename(profileDir),
        cookiesPath: cookies,
      ),
    );
  }

  Future<List<Directory>> subdirs(String dir) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) return const [];
      final out = [
        await for (final e in d.list(followLinks: false))
          if (e is Directory) e,
      ]..sort((a, b) => a.path.compareTo(b.path));
      return out;
    } catch (_) {
      return const [];
    }
  }

  for (final root in _firefoxRoots) {
    for (final d in await subdirs(p.join(home, root.$4))) {
      final cookies = p.join(d.path, 'cookies.sqlite');
      if (await File(cookies).exists()) await add(root, d.path, cookies);
    }
  }
  for (final root in _chromiumRoots) {
    for (final d in await subdirs(p.join(home, root.$4))) {
      // Chromium 96+ keeps it under Network/; older ones at the top.
      for (final rel in ['Network/Cookies', 'Cookies']) {
        final cookies = p.join(d.path, rel);
        if (await File(cookies).exists()) {
          await add(root, d.path, cookies);
          break;
        }
      }
    }
  }
  return found;
}

/// Thrown inside the reader; turned into an [Err] with [message] only.
class _ReadFailure implements Exception {
  _ReadFailure(this.message);
  final String message;
}

String _readMessage(BrowserProfile p) => "Couldn't read ${p.name}'s cookies";

const _copyPrefix = 'songies_cookies_';

/// This process's copies being read right now; never swept.
final _activeCopies = <String>{};

/// Deletes copies an earlier run left in [root] (a crash mid-read leaves a
/// plaintext copy): directories named `songies_cookies_*` owned by this
/// user. Links are never followed. Best effort.
Future<void> _sweepStaleCopies(Directory root) async {
  try {
    final stale = <String>[
      await for (final e in root.list(followLinks: false))
        if (e is Directory &&
            p.basename(e.path).startsWith(_copyPrefix) &&
            !_activeCopies.contains(e.path))
          e.path,
    ];
    if (stale.isEmpty) return;
    final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
    final owners = await Process.run('stat', ['-c', '%u', ...stale]);
    final lines = owners.stdout.toString().trim().split('\n');
    for (final (i, path) in stale.indexed) {
      if (uid.isEmpty || i >= lines.length || lines[i].trim() != uid) continue;
      try {
        await Directory(path).delete(recursive: true);
      } catch (_) {}
    }
  } catch (e) {
    AppLog.w('browser cookies: could not sweep old copies (${e.runtimeType})');
  }
}

/// Copies [profile]'s cookie database (with `-wal`/`-shm`) into a fresh
/// private directory under [tempRoot], opens the copy read-only, runs
/// [body] on it and deletes the copy, whatever happens.
Future<T> _withCopy<T>(
  BrowserProfile profile,
  Directory? tempRoot,
  void Function(Directory dir)? onCopied,
  Future<T> Function(Database db) body,
) async {
  final root = tempRoot ?? Directory.systemTemp;
  await _sweepStaleCopies(root);
  final dir = await root.createTemp(_copyPrefix);
  _activeCopies.add(dir.path);
  try {
    // createTemp follows the umask (usually 0755): close it to the user
    // before anything is copied in, and refuse it if that didn't work.
    await Process.run('chmod', ['700', dir.path]);
    if ((await dir.stat()).mode & 0x1ff != 0x1c0) {
      throw _ReadFailure(_readMessage(profile));
    }
    onCopied?.call(dir);
    final copy = p.join(dir.path, 'cookies.db');
    // A running browser may write while the files are copied. SQLite
    // checks each -wal frame against the -wal header's salt and checksums
    // and ignores frames that don't match (a torn copy just loses the
    // newest writes). If the main file changed during the copy, copy once
    // more.
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = await File(profile.cookiesPath).stat();
      await File(profile.cookiesPath).copy(copy);
      for (final suffix in ['-wal', '-shm']) {
        final target = File('$copy$suffix');
        if (await target.exists()) await target.delete();
        final f = File('${profile.cookiesPath}$suffix');
        try {
          if (await f.exists()) await f.copy(target.path);
        } on FileSystemException {
          // Gone between the check and the copy (the browser checkpointed
          // and closed): the main file then holds everything.
        }
      }
      final after = await File(profile.cookiesPath).stat();
      if (after.size == before.size && after.modified == before.modified) {
        break;
      }
    }
    final db = sqlite3.open(copy, mode: OpenMode.readOnly);
    try {
      return await body(db);
    } finally {
      db.close();
    }
  } finally {
    _activeCopies.remove(dir.path);
    try {
      await dir.delete(recursive: true);
    } catch (e) {
      AppLog.w('browser cookies: could not delete the copy (${e.runtimeType})');
    }
  }
}

bool _hasColumn(Database db, String table, String column) =>
    db.select('PRAGMA table_info($table)').any((r) => r['name'] == column);

bool _kept(String? host) {
  final c = Cookie(name: '', domain: host);
  return YtSessionFromCookies.isYouTube(c) || YtSessionFromCookies.isGoogle(c);
}

/// Reads the `.youtube.com` and `.google.com` cookies of [profile].
///
/// Chromium's `v11` cookies need the browser's password from the keyring:
/// [keyringSecret] (default [secretServicePassword]) is asked for it, by
/// `application` (`chrome`, `chromium`, `brave`), only when such a cookie
/// is there.
///
/// Errors are an [Err] with a plain message naming the browser; never a
/// cookie value, and no cause.
Future<Result<List<Cookie>>> readBrowserCookies(
  BrowserProfile profile, {
  Future<String?> Function(String app)? keyringSecret,
  Directory? tempRoot,
  void Function(Directory dir)? onCopied,
}) async {
  try {
    final cookies = await _withCopy(
      profile,
      tempRoot,
      onCopied,
      (db) => profile.isFirefox
          ? Future.value(_readFirefox(db))
          : _readChromium(db, profile, keyringSecret ?? secretServicePassword),
    );
    return Ok(cookies);
  } on _ReadFailure catch (e) {
    AppLog.w('browser cookies: ${profile.browser}: ${e.message}');
    return Err(Failure(FailureKind.permission, e.message));
  } catch (e) {
    AppLog.w(
      'browser cookies: ${profile.browser} unreadable (${e.runtimeType})',
    );
    return Err(Failure(FailureKind.io, _readMessage(profile)));
  }
}

List<Cookie> _readFirefox(Database db) {
  final container = _hasColumn(db, 'moz_cookies', 'originAttributes')
      ? " AND originAttributes = ''"
      : '';
  final rows = db.select(
    'SELECT name, value, host, path, isSecure, isHttpOnly FROM moz_cookies '
    "WHERE (host LIKE '%youtube.com' OR host LIKE '%google.com')$container",
  );
  return [
    for (final r in rows)
      if (_kept(r['host'] as String?))
        Cookie(
          name: r['name'] as String? ?? '',
          value: r['value'] as String? ?? '',
          domain: r['host'] as String?,
          path: r['path'] as String?,
          isSecure: r['isSecure'] == 1,
          isHttpOnly: r['isHttpOnly'] == 1,
        ),
  ];
}

Future<List<Cookie>> _readChromium(
  Database db,
  BrowserProfile profile,
  Future<String?> Function(String app) keyringSecret,
) async {
  // Chromium 130+ (meta version 24) puts SHA-256(host_key) before the
  // value inside the encrypted bytes.
  var version = 0;
  try {
    final rows = db.select("SELECT value FROM meta WHERE key = 'version'");
    if (rows.isNotEmpty) version = int.tryParse('${rows.first['value']}') ?? 0;
  } catch (_) {}
  final hashPrefix = version >= 24;

  final rows = db.select(
    'SELECT host_key, name, value, encrypted_value, path, is_secure, '
    "is_httponly FROM cookies WHERE (host_key LIKE '%youtube.com' OR "
    "host_key LIKE '%google.com')",
  );
  final kept = [
    for (final r in rows)
      if (_kept(r['host_key'] as String?)) r,
  ];

  final v10Key = chromiumKey('peanuts');
  final emptyKey = chromiumKey('');
  List<Uint8List>? v11Keys;
  final out = <Cookie>[];
  for (final r in kept) {
    final encrypted = r['encrypted_value'];
    String value;
    if (encrypted is! Uint8List || encrypted.isEmpty) {
      value = r['value'] as String? ?? '';
    } else {
      final prefix = encrypted.length >= 3
          ? ascii.decode(encrypted.sublist(0, 3), allowInvalid: true)
          : '';
      final List<Uint8List> keys;
      if (prefix == 'v10') {
        keys = [v10Key, emptyKey];
      } else if (prefix == 'v11') {
        if (v11Keys == null) {
          String? password;
          try {
            password = await keyringSecret(profile.keyringApp);
          } catch (e) {
            AppLog.w('browser cookies: keyring read failed (${e.runtimeType})');
          }
          v11Keys = [if (password != null) chromiumKey(password), emptyKey];
        }
        keys = v11Keys;
      } else {
        throw _ReadFailure(_readMessage(profile));
      }
      final decrypted = _decrypt(encrypted.sublist(3), keys, hashPrefix);
      if (decrypted == null) {
        throw _ReadFailure(
          prefix == 'v11'
              ? "Couldn't unlock ${profile.name}'s cookies: its key in the "
                    "keyring isn't available"
              : _readMessage(profile),
        );
      }
      value = decrypted;
    }
    out.add(
      Cookie(
        name: r['name'] as String? ?? '',
        value: value,
        domain: r['host_key'] as String?,
        path: r['path'] as String?,
        isSecure: r['is_secure'] == 1,
        isHttpOnly: r['is_httponly'] == 1,
      ),
    );
  }
  return out;
}

/// Chromium's Linux cookie key: PBKDF2-HMAC-SHA1([password], "saltysalt",
/// 1 iteration, 16 bytes).
Uint8List chromiumKey(String password) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(utf8.encode('saltysalt'), 1, 16));
  return kdf.process(utf8.encode(password));
}

final _iv = Uint8List.fromList(List.filled(16, 0x20));

/// AES-128-CBC with an IV of 16 spaces; the first key that gives valid
/// padding and UTF-8 wins. Null when none does.
String? _decrypt(Uint8List data, List<Uint8List> keys, bool hashPrefix) {
  if (data.isEmpty || data.length % 16 != 0) return null;
  for (final key in keys) {
    try {
      final cipher =
          PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
              false,
              PaddedBlockCipherParameters(
                ParametersWithIV(KeyParameter(key), _iv),
                null,
              ),
            );
      var plain = cipher.process(data);
      if (hashPrefix) {
        if (plain.length < 32) continue;
        plain = plain.sublist(32);
      }
      return utf8.decode(plain);
    } catch (_) {
      // Wrong key: bad padding or not text. Try the next.
    }
  }
  return null;
}

const _secretsName = 'org.freedesktop.secrets';
const _serviceIface = 'org.freedesktop.Secret.Service';
const _itemIface = 'org.freedesktop.Secret.Item';

String _keyringLabel(String app) => switch (app) {
  'chrome' => 'Chrome',
  'chromium' => 'Chromium',
  'brave' => 'Brave',
  _ => app,
};

/// The Chromium cookie password for [app] (`chrome`, `chromium`, `brave`):
/// first from the Secret Service (GNOME Keyring, KeePassXC, KWallet's
/// Secret Service), by the attribute `application` = [app]; then from
/// KWallet's own API (`<Browser> Keys` / `<Browser> Safe Storage`). The
/// keyring may ask the user to unlock it. Null when it's not there.
///
/// Called only after the user picked a Chromium profile and confirmed:
/// never at startup (R5).
Future<String?> secretServicePassword(String app) async {
  final client = DBusClient.session();
  try {
    return await _fromSecretService(client, app) ??
        await _fromKWallet(client, app);
  } finally {
    await client.close();
  }
}

Future<String?> _fromSecretService(DBusClient client, String app) async {
  try {
    final service = DBusRemoteObject(
      client,
      name: _secretsName,
      path: DBusObjectPath('/org/freedesktop/secrets'),
    );
    final opened = await service.callMethod(_serviceIface, 'OpenSession', [
      const DBusString('plain'),
      const DBusVariant(DBusString('')),
    ], replySignature: DBusSignature('vo'));
    final session = opened.values[1].asObjectPath();
    final search = await service.callMethod(_serviceIface, 'SearchItems', [
      DBusDict(DBusSignature('s'), DBusSignature('s'), {
        const DBusString('application'): DBusString(app),
      }),
    ], replySignature: DBusSignature('aoao'));
    final unlocked = search.values[0].asObjectPathArray().toList();
    final locked = search.values[1].asObjectPathArray().toList();
    if (locked.isNotEmpty) {
      unlocked.addAll(await _unlock(client, service, locked));
    }
    final want = '${_keyringLabel(app)} Safe Storage';
    // The item labelled "<Browser> Safe Storage" first.
    final ordered = <DBusObjectPath>[];
    for (final path in unlocked) {
      final item = DBusRemoteObject(client, name: _secretsName, path: path);
      String label = '';
      try {
        label = (await item.getProperty(_itemIface, 'Label')).asString();
      } catch (_) {}
      label == want ? ordered.insert(0, path) : ordered.add(path);
    }
    for (final path in ordered) {
      final item = DBusRemoteObject(client, name: _secretsName, path: path);
      final secret = await item.callMethod(_itemIface, 'GetSecret', [
        session,
      ], replySignature: DBusSignature('(oayays)'));
      final bytes = secret.values[0].asStruct()[2].asByteArray().toList();
      if (bytes.isNotEmpty) return utf8.decode(bytes, allowMalformed: true);
    }
    return null;
  } catch (e) {
    AppLog.w('browser cookies: Secret Service unavailable (${e.runtimeType})');
    return null;
  }
}

/// Unlocks [locked] items; the keyring may show its own prompt.
Future<List<DBusObjectPath>> _unlock(
  DBusClient client,
  DBusRemoteObject service,
  List<DBusObjectPath> locked,
) async {
  final r = await service.callMethod(_serviceIface, 'Unlock', [
    DBusArray.objectPath(locked),
  ], replySignature: DBusSignature('aoo'));
  final done = r.values[0].asObjectPathArray().toList();
  final prompt = r.values[1].asObjectPath();
  if (prompt.value == '/') return done;
  final promptObject = DBusRemoteObject(
    client,
    name: _secretsName,
    path: prompt,
  );
  final completed = DBusRemoteObjectSignalStream(
    object: promptObject,
    interface: 'org.freedesktop.Secret.Prompt',
    name: 'Completed',
    signature: DBusSignature('bv'),
  ).first;
  await promptObject.callMethod('org.freedesktop.Secret.Prompt', 'Prompt', [
    const DBusString(''),
  ], replySignature: DBusSignature(''));
  final signal = await completed.timeout(const Duration(minutes: 2));
  if (signal.values[0].asBoolean()) return done; // dismissed
  final result = signal.values[1].asVariant();
  return [...done, ...result.asObjectPathArray()];
}

Future<String?> _fromKWallet(DBusClient client, String app) async {
  const appId = 'Songies';
  final label = _keyringLabel(app);
  for (final (name, path) in [
    ('org.kde.kwalletd6', '/modules/kwalletd6'),
    ('org.kde.kwalletd5', '/modules/kwalletd5'),
  ]) {
    try {
      final wallet = DBusRemoteObject(
        client,
        name: name,
        path: DBusObjectPath(path),
      );
      const iface = 'org.kde.KWallet';
      final network = (await wallet.callMethod(
        iface,
        'networkWallet',
        const [],
        replySignature: DBusSignature('s'),
      )).values[0].asString();
      final handle = (await wallet.callMethod(iface, 'open', [
        DBusString(network),
        const DBusInt64(0),
        const DBusString(appId),
      ], replySignature: DBusSignature('i'))).values[0].asInt32();
      if (handle < 0) continue;
      try {
        final pw = (await wallet.callMethod(iface, 'readPassword', [
          DBusInt32(handle),
          DBusString('$label Keys'),
          DBusString('$label Safe Storage'),
          const DBusString(appId),
        ], replySignature: DBusSignature('s'))).values[0].asString();
        if (pw.isNotEmpty) return pw;
      } finally {
        try {
          await wallet.callMethod(iface, 'close', [
            DBusInt32(handle),
            const DBusBoolean(false),
            const DBusString(appId),
          ], replySignature: DBusSignature('i'));
        } catch (_) {}
      }
    } catch (e) {
      // Not running here: try the next.
    }
  }
  return null;
}
