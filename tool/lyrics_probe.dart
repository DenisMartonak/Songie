// Dev-only probe for the lyrics sources. Run by hand with the real network;
// never imported by lib/ or by tests.
//
//   dart run tool/lyrics_probe.dart --out <dir outside the repo>
//
// For two well-known songs it calls LRCLIB `/api/get` and `/api/search`, then
// YouTube Music (WEB_REMIX, signed out) `next` and the lyrics-tab `browse`,
// then the ANDROID_MUSIC client that ytmusicapi uses for timed lyrics. It
// prints each response's shape and writes the raw responses to --out. Raw
// responses are never committed; fixtures are hand-made from the shapes.
// See docs/innertube-notes.md, "Lyrics".
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const _songs = <Map<String, Object?>>[
  {
    'key': 'rick',
    'videoId': 'dQw4w9WgXcQ',
    'artist': 'Rick Astley',
    'track': 'Never Gonna Give You Up',
    'album': 'Whenever You Need Somebody',
    'duration': 213,
  },
  {
    'key': 'queen',
    'videoId': 'fJ9rUzIMcZQ',
    'artist': 'Queen',
    'track': 'Bohemian Rhapsody',
    'album': 'A Night at the Opera',
    'duration': 354,
  },
];

const _ua = 'Songies/1.0.0 (https://github.com/DenisMartonak/Songie)';

const _webRemix = <String, Object?>{
  'nameId': 67,
  'client': {
    'clientName': 'WEB_REMIX',
    'clientVersion': '1.20260707.12.00',
    'userAgent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
  },
};

// ytmusicapi's timed-lyrics identity.
const _androidMusic = <String, Object?>{
  'nameId': 21,
  'client': {
    'clientName': 'ANDROID_MUSIC',
    'clientVersion': '7.21.50',
    'androidSdkVersion': 30,
    'userAgent': 'com.google.android.apps.youtube.music/7.21.50 (Linux; U; Android 11) gzip',
  },
};

late Directory _out;
String? _visitor;

Future<void> main(List<String> args) async {
  final i = args.indexOf('--out');
  if (i < 0 || i + 1 >= args.length) {
    stderr.writeln('usage: dart run tool/lyrics_probe.dart --out <dir>');
    exit(64);
  }
  _out = Directory(args[i + 1]);
  final outPath = _out.absolute.uri.normalizePath().toFilePath();
  final repo = _repoRoot();
  if (repo != null && outPath.startsWith(repo)) {
    stderr.writeln('refusing --out inside the repo ($outPath)');
    exit(64);
  }
  _out.createSync(recursive: true);

  for (final s in _songs) {
    final key = s['key']! as String;
    print('\n=== ${s['track']} (${s['videoId']}) ===');
    await _lrclib(key, s);
    await _youtube(key, s);
  }
}

/// The folder holding pubspec.yaml above the working directory, if any.
String? _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.uri.normalizePath().toFilePath();
    }
    if (dir.parent.path == dir.path) return null;
    dir = dir.parent;
  }
}

void _save(String name, Object? json) {
  File('${_out.path}/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));
}

Future<Object?> _get(Uri uri) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.getUrl(uri);
    req.headers.set('User-Agent', _ua);
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    print('GET ${uri.path} -> ${res.statusCode}');
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  } finally {
    http.close();
  }
}

Future<void> _lrclib(String key, Map<String, Object?> s) async {
  final get = await _get(
    Uri.https('lrclib.net', '/api/get', {
      'artist_name': s['artist']! as String,
      'track_name': s['track']! as String,
      'album_name': s['album']! as String,
      'duration': '${s['duration']}',
    }),
  );
  _save('lrclib_get_$key', get);
  if (get is Map) {
    print('  get keys: ${get.keys.toList()}');
    print(
      '  duration ${get['duration']}, instrumental ${get['instrumental']}, '
      'syncedLyrics ${(get['syncedLyrics'] as String?)?.length ?? 'null'} chars, '
      'plainLyrics ${(get['plainLyrics'] as String?)?.length ?? 'null'} chars',
    );
    final synced = get['syncedLyrics'] as String?;
    if (synced != null) {
      print(
        '  synced line shape: ${synced.split('\n').first.replaceAll(RegExp(r'\](.*)'), '] <text>')}',
      );
    }
  }
  final search = await _get(
    Uri.https('lrclib.net', '/api/search', {
      'artist_name': s['artist']! as String,
      'track_name': s['track']! as String,
    }),
  );
  _save('lrclib_search_$key', search);
  if (search is List) {
    print('  search: ${search.length} results');
    for (final r in search.take(8).whereType<Map>()) {
      print(
        '   id ${r['id']} dur ${r['duration']} instr ${r['instrumental']} '
        'synced ${r['syncedLyrics'] != null} plain ${r['plainLyrics'] != null}',
      );
    }
  }
}

Future<void> _youtube(String key, Map<String, Object?> s) async {
  final next = await _post(_webRemix, 'next', {
    'videoId': s['videoId'],
    'playlistId': 'RDAMVM${s['videoId']}',
    'params': 'wAEB',
    'isAudioOnly': true,
    'enablePersistentPlaylistPanel': true,
    'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
  });
  _save('ytm_next_$key', next.json);
  final tabs = _find(next.json, [
    'contents',
    'singleColumnMusicWatchNextResultsRenderer',
    'tabbedRenderer',
    'watchNextTabbedResultsRenderer',
    'tabs',
  ]);
  print('next ${next.status}: tabs ${tabs is List ? tabs.length : 'none'}');
  String? lyricsId;
  if (tabs is List) {
    for (var t = 0; t < tabs.length; t++) {
      final r = (tabs[t] as Map)['tabRenderer'] as Map?;
      print(
        '  tab $t: title ${r?['title']}, endpoint ${r?['endpoint'] == null ? 'none' : jsonEncode(r!['endpoint'])}, unselectable ${r?['unselectable']}',
      );
      final id = _find(r, ['endpoint', 'browseEndpoint', 'browseId']);
      if (id is String && id.startsWith('MPLY')) lyricsId = id;
    }
  }
  print(
    '  lyrics browse id: ${lyricsId == null ? 'none' : '$lyricsId (path tabs[1].tabRenderer.endpoint.browseEndpoint.browseId)'}',
  );
  if (lyricsId == null) return;

  final browse = await _post(_webRemix, 'browse', {'browseId': lyricsId});
  _save('ytm_browse_lyrics_$key', browse.json);
  print('browse ${browse.status}: top keys ${browse.json?.keys.toList()}');
  final shelf = _find(browse.json, [
    'contents',
    'sectionListRenderer',
    'contents',
    0,
    'musicDescriptionShelfRenderer',
  ]);
  if (shelf is Map) {
    print('  musicDescriptionShelfRenderer keys ${shelf.keys.toList()}');
    final text = _find(shelf, ['description', 'runs', 0, 'text']);
    print(
      '  description.runs[0].text ${text is String ? '${text.length} chars' : 'none'}',
    );
    print('  footer ${jsonEncode(_find(shelf, ['footer', 'runs']))}');
  } else {
    print(
      '  no musicDescriptionShelfRenderer; json head: ${jsonEncode(browse.json).substring(0, 300)}',
    );
  }

  final timed = await _post(_androidMusic, 'browse', {'browseId': lyricsId});
  _save('ytm_browse_lyrics_android_$key', timed.json);
  final s0 = jsonEncode(timed.json);
  print(
    'ANDROID_MUSIC browse ${timed.status}: timedLyricsModel ${s0.contains('timedLyricsModel')}, timedLyricsData ${s0.contains('timedLyricsData')}, musicDescriptionShelf ${s0.contains('musicDescriptionShelfRenderer')}',
  );
  if (timed.json != null) print('  top keys ${timed.json!.keys.toList()}');
  if (s0.length < 600) print('  body: $s0');
}

dynamic _find(Object? node, List<Object> path) {
  var cur = node;
  for (final p in path) {
    if (p is int) {
      if (cur is List && p < cur.length) {
        cur = cur[p];
      } else {
        return null;
      }
    } else if (cur is Map) {
      cur = cur[p];
    } else {
      return null;
    }
  }
  return cur;
}

class _Resp {
  _Resp(this.status, this.json);
  final int status;
  final Map<String, Object?>? json;
}

Future<_Resp> _post(
  Map<String, Object?> id,
  String endpoint,
  Map<String, Object?> body,
) async {
  final client = Map<String, Object?>.from(id['client']! as Map)
    ..['hl'] = 'en'
    ..['gl'] = 'US'
    ..['timeZone'] = 'UTC'
    ..['utcOffsetMinutes'] = 0;
  if (_visitor != null) client['visitorData'] = _visitor;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.postUrl(
      Uri.https('music.youtube.com', '/youtubei/v1/$endpoint', {
        'prettyPrint': 'false',
      }),
    );
    req.followRedirects = false;
    req.headers
      ..set('Content-Type', 'application/json')
      ..set('User-Agent', client['userAgent']! as String)
      ..set('X-YouTube-Client-Name', '${id['nameId']}')
      ..set('X-YouTube-Client-Version', client['clientVersion']! as String)
      ..set('Origin', 'https://music.youtube.com');
    if (_visitor != null) req.headers.set('X-Goog-Visitor-Id', _visitor!);
    req.add(
      utf8.encode(
        jsonEncode({
          'context': {'client': client},
          ...body,
        }),
      ),
    );
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    Map<String, Object?>? json;
    try {
      json = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      json = null;
    }
    final vd = _find(json, ['responseContext', 'visitorData']);
    if (_visitor == null && vd is String) _visitor = vd;
    return _Resp(res.statusCode, json);
  } finally {
    http.close();
  }
}
