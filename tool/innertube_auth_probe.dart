// Dev-only probe of signed-in YouTube Music (Plan 7). Run by hand with the
// real network and the user's own session; never imported by lib/ or by
// tests, and not part of `flutter test` (it lives outside test/):
//
//   flutter test tool/innertube_auth_probe.dart \
//     --dart-define=COOKIES=<path to a Netscape cookies.txt> \
//     --dart-define=OUT=<scratch dir> > <scratch dir>/probe.log
//
// The cookies file is exported by the user from a signed-in browser, lives
// outside the repo and is deleted after the run. Raw responses go to
// <OUT>/raw only; OUT must be outside the repo (the probe fails otherwise).
// Ruling R4: real signed-in responses are never saved as fixtures, scrubbed
// or not, because they reveal the account's listening taste. The committed
// signed-in fixtures are hand-crafted; a shape change found here is
// reproduced in them by hand.
//
// It runs under the Flutter test runner like tool/stream_timing.dart: plain
// `test()`, never `testWidgets()`, so real HTTP works.
//
// About eleven requests in all, two seconds apart, no loops:
//   1. Home signed out (WEB_REMIX, no cookies): the signed-out marker and a
//      visitor id.
//   2. Home with cookies + SAPISIDHASH Authorization.
//   3. Home with cookies only (no Authorization): is the header needed?
//   4. Home with the cookie names but fake values (an expired session).
//   5. VISIONOS `player` for video A, anonymous (as Plan 5 does).
//   6. WEB_REMIX `player` for video B, signed in (account tracking URLs).
//   7-10. One play report each way, sent with the session: A's anonymous
//      tracking URLs, B's signed-in ones (playback + watchtime each). Nothing
//      is played.
//   11. `FEmusic_history`, signed in, once: where A and B appear.
//
// Output holds only statuses, counts, marker names and values (logged_in=1),
// key names and yes/no findings. Never cookie values, SAPISIDHASH, account
// names, emails, channel ids or photo URLs.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _cookiesPath = String.fromEnvironment('COOKIES');
const _outPath = String.fromEnvironment('OUT');

/// Public videos from the Plan 5 probe. A gets the anonymous report, B the
/// signed-in one.
const _videoA = 'fOT0BUpITw8';
const _videoB = '4D7u5KF7SP8';

const _origin = 'https://music.youtube.com';
const _webUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const _webRemix = <String, Object?>{
  'clientName': 'WEB_REMIX',
  'clientVersion': '1.20260707.12.00',
  'userAgent': _webUa,
};
const _visionOs = <String, Object?>{
  'clientName': 'VISIONOS',
  'clientVersion': '1.02',
  'deviceMake': 'Apple',
  'deviceModel': 'RealityDevice17,1',
  'userAgent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  'osName': 'visionOS',
  'osVersion': '26.5.23O471',
};

void main() {
  test('signed-in Innertube probe (real network)', () async {
    if (_outPath.isEmpty) fail('pass --dart-define=OUT=<scratch dir>');
    final out = Directory(_outPath).absolute.path;
    final repo = Directory.current.absolute.path;
    if (_inside(out, repo) ||
        _inside(out, Directory.current.resolveSymbolicLinksSync())) {
      fail('OUT must be outside the repo: raw responses hold account data');
    }
    final raw = Directory('$out/raw')..createSync(recursive: true);
    await _probe(raw);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Whether [path] is [dir] or inside it (both absolute, normalised).
bool _inside(String path, String dir) {
  String norm(String p) =>
      File(p).uri.normalizePath().path.replaceAll(RegExp(r'/+$'), '');
  final p = norm(path);
  final d = norm(dir);
  return p == d || p.startsWith('$d/');
}

// --- Cookies ----------------------------------------------------------------

class _Cookie {
  _Cookie(this.domain, this.name, this.value);
  final String domain;
  final String name;
  final String value;

  bool sentTo(String host) {
    final d = domain.startsWith('.') ? domain.substring(1) : domain;
    return host == d || host.endsWith('.$d');
  }
}

/// Netscape cookies.txt: domain, subdomains, path, secure, expiry, name,
/// value; `#HttpOnly_` marks HttpOnly cookies.
List<_Cookie> _readCookies(String path) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final out = <_Cookie>[];
  for (var line in File(path).readAsLinesSync()) {
    if (line.startsWith('#HttpOnly_')) line = line.substring(10);
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final f = line.split('\t');
    if (f.length < 7) continue;
    final expiry = int.tryParse(f[4]) ?? 0;
    if (expiry != 0 && expiry < now) continue;
    final d = f[0].toLowerCase();
    if (!(d.endsWith('youtube.com') || d.endsWith('google.com'))) continue;
    out.add(_Cookie(d, f[5], f[6]));
  }
  return out;
}

String _cookieHeader(List<_Cookie> all, String host) => all
    .where((c) => c.sentTo(host))
    .map((c) => '${c.name}=${c.value}')
    .join('; ');

String? _cookie(List<_Cookie> all, String name, String host) {
  for (final c in all) {
    if (c.name == name && c.sentTo(host)) return c.value;
  }
  return null;
}

/// ytmusicapi's header: `SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> <origin>")>`.
String _sapisidHash(String sapisid) {
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final h = sha1.convert(utf8.encode('$ts $sapisid $_origin'));
  return 'SAPISIDHASH ${ts}_$h';
}

// --- The probe --------------------------------------------------------------

class _Resp {
  _Resp(this.status, this.json);
  final int status;
  final Map<String, Object?>? json;
}

Future<void> _probe(Directory raw) async {
  if (_cookiesPath.isEmpty) fail('pass --dart-define=COOKIES=<cookies.txt>');
  final cookies = _readCookies(_cookiesPath);
  const host = 'music.youtube.com';
  print('cookies for $host: ${cookies.where((c) => c.sentTo(host)).length}');
  for (final n in [
    'SAPISID',
    '__Secure-1PAPISID',
    '__Secure-3PAPISID',
    'SID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    'HSID',
    'SSID',
    'APISID',
    'LOGIN_INFO',
    'SOCS',
    'VISITOR_INFO1_LIVE',
    'PREF',
  ]) {
    print('  cookie $n present: ${_cookie(cookies, n, host) != null}');
  }
  final sapisid =
      _cookie(cookies, 'SAPISID', host) ??
      _cookie(cookies, '__Secure-3PAPISID', host);
  if (sapisid == null) fail('no SAPISID cookie: not signed in');

  Map<String, String> signedIn({bool auth = true, List<_Cookie>? jar}) => {
    'Cookie': _cookieHeader(jar ?? cookies, host),
    if (auth) 'Authorization': _sapisidHash(sapisid),
    'X-Goog-AuthUser': '0',
    'X-Origin': _origin,
  };

  // 1. Signed out.
  final out = await _innertube(_webRemix, 67, 'browse', {
    'browseId': 'FEmusic_home',
  }, const {});
  _summariseHome('home signed out', out);
  _saveRaw(raw, 'home_signed_out', out);
  final visitor = _str(out.json, ['responseContext', 'visitorData']);

  // 2. Cookies + Authorization.
  await _pause();
  final inAuth = await _innertube(_webRemix, 67, 'browse', {
    'browseId': 'FEmusic_home',
  }, signedIn());
  _summariseHome('home cookies+auth', inAuth);
  _saveRaw(raw, 'home_signed_in', inAuth);

  // 3. Cookies only.
  await _pause();
  final inCookies = await _innertube(_webRemix, 67, 'browse', {
    'browseId': 'FEmusic_home',
  }, signedIn(auth: false));
  _summariseHome('home cookies only', inCookies);
  _saveRaw(raw, 'home_cookies_only', inCookies);

  // 4. An expired session: the same cookie names, fake values.
  await _pause();
  final fakeJar = [
    for (final c in cookies)
      _Cookie(c.domain, c.name, 'FAKE${c.name.hashCode.abs()}expired'),
  ];
  final fakeHeaders = {
    ...signedIn(jar: fakeJar),
    'Authorization': _sapisidHash('FAKEexpiredSAPISID'),
  };
  final expired = await _innertube(_webRemix, 67, 'browse', {
    'browseId': 'FEmusic_home',
  }, fakeHeaders);
  _summariseHome('home expired (fake cookie values)', expired);
  _saveRaw(raw, 'home_expired', expired);

  // 5. Anonymous VISIONOS player for A (Plan 5's route).
  await _pause();
  final playerA = await _innertube(
    _visionOs,
    101,
    'player',
    _playerBody(_videoA),
    const {},
    host: 'www.youtube.com',
    visitor: visitor,
  );
  final trackA = _summarisePlayer(
    'player VISIONOS anonymous $_videoA',
    playerA,
  );

  // 6. Signed-in WEB_REMIX player for B.
  await _pause();
  final playerB = await _innertube(
    _webRemix,
    67,
    'player',
    _playerBody(_videoB),
    signedIn(),
  );
  final trackB = _summarisePlayer(
    'player WEB_REMIX signed in $_videoB',
    playerB,
  );
  if (trackA != null && trackB != null) {
    final a = Uri.parse(trackA.$1).queryParameters.keys.toSet();
    final b = Uri.parse(trackB.$1).queryParameters.keys.toSet();
    print('  playback url params only in signed-in: ${b.difference(a)}');
    print('  playback url params only in anonymous: ${a.difference(b)}');
  }

  // 7-10. One report each way, sent with the session. Nothing is played.
  Map<String, String> reportHeaders(String ua) => {
    'User-Agent': ua,
    'Cookie': _cookieHeader(cookies, 's.youtube.com'),
    'Authorization': _sapisidHash(sapisid),
    'X-Goog-AuthUser': '0',
    'Origin': _origin,
  };
  if (trackA != null) {
    await _report(
      'A anonymous urls + session',
      trackA,
      reportHeaders(_visionOs['userAgent']! as String),
    );
  }
  if (trackB != null) {
    await _report('B signed-in urls + session', trackB, reportHeaders(_webUa));
  }

  // 11. History, once, after a short wait for it to update.
  await Future<void>.delayed(const Duration(seconds: 8));
  final history = await _innertube(_webRemix, 67, 'browse', {
    'browseId': 'FEmusic_history',
  }, signedIn());
  _saveRaw(raw, 'history', history);
  _summariseHistory(history);
}

Future<void> _pause() => Future<void>.delayed(const Duration(seconds: 2));

Map<String, Object?> _playerBody(String video) => {
  'videoId': video,
  'playbackContext': {
    'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
  },
  'contentCheckOk': true,
  'racyCheckOk': true,
};

Future<_Resp> _innertube(
  Map<String, Object?> client,
  int nameId,
  String endpoint,
  Map<String, Object?> body,
  Map<String, String> extra, {
  String host = 'music.youtube.com',
  String? visitor,
}) async {
  final c = Map<String, Object?>.from(client)
    ..['hl'] = 'en'
    ..['utcOffsetMinutes'] = 0;
  if (visitor != null) c['visitorData'] = visitor;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.postUrl(
      Uri.https(host, '/youtubei/v1/$endpoint', {'prettyPrint': 'false'}),
    );
    req.followRedirects = false;
    req.headers
      ..set('Content-Type', 'application/json')
      ..set('User-Agent', c['userAgent']! as String)
      ..set('X-YouTube-Client-Name', '$nameId')
      ..set('X-YouTube-Client-Version', c['clientVersion']! as String)
      ..set('Origin', 'https://$host');
    if (visitor != null) req.headers.set('X-Goog-Visitor-Id', visitor);
    extra.forEach(req.headers.set);
    req.add(
      utf8.encode(
        jsonEncode({
          'context': {'client': c},
          ...body,
        }),
      ),
    );
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await res.transform(utf8.decoder).join();
    Map<String, Object?>? json;
    try {
      json = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      json = null;
    }
    final setCookies = res.cookies.map((c) => c.name).toSet();
    print(
      '$endpoint: HTTP ${res.statusCode}, json ${json != null}'
      '${setCookies.isEmpty ? '' : ', sets cookies named $setCookies'}',
    );
    return _Resp(res.statusCode, json);
  } finally {
    http.close();
  }
}

void _saveRaw(Directory raw, String name, _Resp r) =>
    File('${raw.path}/$name.json')
        .writeAsStringSync(jsonEncode({'status': r.status, 'json': r.json}));

/// Generic YouTube Music shelf titles; anything else prints as `<other>`
/// (a title could hold the account name).
const _knownTitles = {
  'quick picks',
  'listen again',
  'mixed for you',
  'forgotten favorites',
  'forgotten favourites',
  'from the community',
  'new releases',
  'recommended music videos',
  'trending',
  'charts',
  'take it easy',
  'all hits',
  'recommended albums',
  'from your library',
  'long listening',
  'covers and remixes',
  'live performances',
  'recommended radios',
  'today\'s hits',
  'energize',
  'relax',
  'feel good',
  'focus',
  'workout',
  'sleep',
  'commute',
  'party',
  'romance',
  'sad',
  'your favorites',
  'albums for you',
  'music videos for you',
  'similar to',
  'more from',
  'today',
  'yesterday',
  'this week',
  'last week',
  'earlier',
  'this month',
  'last month',
  'keep listening',
  'speed dial',
  'recaps',
  'your shows',
  'shows for you',
};

String _safeTitle(String? t) => t == null
    ? '<none>'
    : (_knownTitles.contains(t.toLowerCase()) ? t : '<other>');

/// `responseContext.serviceTrackingParams[].params` `logged_in`, as
/// `service:value`, and `mainAppWebResponseContext.loggedOut`.
String _markers(Object? json) {
  final stp = _at(json, ['responseContext', 'serviceTrackingParams']);
  final found = <String>[];
  if (stp is List) {
    for (final s in stp) {
      final params = _at(s, ['params']);
      if (params is! List) continue;
      for (final p in params) {
        if (p is Map && p['key'] == 'logged_in') {
          found.add('${_at(s, ['service'])}:logged_in=${p['value']}');
        }
      }
    }
  }
  final loggedOut = _at(json, [
    'responseContext',
    'mainAppWebResponseContext',
    'loggedOut',
  ]);
  return 'markers [${found.join(', ')}], loggedOut=$loggedOut';
}

void _summariseHome(String label, _Resp r) {
  final j = r.json;
  final shelves = <String>[];
  var items = 0;
  _walk(j, (m) {
    final shelf = m['musicCarouselShelfRenderer'];
    if (shelf is! Map) return;
    final title = _runsText(
      _at(shelf, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']),
    );
    final hasStrapline =
        _at(shelf, [
          'header',
          'musicCarouselShelfBasicHeaderRenderer',
          'strapline',
        ]) !=
        null;
    final n = (shelf['contents'] as List?)?.length ?? 0;
    items += n;
    shelves.add('${_safeTitle(title)}($n${hasStrapline ? ', strapline' : ''})');
  });
  var datasync = false;
  var accountKeys = <String>{};
  var accountPhotos = 0;
  _walk(j, (m) {
    for (final k in m.keys) {
      final key = '$k';
      if (key.toLowerCase().contains('datasync')) datasync = true;
      if (key.toLowerCase().contains('account')) accountKeys.add(key);
    }
  });
  _strings(j, '', (k, v) {
    if (v.contains('lh3.googleusercontent.com/a/')) accountPhotos++;
  });
  final error = _at(j, ['error', 'status']);
  print(
    '$label: HTTP ${r.status}${error == null ? '' : ' error $error'}, '
    '${_markers(j)}, ${shelves.length} shelves, $items items, '
    'continuation ${_hasKey(j, 'nextContinuationData') || _hasKey(j, 'continuations')}, '
    'datasyncId $datasync, account keys $accountKeys, '
    'account photo urls $accountPhotos',
  );
  print('  shelves: ${shelves.join(' | ')}');
}

/// Prints the player summary; returns (playbackUrl, watchtimeUrl).
(String, String)? _summarisePlayer(String label, _Resp r) {
  final j = r.json;
  final status = _str(j, ['playabilityStatus', 'status']);
  final playback = _str(j, [
    'playbackTracking',
    'videostatsPlaybackUrl',
    'baseUrl',
  ]);
  final watchtime = _str(j, [
    'playbackTracking',
    'videostatsWatchtimeUrl',
    'baseUrl',
  ]);
  final formats =
      (_at(j, ['streamingData', 'adaptiveFormats']) as List?)?.length ?? 0;
  print(
    '$label: HTTP ${r.status} $status, formats $formats, '
    'playbackTracking ${playback != null}/${watchtime != null}, '
    '${_markers(j)}',
  );
  if (playback == null || watchtime == null) return null;
  return (playback, watchtime);
}

Future<void> _report(
  String label,
  (String, String) tracking,
  Map<String, String> headers,
) async {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final rnd = Random.secure();
  final cpn = String.fromCharCodes(
    List.generate(16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
  );
  Uri add(String url, Map<String, String> q) {
    final u = Uri.parse(url);
    return u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  final base = {'ver': '2', 'cpn': cpn};
  final urls = [
    add(tracking.$1, base),
    add(tracking.$2, {...base, 'st': '0', 'et': '35', 'cmt': '35'}),
  ];
  for (final url in urls) {
    await _pause();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await http.getUrl(url);
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      print('report $label ${url.path}: HTTP ${res.statusCode}');
    } on Object catch (e) {
      print('report $label ${url.path}: failed (${e.runtimeType})');
    } finally {
      http.close();
    }
  }
}

void _summariseHistory(_Resp r) {
  final j = r.json;
  // Video ids in document order, with the index of the shelf they are in.
  final order = <String>[];
  final shelfOf = <String, int>{};
  final shelfTitles = <String>[];
  _walk(j, (m) {
    final shelf = m['musicShelfRenderer'];
    if (shelf is! Map) return;
    final idx = shelfTitles.length;
    shelfTitles.add(_safeTitle(_runsText(shelf['title'])));
    _walk(shelf['contents'], (item) {
      final id = _at(item, ['playlistItemData', 'videoId']);
      if (id is String && !shelfOf.containsKey(id)) {
        order.add(id);
        shelfOf[id] = idx;
      }
    });
  });
  print(
    'history: HTTP ${r.status}, ${_markers(j)}, ${shelfTitles.length} shelves '
    '[${shelfTitles.join(', ')}], ${order.length} songs',
  );
  for (final (name, id) in [('A', _videoA), ('B', _videoB)]) {
    final i = order.indexOf(id);
    print(
      '  $name ($id): ${i < 0 ? 'not in history' : 'position $i, shelf ${shelfOf[id]} '
                '(${shelfTitles[shelfOf[id]!]})'}',
    );
  }
}

// --- JSON helpers -----------------------------------------------------------

Object? _at(Object? v, List<String> path) {
  for (final k in path) {
    if (v is! Map) return null;
    v = v[k];
  }
  return v;
}

String? _str(Object? v, List<String> path) {
  final r = _at(v, path);
  return r is String ? r : null;
}

String? _runsText(Object? text) {
  final runs = _at(text, ['runs']);
  if (runs is! List) return null;
  return runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
}

bool _hasKey(Object? json, String key) {
  var found = false;
  _walk(json, (m) => found = found || m.containsKey(key));
  return found;
}

void _walk(Object? v, void Function(Map m) f) {
  if (v is Map) {
    f(v);
    for (final c in v.values) {
      _walk(c, f);
    }
  } else if (v is List) {
    for (final c in v) {
      _walk(c, f);
    }
  }
}

void _strings(Object? v, String key, void Function(String, String) f) {
  if (v is Map) {
    v.forEach((k, c) => _strings(c, '$k', f));
  } else if (v is List) {
    for (final c in v) {
      _strings(c, key, f);
    }
  } else if (v is String) {
    f(key, v);
  }
}
