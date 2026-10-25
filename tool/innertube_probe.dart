// Dev-only probe for YouTube's Innertube API. Run by hand with the real
// network; never imported by lib/ or by tests.
//
//   dart run tool/innertube_probe.dart [--raw <dir>] [--out <dir>]
//
// It calls `player` for two videos with each candidate client, then the
// YouTube Music (WEB_REMIX) `search`, `browse` and `next` endpoints, prints a
// summary, writes the raw responses to --raw (default build/innertube_raw,
// never committed) and scrubbed, trimmed fixtures to --out (default
// test/fixtures/innertube). See docs/innertube-notes.md.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const _videos = ['fOT0BUpITw8', '4D7u5KF7SP8'];

/// Candidate player clients, from yt-dlp's INNERTUBE_CLIENTS (master,
/// fetched 2026-10-25): name, version, nameId, user agent, extra fields.
const _playerClients = <String, Map<String, Object?>>{
  'visionos': {
    'nameId': 101,
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'userAgent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
    },
  },
  'android_vr': {
    'nameId': 28,
    'client': {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.65.10',
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'userAgent': 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      'osName': 'Android',
      'osVersion': '12L',
    },
  },
  'tv': {
    'nameId': 7,
    'client': {
      'clientName': 'TVHTML5',
      'clientVersion': '7.20260707.07.00',
      'userAgent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
    },
  },
  'ios': {
    'nameId': 5,
    'client': {
      'clientName': 'IOS',
      'clientVersion': '21.26.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'userAgent': 'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  },
};

const _webRemix = <String, Object?>{
  'nameId': 67,
  'client': {
    'clientName': 'WEB_REMIX',
    'clientVersion': '1.20260707.12.00',
    'userAgent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
  },
};

String? _visitor;
final _visitorsSeen = <String>{};
final _ips = <String>{};
late Directory _raw;
late Directory _out;

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  _raw = Directory(arg('--raw', 'build/innertube_raw'))
    ..createSync(recursive: true);
  _out = Directory(arg('--out', 'test/fixtures/innertube'))
    ..createSync(recursive: true);

  await _consentProbe();

  // Before any visitor id exists: YouTube asks the player clients to sign in.
  final bare = await _player(_playerClients['visionos']!, '4D7u5KF7SP8');
  await _summarisePlayer(
    'visionos (no visitor)',
    '4D7u5KF7SP8',
    bare,
    _playerClients['visionos']!,
  );
  _save('player_visionos_no_visitor_4D7u5KF7SP8', bare, raw: true);
  _visitor = null;

  // WEB_REMIX first so a visitor id exists for the player calls, the way
  // the app will behave.
  final home = await _post(_webRemix, 'music.youtube.com', 'browse', {
    'browseId': 'FEmusic_home',
  });
  print(
    'home: status ${home.status}, '
    'visitorData ${_str(home.json, ['responseContext', 'visitorData']) != null}',
  );
  _save('browse_home', home, raw: true);

  for (final video in _videos) {
    for (final e in _playerClients.entries) {
      final r = await _player(e.value, video);
      await _summarisePlayer(e.key, video, r, e.value);
      _save('player_${e.key}_$video', r, raw: true);
    }
  }

  final all = await _post(_webRemix, 'music.youtube.com', 'search', {
    'query': 'daft punk',
  });
  print('search all: status ${all.status}');
  _save('search_all', all, raw: true);
  final chips = _chipParams(all.json);
  print('search filter chips: ${jsonEncode(chips)}');

  final songsParams = chips['Songs'];
  if (songsParams != null) {
    final songs = await _post(_webRemix, 'music.youtube.com', 'search', {
      'query': 'daft punk',
      'params': songsParams,
    });
    print('search songs: status ${songs.status}');
    _save('search_songs', songs, raw: true);
  }

  final ids = _pageIds(all.json);
  print('page ids from search: ${jsonEncode(ids)}');
  for (final kind in ['ARTIST', 'ALBUM', 'PLAYLIST']) {
    final id = ids[kind];
    if (id == null) continue;
    final r = await _post(_webRemix, 'music.youtube.com', 'browse', {
      'browseId': id,
    });
    print('browse $kind $id: status ${r.status}');
    _save('browse_${kind.toLowerCase()}', r, raw: true);
  }

  final next = await _post(_webRemix, 'music.youtube.com', 'next', {
    'videoId': '4D7u5KF7SP8',
    'playlistId': 'RDAMVM4D7u5KF7SP8',
    'params': 'wAEB',
    'isAudioOnly': true,
    'enablePersistentPlaylistPanel': true,
    'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
  });
  print('next radio: status ${next.status}');
  _save('next_radio', next, raw: true);

  print('client IPs seen (scrubbed): ${_ips.length}');
  _verifyScrubbed();
}

Future<_Resp> _player(Map<String, Object?> id, String video) =>
    _post(id, 'www.youtube.com', 'player', {
      'videoId': video,
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    });

class _Resp {
  _Resp(this.status, this.json, this.headers);
  final int status;
  final Map<String, Object?>? json;
  final Map<String, List<String>> headers;
}

Future<_Resp> _post(
  Map<String, Object?> id,
  String host,
  String endpoint,
  Map<String, Object?> body,
) async {
  final client = Map<String, Object?>.from(id['client']! as Map)
    ..['hl'] = 'en'
    ..['gl'] = 'US'
    ..['timeZone'] = 'UTC'
    ..['utcOffsetMinutes'] = 0;
  if (_visitor != null) client['visitorData'] = _visitor;
  final full = {
    'context': {'client': client},
    ...body,
  };
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.postUrl(
      Uri.https(host, '/youtubei/v1/$endpoint', {'prettyPrint': 'false'}),
    );
    req.followRedirects = false;
    req.headers
      ..set('Content-Type', 'application/json')
      ..set('User-Agent', client['userAgent']! as String)
      ..set('X-YouTube-Client-Name', '${id['nameId']}')
      ..set('X-YouTube-Client-Version', client['clientVersion']! as String)
      ..set('Origin', 'https://$host');
    if (_visitor != null) req.headers.set('X-Goog-Visitor-Id', _visitor!);
    req.add(utf8.encode(jsonEncode(full)));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    final headers = <String, List<String>>{};
    res.headers.forEach((k, v) => headers[k] = v);
    Map<String, Object?>? json;
    try {
      json = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      json = null;
    }
    final vd = _str(json, ['responseContext', 'visitorData']);
    if (vd != null) _visitorsSeen.add(vd);
    if (_visitor == null && vd != null) _visitor = vd;
    final loc = res.headers.value('location');
    if (loc != null) print('  $endpoint redirect -> ${loc.split('?').first}');
    final cookies = res.cookies.map((c) => c.name).toSet();
    if (cookies.isNotEmpty) print('  $endpoint sets cookies: $cookies');
    return _Resp(res.statusCode, json, headers);
  } finally {
    http.close();
  }
}

/// GETs the YouTube Music page without cookies to see whether this network
/// is sent to consent.youtube.com, then with the SOCS cookie the open-source
/// clients use.
Future<void> _consentProbe() async {
  for (final socs in [null, 'CAI']) {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await http.getUrl(Uri.https('music.youtube.com', '/'));
      req.followRedirects = false;
      req.headers.set(
        'User-Agent',
        (_webRemix['client']! as Map)['userAgent']! as String,
      );
      if (socs != null) req.headers.set('Cookie', 'SOCS=$socs');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      final loc = res.headers.value('location');
      print(
        'consent GET (SOCS=${socs ?? 'none'}): ${res.statusCode}'
        '${loc == null ? '' : ' -> ${loc.split('?').first}'}'
        ', consent text in page: ${body.contains('consent.youtube.com')}',
      );
    } finally {
      http.close();
    }
  }
}

Future<void> _summarisePlayer(
  String name,
  String video,
  _Resp r,
  Map<String, Object?> id,
) async {
  final j = r.json;
  final status = _str(j, ['playabilityStatus', 'status']);
  final reason = _str(j, ['playabilityStatus', 'reason']);
  final formats =
      ((_at(j, ['streamingData', 'adaptiveFormats']) as List?) ?? const [])
          .cast<Map>();
  final audio = formats
      .where((f) => '${f['mimeType']}'.startsWith('audio/'))
      .toList();
  final plain = audio.where((f) => f['url'] != null).length;
  final ciphered = audio.where((f) => f['signatureCipher'] != null).length;
  final sabr = _at(j, ['streamingData', 'serverAbrStreamingUrl']) != null;
  final tracking = _at(j, ['playbackTracking']) != null;
  final itags = audio.map((f) => '${f['itag']}').join(',');
  print(
    'player $name $video: HTTP ${r.status} $status'
    '${reason == null ? '' : ' ($reason)'}; audio ${audio.length} '
    '[$itags] plain url $plain, signatureCipher $ciphered, sabr $sabr, '
    'playbackTracking $tracking',
  );
  if (plain == 0) return;
  // Can the plain URL actually be fetched? One small ranged GET.
  final best = audio.firstWhere(
    (f) => f['itag'] == 251 && f['url'] != null,
    orElse: () => audio.firstWhere((f) => f['url'] != null),
  );
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.getUrl(Uri.parse(best['url'] as String));
    req.headers
      ..set('User-Agent', (id['client']! as Map)['userAgent']! as String)
      ..set('Range', 'bytes=0-1023');
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain<void>();
    print(
      '  ranged GET itag ${best['itag']}: ${res.statusCode} '
      '${res.headers.contentType}',
    );
  } on Object catch (e) {
    print('  ranged GET failed: $e');
  } finally {
    http.close();
  }
}

/// The `params` of each WEB_REMIX search filter chip, by chip label.
Map<String, String> _chipParams(Object? json) {
  final out = <String, String>{};
  _walk(json, (m) {
    final chip = m['chipCloudChipRenderer'];
    if (chip is! Map) return;
    final label = _runsText(chip['text']);
    final params = _at(chip, [
      'navigationEndpoint',
      'searchEndpoint',
      'params',
    ]);
    if (label != null && params is String) out[label] = params;
  });
  return out;
}

/// The first browseId of each music page type (ARTIST, ALBUM, PLAYLIST).
Map<String, String> _pageIds(Object? json) {
  final out = <String, String>{};
  _walk(json, (m) {
    final be = m['browseEndpoint'];
    if (be is! Map) return;
    final type = _at(be, [
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
      'pageType',
    ]);
    final id = be['browseId'];
    if (type is String && id is String) {
      final kind = type.replaceFirst('MUSIC_PAGE_TYPE_', '');
      out.putIfAbsent(kind, () => id);
    }
  });
  return out;
}

void _save(String name, _Resp r, {bool raw = false}) {
  final doc = {'status': r.status, 'json': r.json};
  if (raw) File('${_raw.path}/$name.json').writeAsStringSync(jsonEncode(doc));
  // Compact, to keep the repo small; read them with jq.
  final scrubbed = _scrub(_trim(r.json), null);
  File('${_out.path}/$name.json').writeAsStringSync(
    '${jsonEncode({'status': r.status, 'json': scrubbed})}\n',
  );
}

// --- Trimming ---------------------------------------------------------------

/// Keys dropped from fixtures: large and not read by the app.
const _dropKeys = {
  'frameworkUpdates',
  'serviceTrackingParams',
  'mainAppWebResponseContext',
  'webResponseContextExtensionData',
  'storyboards',
  'attestation',
  'playerConfig',
  'adPlacements',
  'playerAds',
  'adSlots',
  'annotations',
  'endscreen',
  'cards',
  'captions',
  'heartbeatParams',
  'paidContentOverlay',
  'messages',
  'auxiliaryUi',
  'adBreakHeartbeatParams',
  'playerSettingsMenuData',
  'description',
  // Sign-in prompts behind like/save buttons.
  'modalEndpoint',
};

/// Carousels (home, artist and search shelves) are cut to this many items.
/// Lists of shelves, `musicShelfRenderer` lists (search results, album and
/// playlist tracks) and the radio queue are never cut.
const _maxCarouselItems = 6;

/// Menu entries kept: navigation to a page or a radio (Go to artist/album,
/// Start radio). Service entries (queue, library, feedback) and sign-in
/// prompts are dropped; they are most of a page.
bool _keepMenuItem(Object? item) {
  final nav = _at(item, ['menuNavigationItemRenderer', 'navigationEndpoint']);
  return nav is Map &&
      (nav.containsKey('browseEndpoint') ||
          nav.containsKey('watchEndpoint') ||
          nav.containsKey('watchPlaylistEndpoint'));
}

/// The radio queue keeps this many songs (Task 3 needs 20 or more).
const _maxRadioItems = 25;

Object? _trim(Object? v, [String? parent]) {
  if (v is Map) {
    final out = <String, Object?>{};
    for (final e in v.entries) {
      final k = e.key as String;
      if (_dropKeys.contains(k)) continue;
      var child = e.value;
      if (child is List &&
          parent == 'musicCarouselShelfRenderer' &&
          k == 'contents' &&
          child.length > _maxCarouselItems) {
        child = child.sublist(0, _maxCarouselItems);
      }
      if (child is List && parent == 'menuRenderer' && k == 'items') {
        child = child.where(_keepMenuItem).toList();
      }
      if (child is List &&
          parent == 'playlistPanelRenderer' &&
          k == 'contents' &&
          child.length > _maxRadioItems) {
        child = child.sublist(0, _maxRadioItems);
      }
      out[k] = _trim(child, k);
    }
    return out;
  }
  if (v is List) return v.map((x) => _trim(x, parent)).toList();
  return v;
}

// --- Scrubbing --------------------------------------------------------------

const _fakeIp = '203.0.113.1';

/// Keys whose string values are tokens: replaced by a fixed fake string.
const _tokenKeys = {
  'visitorData': 'FAKE_VISITOR_DATA',
  'trackingParams': 'FAKE_TRACKING_PARAMS',
  'clickTrackingParams': 'FAKE_TRACKING_PARAMS',
  'serializedShareEntity': 'FAKE_SHARE_ENTITY',
  'continuation': 'FAKE_CONTINUATION',
  'token': 'FAKE_TOKEN',
  'playerResponseToken': 'FAKE_TOKEN',
  'eventId': 'FAKE_EVENT_ID',
  'serializedContextData': 'FAKE_CONTEXT_DATA',
  'responseId': 'FAKE_RESPONSE_ID',
  'rolloutToken': 'FAKE_ROLLOUT_TOKEN',
  'queueContextParams': 'FAKE_QUEUE_CONTEXT_PARAMS',
};

/// Any key naming visitor data (visitorData, updatedVisitorData, ...).
bool _isVisitorKey(String? key) =>
    key != null && key.toLowerCase().contains('visitordata');

/// URL query parameters scrubbed from every URL (including those inside a
/// `signatureCipher`): the client ip and per-session tokens.
const _urlParams = {
  'ip': _fakeIp,
  'ei': 'FAKE_EI',
  'vm': 'FAKE_VM',
  'sig': 'FAKE_SIG',
  'lsig': 'FAKE_LSIG',
  'n': 'FAKE_N',
  'pot': 'FAKE_POT',
  'cpn': 'FAKE_CPN',
  'of': 'FAKE_OF',
  's': 'FAKE_S',
  // The visitor id inside consent.youtube.com links.
  'vd': 'FAKE_VISITOR_DATA',
  'id': 'FAKE_ID',
  'plid': 'FAKE_PLID',
  'oid': 'FAKE_OID',
  'bui': 'FAKE_BUI',
  'spc': 'FAKE_SPC',
  'xpc': 'FAKE_XPC',
  'fexp': 'FAKE_FEXP',
  'initcwndbps': 'FAKE_CWND',
  // Country and the CDN nodes near the client.
  'gcr': 'zz',
  'mn': 'sn-fake',
  'playback_host': 'rr1---sn-fake.googlevideo.com',
};

Object? _scrub(Object? v, String? key) {
  if (v is Map) {
    return {for (final e in v.entries) e.key: _scrub(e.value, e.key as String)};
  }
  if (v is List) return v.map((x) => _scrub(x, key)).toList();
  if (v is String) {
    final fake = _isVisitorKey(key) ? 'FAKE_VISITOR_DATA' : _tokenKeys[key];
    if (fake != null) return fake;
    if (key == 'signatureCipher') {
      final q = Uri.splitQueryString(v);
      return Uri(
        queryParameters: {
          for (final e in q.entries)
            e.key: e.key == 'url'
                ? _scrubUrl(e.value)
                : (_urlParams[e.key] ?? e.value),
        },
      ).query;
    }
    if (v.startsWith('https://')) return _scrubUrl(v);
  }
  return v;
}

String _scrubUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  // Manifest URLs carry parameters as /key/value/ path pairs.
  final segs = [...uri.pathSegments];
  for (var i = 0; i + 1 < segs.length; i++) {
    final fake = _urlParams[segs[i]];
    if (fake == null) continue;
    if (segs[i] == 'ip') _ips.add(segs[i + 1]);
    segs[i + 1] = fake;
    i++;
  }
  final ip = uri.queryParameters['ip'];
  if (ip != null) _ips.add(ip);
  // Edit the query text in place so parameter order and encoding stay.
  final parts = uri.query.isEmpty
      ? null
      : uri.query
            .split('&')
            .map((p) {
              final eq = p.indexOf('=');
              final k = eq < 0 ? p : p.substring(0, eq);
              final fake = _urlParams[k];
              return fake == null ? p : '$k=$fake';
            })
            .join('&');
  // rrN---sn-<node>.googlevideo.com names the CDN node near the client.
  final host = uri.host.replaceFirst(
    RegExp(r'^rr(\d+)---sn-[a-z0-9-]+\.googlevideo\.com$'),
    'rr1---sn-fake.googlevideo.com',
  );
  return uri.replace(host: host, pathSegments: segs, query: parts).toString();
}

/// Fails loudly if any fixture still holds a seen client IP or visitor id.
void _verifyScrubbed() {
  final secrets = {..._ips, ..._visitorsSeen};
  final ipTail = RegExp(r'^\d+\.\d+\.\d+\.\d+$');
  for (final f in _out.listSync().whereType<File>()) {
    final text = f.readAsStringSync();
    for (final s in secrets) {
      if (text.contains(s) || text.contains(Uri.encodeComponent(s))) {
        throw StateError('${f.path} still contains a secret');
      }
    }
    _checkNoCdnNodes(f, text);
    _checkNoVisitorShaped(f);
    // Any IPv4 address other than the fake one is suspicious.
    for (final m in RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').allMatches(text)) {
      final s = m.group(0)!;
      if (s != _fakeIp && ipTail.hasMatch(s) && !s.startsWith('0.')) {
        print('  note: ${f.path} has $s (check it is not an IP)');
      }
    }
  }
  print('scrub check passed');
}

/// Decodes a token-like string as url-safe or standard base64 (padding
/// optional). Null when it is not base64.
List<int>? _decodeB64(String s) {
  if (s.length < 8 || !RegExp(r'^[A-Za-z0-9_\-+/]+={0,2}$').hasMatch(s)) {
    return null;
  }
  final n = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  try {
    return base64.decode(base64.normalize(n));
  } on FormatException {
    return null;
  }
}

/// Real visitor data is a protobuf starting 0x0A 0x0B + an 11-char id.
bool _visitorShaped(String s) {
  final b = _decodeB64(s);
  return b != null && b.length >= 13 && b[0] == 0x0A && b[1] == 0x0B;
}

/// Fails if any string value in a fixture is visitor-shaped, or a
/// rolloutToken/queueContextParams is not a FAKE_ placeholder.
void _checkNoVisitorShaped(File f) {
  _walk(jsonDecode(f.readAsStringSync()), (m) {
    for (final e in m.entries) {
      final v = e.value;
      if (v is! String) continue;
      if (_visitorShaped(v)) {
        throw StateError('${f.path} has a visitor-shaped value at ${e.key}');
      }
      final k = '${e.key}';
      if ((k == 'rolloutToken' || k == 'queueContextParams') &&
          !v.startsWith('FAKE_')) {
        throw StateError('${f.path} has an unscrubbed $k');
      }
    }
  });
}

void _checkNoCdnNodes(File f, String text) {
  final node = RegExp(r'sn-[a-z0-9]+-[a-z0-9]+').firstMatch(text);
  if (node != null) throw StateError('${f.path} names CDN node ${node[0]}');
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
