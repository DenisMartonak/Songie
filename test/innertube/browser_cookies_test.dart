import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/browser_cookies.dart';
import 'package:songies/innertube/browser_sign_in.dart';
import 'package:songies/innertube/yt_sign_in.dart';
import 'package:sqlite3/sqlite3.dart';

// Every value here is made up for the test; nothing comes from a real
// browser profile.
const _sap = 'test-sapisid-value-123';

Uint8List _key(String password) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(utf8.encode('saltysalt'), 1, 16));
  return kdf.process(utf8.encode(password));
}

/// Encrypts [value] the way Chromium on Linux does.
Uint8List _chromeEncrypt(
  String value, {
  String prefix = 'v10',
  String password = 'peanuts',
  String? hostKeyHash,
}) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(
            KeyParameter(_key(password)),
            Uint8List.fromList(List.filled(16, 0x20)),
          ),
          null,
        ),
      );
  final plain = <int>[
    if (hostKeyHash != null) ...List.filled(32, 7),
    ...utf8.encode(value),
  ];
  return Uint8List.fromList([
    ...ascii.encode(prefix),
    ...cipher.process(Uint8List.fromList(plain)),
  ]);
}

Database _firefoxDb(String path) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, originAttributes TEXT
      NOT NULL DEFAULT '', name TEXT, value TEXT, host TEXT, path TEXT,
      expiry INTEGER, lastAccessed INTEGER, creationTime INTEGER,
      isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER)''');
  return db;
}

void _ffAdd(
  Database db,
  String name,
  String value,
  String host, {
  String origin = '',
}) {
  db.execute(
    'INSERT INTO moz_cookies (originAttributes, name, value, host, path, '
    'expiry, isSecure, isHttpOnly, sameSite) VALUES (?, ?, ?, ?, ?, ?, 1, 1, 0)',
    [origin, name, value, host, '/', 4102444800],
  );
}

Database _chromeDb(String path, {int version = 23}) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final db = sqlite3.open(path);
  db.execute(
    'CREATE TABLE meta (key TEXT NOT NULL UNIQUE PRIMARY KEY, '
    'value TEXT)',
  );
  db.execute("INSERT INTO meta VALUES ('version', '$version')");
  db.execute('''
    CREATE TABLE cookies (creation_utc INTEGER, host_key TEXT, top_frame_site_key
      TEXT NOT NULL DEFAULT '', name TEXT, value TEXT, encrypted_value BLOB,
      path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER,
      samesite INTEGER)''');
  return db;
}

void _chAdd(
  Database db,
  String name,
  String host, {
  String value = '',
  Uint8List? encrypted,
}) {
  db.execute(
    'INSERT INTO cookies (creation_utc, host_key, name, value, '
    'encrypted_value, path, expires_utc, is_secure, is_httponly, samesite) '
    'VALUES (0, ?, ?, ?, ?, ?, 0, 1, 1, 0)',
    [host, name, value, encrypted ?? Uint8List(0), '/'],
  );
}

Map<String, String> _byName(List<Cookie> cookies) => {
  for (final c in cookies) '${c.domain}|${c.name}': '${c.value}',
};

void main() {
  late Directory home;
  late Directory temp;

  setUp(() {
    home = Directory.systemTemp.createTempSync('songies_home_');
    temp = Directory.systemTemp.createTempSync('songies_cookie_tmp_');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String at(String rel) => p.join(home.path, rel);

  group('findBrowserProfiles', () {
    test('finds native and Flatpak profiles of every family', () async {
      final ff = _firefoxDb(
        at(
          '.mozilla/firefox/abc.default-release/'
          'cookies.sqlite',
        ),
      )..close();
      final flatFf = _firefoxDb(
        at(
          '.var/app/org.mozilla.firefox/.mozilla/'
          'firefox/xyz.default/cookies.sqlite',
        ),
      );
      flatFf.close();
      _firefoxDb(
        at(
          '.var/app/io.gitlab.librewolf-community/.librewolf/'
          'lw.default/cookies.sqlite',
        ),
      ).close();
      _firefoxDb(
        at(
          '.var/app/net.waterfox.waterfox/.waterfox/'
          'wf.default/cookies.sqlite',
        ),
      ).close();
      _chromeDb(
        at(
          '.var/app/com.google.Chrome/config/google-chrome/Default/'
          'Cookies',
        ),
      ).close();
      _chromeDb(
        at(
          '.var/app/com.google.ChromeDev/config/'
          'google-chrome-unstable/Profile 1/Cookies',
        ),
      ).close();
      _chromeDb(
        at(
          '.var/app/org.chromium.Chromium/config/chromium/Default/'
          'Network/Cookies',
        ),
      ).close();
      _chromeDb(
        at(
          '.var/app/io.github.ungoogled_software.ungoogled_chromium/'
          'config/chromium/Default/Cookies',
        ),
      ).close();
      _chromeDb(at('.config/BraveSoftware/Brave-Browser/Default/Cookies'))
          .close();
      // Not a profile: no cookie database inside.
      Directory(at('.config/google-chrome/System Profile'))
          .createSync(recursive: true);
      expect(ff, isNotNull);

      final found = await findBrowserProfiles(home: home.path);
      final seen = {
        for (final f in found) '${f.kind.name}|${f.browser}|${f.profile}',
      };
      expect(seen, {
        'firefox|Firefox|abc.default-release',
        'firefox|Firefox (Flatpak)|xyz.default',
        'firefox|LibreWolf (Flatpak)|lw.default',
        'firefox|Waterfox (Flatpak)|wf.default',
        'chrome|Google Chrome (Flatpak)|Default',
        'chrome|Google Chrome Dev (Flatpak)|Profile 1',
        'chromium|Chromium (Flatpak)|Default',
        'chromium|ungoogled Chromium (Flatpak)|Default',
        'brave|Brave|Default',
      });
    });

    test('an empty home has no profiles', () async {
      expect(await findBrowserProfiles(home: home.path), isEmpty);
    });
  });

  group('readBrowserCookies', () {
    test('Firefox: finds the .youtube.com SAPISID in plain text', () async {
      final path = at('.mozilla/firefox/a.default/cookies.sqlite');
      final db = _firefoxDb(path);
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      _ffAdd(db, 'SID', 'g-sid', '.google.com');
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;

      final r = await readBrowserCookies(profile, tempRoot: temp);
      final cookies = (r as Ok<List<Cookie>>).value;
      expect(_byName(cookies), {
        '.youtube.com|SAPISID': _sap,
        '.google.com|SID': 'g-sid',
      });
      expect(await hasYouTubeSession(profile, tempRoot: temp), isTrue);
    });

    test('Firefox: container cookies are left out', () async {
      final db = _firefoxDb(at('.mozilla/firefox/a.default/cookies.sqlite'));
      _ffAdd(db, 'SAPISID', 'work', '.youtube.com', origin: '^userContextId=2');
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      final cookies =
          (await readBrowserCookies(profile, tempRoot: temp) as Ok).value
              as List<Cookie>;
      expect(_byName(cookies), {'.youtube.com|SAPISID': _sap});
    });

    test('non-YouTube cookies are dropped', () async {
      final db = _firefoxDb(at('.mozilla/firefox/a.default/cookies.sqlite'));
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      _ffAdd(db, 'bank', 'secret-bank', '.bank.example');
      _ffAdd(db, 'evil', 'x', '.notyoutube.com');
      _ffAdd(db, 'evil2', 'x', 'youtube.com.example.org');
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      final cookies =
          (await readBrowserCookies(profile, tempRoot: temp) as Ok).value
              as List<Cookie>;
      expect(_byName(cookies).keys, ['.youtube.com|SAPISID']);
    });

    test('Chromium v10 decrypts with the peanuts key', () async {
      final db = _chromeDb(at('.config/chromium/Default/Cookies'));
      _chAdd(db, 'SAPISID', '.youtube.com', encrypted: _chromeEncrypt(_sap));
      _chAdd(db, 'SID', '.google.com', encrypted: _chromeEncrypt('g-sid'));
      _chAdd(db, 'PREF', '.youtube.com', value: 'plain-pref');
      _chAdd(db, 'other', '.example.com', encrypted: _chromeEncrypt('nope'));
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;

      var asked = 0;
      final r = await readBrowserCookies(
        profile,
        tempRoot: temp,
        keyringSecret: (_) async {
          asked++;
          return null;
        },
      );
      expect(_byName((r as Ok<List<Cookie>>).value), {
        '.youtube.com|SAPISID': _sap,
        '.google.com|SID': 'g-sid',
        '.youtube.com|PREF': 'plain-pref',
      });
      expect(asked, 0, reason: 'v10 needs no keyring');
    });

    test('Chromium v11 uses the injected keyringSecret', () async {
      final db = _chromeDb(
        at(
          '.var/app/com.google.Chrome/config/'
          'google-chrome/Default/Cookies',
        ),
      );
      _chAdd(
        db,
        'SAPISID',
        '.youtube.com',
        encrypted: _chromeEncrypt(_sap, prefix: 'v11', password: 'kr-pw'),
      );
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;

      final apps = <String>[];
      final r = await readBrowserCookies(
        profile,
        tempRoot: temp,
        keyringSecret: (app) async {
          apps.add(app);
          return 'kr-pw';
        },
      );
      expect(_byName((r as Ok<List<Cookie>>).value), {
        '.youtube.com|SAPISID': _sap,
      });
      expect(apps, ['chrome']);
    });

    test('Chromium v24+ strips the host hash before the value', () async {
      final db = _chromeDb(at('.config/chromium/Default/Cookies'), version: 24);
      _chAdd(
        db,
        'SAPISID',
        '.youtube.com',
        encrypted: _chromeEncrypt(_sap, hostKeyHash: '.youtube.com'),
      );
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      final r = await readBrowserCookies(profile, tempRoot: temp);
      expect(_byName((r as Ok<List<Cookie>>).value), {
        '.youtube.com|SAPISID': _sap,
      });
    });

    test(
      'Chromium v11 without the keyring secret is an Err, no values',
      () async {
        final db = _chromeDb(at('.config/google-chrome/Default/Cookies'));
        _chAdd(
          db,
          'SAPISID',
          '.youtube.com',
          encrypted: _chromeEncrypt(_sap, prefix: 'v11', password: 'kr-pw'),
        );
        db.close();
        final profile = (await findBrowserProfiles(home: home.path)).single;
        final r = await readBrowserCookies(
          profile,
          tempRoot: temp,
          keyringSecret: (_) async => null,
        );
        final f = (r as Err).failure;
        expect(f.message, isNot(contains(_sap)));
        expect(f.message, contains('Google Chrome'));
      },
    );

    test('a database with a -wal is read through a private copy; the '
        'original is untouched', () async {
      final path = at('.mozilla/firefox/a.default/cookies.sqlite');
      final db = _firefoxDb(path);
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA wal_autocheckpoint=0');
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      // The "browser" keeps the database open: the row lives only in -wal.
      expect(File('$path-wal').existsSync(), isTrue);
      expect(File('$path-wal').lengthSync(), greaterThan(0));

      final files = [path, '$path-wal', '$path-shm'];
      final before = {
        for (final f in files)
          f: (File(f).readAsBytesSync(), File(f).lastModifiedSync()),
      };

      final profile = (await findBrowserProfiles(home: home.path)).single;
      final r = await readBrowserCookies(profile, tempRoot: temp);
      expect(_byName((r as Ok<List<Cookie>>).value), {
        '.youtube.com|SAPISID': _sap,
      });

      for (final f in files) {
        expect(File(f).readAsBytesSync(), before[f]!.$1, reason: f);
        expect(File(f).lastModifiedSync(), before[f]!.$2, reason: f);
      }
      // The private copy is gone.
      expect(temp.listSync(), isEmpty);
      db.close();
    });

    test(
      'a WAL-mode database the browser closed (no -wal) still reads',
      () async {
        final path = at('.mozilla/firefox/a.default/cookies.sqlite');
        final db = _firefoxDb(path);
        db.execute('PRAGMA journal_mode=WAL');
        _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
        db.close();
        expect(File('$path-wal').existsSync(), isFalse);
        final profile = (await findBrowserProfiles(home: home.path)).single;
        final r = await readBrowserCookies(profile, tempRoot: temp);
        expect(_byName((r as Ok<List<Cookie>>).value), {
          '.youtube.com|SAPISID': _sap,
        });
        expect(await hasYouTubeSession(profile, tempRoot: temp), isTrue);
        expect(temp.listSync(), isEmpty);
      },
    );

    test('the private copy lives in a 0700 directory', () async {
      final db = _firefoxDb(at('.mozilla/firefox/a.default/cookies.sqlite'));
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      final modes = <int>[];
      await readBrowserCookies(
        profile,
        tempRoot: temp,
        onCopied: (dir) => modes.add(dir.statSync().mode & 0x1ff),
      );
      expect(modes, [0x1c0]);
      expect(temp.listSync(), isEmpty);
    });

    test('a corrupt file gives Err with no cookie text', () async {
      final path = at('.mozilla/firefox/a.default/cookies.sqlite');
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsStringSync('garbage SAPISID=$_sap garbage' * 200);
      final profile = (await findBrowserProfiles(home: home.path)).single;
      final r = await readBrowserCookies(profile, tempRoot: temp);
      final f = (r as Err).failure;
      expect(f.message, "Couldn't read Firefox's cookies");
      expect(f.toString(), isNot(contains(_sap)));
      expect('${f.cause}', isNot(contains(_sap)));
      expect(temp.listSync(), isEmpty);
    });

    test('an unreadable (locked) file gives Err with no cookie text', () async {
      final path = at('.mozilla/firefox/a.default/cookies.sqlite');
      final db = _firefoxDb(path);
      _ffAdd(db, 'SAPISID', _sap, '.youtube.com');
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      await Process.run('chmod', ['000', path]);
      try {
        final r = await readBrowserCookies(profile, tempRoot: temp);
        final f = (r as Err).failure;
        expect(f.message, "Couldn't read Firefox's cookies");
        expect(f.toString(), isNot(contains(_sap)));
        expect(await hasYouTubeSession(profile, tempRoot: temp), isFalse);
      } finally {
        await Process.run('chmod', ['600', path]);
      }
      expect(temp.listSync(), isEmpty);
    });

    test('hasYouTubeSession is false without a YouTube SAPISID', () async {
      final db = _chromeDb(at('.config/chromium/Default/Cookies'));
      _chAdd(db, 'SID', '.youtube.com', encrypted: _chromeEncrypt('x'));
      _chAdd(db, 'SAPISID', '.example.com', encrypted: _chromeEncrypt('x'));
      db.close();
      final profile = (await findBrowserProfiles(home: home.path)).single;
      expect(await hasYouTubeSession(profile, tempRoot: temp), isFalse);
    });
  });

  group('BrowserSignIn', () {
    test('label', () {
      expect(BrowserSignIn().label, 'Use the YouTube sign-in from my browser');
    });

    test('with no profiles found, supported() is false', () async {
      expect(await BrowserSignIn(home: home.path).supported(), isFalse);
    });

    test('with a profile found, supported() is true', () async {
      _firefoxDb(at('.mozilla/firefox/a.default/cookies.sqlite')).close();
      expect(await BrowserSignIn(home: home.path).supported(), isTrue);
    });

    BrowserProfile fake(String name, String profile) => BrowserProfile(
      kind: BrowserKind.firefox,
      name: name,
      flatpak: true,
      profile: profile,
      cookiesPath: '/nonexistent/$profile/cookies.sqlite',
    );

    Future<YtSignInResult?> run(
      WidgetTester tester,
      BrowserSignIn route,
      Future<void> Function() drive,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      YtSignInResult? result;
      var done = false;
      unawaited(
        route.signIn(ctx).then((r) {
          result = r;
          done = true;
        }),
      );
      await tester.pumpAndSettle();
      await drive();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      return result;
    }

    testWidgets('lists only signed-in profiles; pick and confirm build the '
        'session', (tester) async {
      final a = fake('Firefox', 'a.default');
      final b = fake('LibreWolf', 'b.default');
      final c = fake('Waterfox', 'c.default');
      final read = <BrowserProfile>[];
      final route = BrowserSignIn(
        findProfiles: () async => [a, b, c],
        hasSession: (p) async => p != c,
        readCookies: (p) async {
          read.add(p);
          return Ok([
            Cookie(name: 'SAPISID', value: _sap, domain: '.youtube.com'),
          ]);
        },
      );
      final result = await run(tester, route, () async {
        expect(find.text('Firefox (Flatpak)'), findsOneWidget);
        expect(find.text('LibreWolf (Flatpak)'), findsOneWidget);
        expect(find.text('Waterfox (Flatpak)'), findsNothing);
        expect(read, isEmpty, reason: 'nothing is read before confirming');
        await tester.tap(find.byKey(const Key('browserSignIn.profile.1')));
        await tester.pumpAndSettle();
        expect(read, isEmpty, reason: 'nothing is read before confirming');
        await tester.tap(find.byKey(const Key('browserSignIn.confirm')));
      });
      expect(read, [b]);
      expect(result!.session.sapisid, _sap);
    });

    testWidgets('cancelling the confirm reads nothing', (tester) async {
      var reads = 0;
      final route = BrowserSignIn(
        findProfiles: () async => [fake('Firefox', 'a')],
        hasSession: (_) async => true,
        readCookies: (_) async {
          reads++;
          return const Ok([]);
        },
      );
      final result = await run(tester, route, () async {
        await tester.tap(find.text('Cancel'));
      });
      expect(result, isNull);
      expect(reads, 0);
    });

    testWidgets('a read error is shown plainly and gives no session', (
      tester,
    ) async {
      final route = BrowserSignIn(
        findProfiles: () async => [fake('Firefox', 'a')],
        hasSession: (_) async => true,
        readCookies: (_) async => const Err(
          Failure(FailureKind.io, "Couldn't read Firefox's cookies"),
        ),
      );
      final result = await run(tester, route, () async {
        await tester.tap(find.byKey(const Key('browserSignIn.confirm')));
      });
      expect(result, isNull);
      expect(find.text("Couldn't read Firefox's cookies"), findsOneWidget);
    });

    testWidgets('no signed-in profile: says so, no dialog', (tester) async {
      final route = BrowserSignIn(
        findProfiles: () async => [fake('Firefox', 'a')],
        hasSession: (_) async => false,
      );
      final result = await run(tester, route, () async {});
      expect(result, isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.textContaining('No browser here is signed in'),
        findsOneWidget,
      );
    });

    test('forget() is a no-op', () async {
      await BrowserSignIn(home: home.path).forget();
    });
  });
}
