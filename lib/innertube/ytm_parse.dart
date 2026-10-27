import '../core/log.dart';
import 'ytm_models.dart';

/// Defensive parsers for YouTube Music responses. Every parser returns `null`
/// (or an empty list) when a piece it needs is missing and never throws: a
/// changed shape only drops that row, and the drop is logged.

typedef Json = Map<String, Object?>;

const _separators = {'&', ',', '•'};
const _typeWords = {
  'Song',
  'Video',
  'Album',
  'Single',
  'EP',
  'Artist',
  'Playlist',
  'Podcast',
  'Episode',
  'Profile',
};

// Small accessors.
Json? _map(Object? v) => v is Map ? v.cast<String, Object?>() : null;
List<Object?> _list(Object? v) => v is List ? v.cast<Object?>() : const [];
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Follows [path] (map keys and list indexes); null when any step is missing.
Object? dig(Object? v, List<Object> path) {
  for (final k in path) {
    if (k is int) {
      final l = _list(v);
      if (k >= l.length) return null;
      v = l[k];
    } else {
      final m = _map(v);
      if (m == null) return null;
      v = m[k];
    }
  }
  return v;
}

List<Json> _runs(Object? text) => [
  for (final r in _list(_map(text)?['runs']))
    if (_map(r) != null) _map(r)!,
];

String? _runsText(List<Json> runs) {
  final s = runs.map((r) => (r['text'] as String?) ?? '').join().trim();
  return s.isEmpty ? null : s;
}

String? _browseId(Json run) =>
    _str(dig(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']));

String? _pageType(Object? endpointHolder) => _str(
  dig(endpointHolder, [
    'browseEndpoint',
    'browseEndpointContextSupportedConfigs',
    'browseEndpointContextMusicConfig',
    'pageType',
  ]),
);

/// Splits subtitle runs at the " • " separators.
List<List<Json>> _groups(List<Json> runs) {
  final out = <List<Json>>[[]];
  for (final r in runs) {
    if ((r['text'] as String?)?.trim() == '•') {
      out.add([]);
    } else {
      out.last.add(r);
    }
  }
  return [
    for (final g in out)
      if (g.isNotEmpty) g,
  ];
}

/// Drops a leading "Song" / "Album" / ... word the all tab adds.
List<List<Json>> _withoutType(List<List<Json>> groups) {
  if (groups.length > 1 &&
      groups.first.length == 1 &&
      _typeWords.contains((groups.first.first['text'] as String?)?.trim())) {
    return groups.sublist(1);
  }
  return groups;
}

final _durationRe = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');

int? parseDurationMs(String? s) {
  if (s == null || !_durationRe.hasMatch(s.trim())) return null;
  var seconds = 0;
  for (final part in s.trim().split(':')) {
    seconds = seconds * 60 + int.parse(part);
  }
  return seconds * 1000;
}

/// The largest thumbnail, rewritten to 544 px where the URL has a size.
String? bestThumbnail(Object? thumbnails) {
  String? best;
  var bestWidth = -1;
  for (final t in _list(thumbnails)) {
    final m = _map(t);
    final url = _str(m?['url']);
    if (url == null) continue;
    final w = m?['width'] is num ? (m!['width']! as num).toInt() : 0;
    if (w > bestWidth) {
      bestWidth = w;
      best = url;
    }
  }
  return best?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
}

/// Artists, album and duration read from a subtitle's runs.
class _SongMeta {
  _SongMeta(this.artists, this.album, this.albumBrowseId, this.durationMs);
  final List<YtmArtistRef> artists;
  final String? album;
  final String? albumBrowseId;
  final int? durationMs;
}

_SongMeta _songMeta(List<Json> runs, {String? durationText}) {
  final groups = _withoutType(_groups(runs));
  final artists = <YtmArtistRef>[];
  String? album;
  String? albumId;
  int? duration = parseDurationMs(durationText);
  for (final r in runs) {
    final id = _browseId(r);
    final name = _str(r['text']);
    if (id == null || name == null) continue;
    final type = _pageType(r['navigationEndpoint']);
    if (type == 'MUSIC_PAGE_TYPE_ARTIST' || id.startsWith('UC')) {
      artists.add(YtmArtistRef(browseId: id, name: name));
    } else if (album == null &&
        (type == 'MUSIC_PAGE_TYPE_ALBUM' || id.startsWith('MPRE'))) {
      album = name;
      albumId = id;
    }
  }
  if (artists.isEmpty && groups.isNotEmpty) {
    for (final r in groups.first) {
      final name = _str(r['text']);
      if (name != null && !_separators.contains(name.trim())) {
        artists.add(YtmArtistRef(name: name.trim()));
      }
    }
  }
  if (duration == null) {
    for (final g in groups.reversed) {
      duration = parseDurationMs(_runsText(g));
      if (duration != null) break;
    }
  }
  return _SongMeta(artists, album, albumId, duration);
}

bool _isVideoType(String? musicVideoType, bool typeWordIsVideo) {
  if (musicVideoType == null) return typeWordIsVideo;
  return !(musicVideoType.endsWith('_ATV') ||
      musicVideoType.endsWith('_OFFICIAL_SOURCE_MUSIC'));
}

T? _guard<T>(String what, T? Function() parse) {
  try {
    return parse();
  } catch (e) {
    AppLog.i('ytm parse: $what failed: $e');
    return null;
  }
}

/// A `musicResponsiveListItemRenderer` as a song, video, album, artist or
/// playlist; null for anything else (episodes, podcasts, profiles) or a row
/// with a missing piece.
Object? parseListItem(Object? renderer) => _guard('list item', () {
  final r = _map(renderer);
  if (r == null) return null;
  final cols = [
    for (final c in _list(r['flexColumns']))
      _runs(dig(c, ['musicResponsiveListItemFlexColumnRenderer', 'text'])),
  ];
  if (cols.isEmpty) return null;
  final title = _runsText(cols[0]);
  if (title == null) {
    AppLog.i('ytm parse: list item without a title dropped');
    return null;
  }
  final subtitle = cols.length > 1 ? cols[1] : const <Json>[];
  final groups = _groups(subtitle);
  final typeWord = groups.isNotEmpty && groups.first.length == 1
      ? (groups.first.first['text'] as String?)?.trim()
      : null;
  final thumb = bestThumbnail(
    dig(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']),
  );
  final play = dig(r, [
    'overlay',
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
  ]);
  final nav = r['navigationEndpoint'];
  final pageType = _pageType(nav);
  final browseId = _str(dig(nav, ['browseEndpoint', 'browseId']));

  if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' && browseId != null) {
    final rest = _withoutType(groups);
    String? year;
    for (final g in rest) {
      final t = _runsText(g);
      if (t != null && RegExp(r'^\d{4}$').hasMatch(t)) year = t;
    }
    return YtmAlbum(
      browseId: browseId,
      title: title,
      artist: rest.isEmpty ? null : _runsText(rest.first),
      year: year,
      thumbnailUrl: thumb,
      playlistId: _str(dig(play, ['watchPlaylistEndpoint', 'playlistId'])),
    );
  }
  if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' && browseId != null) {
    return YtmArtist(browseId: browseId, name: title, thumbnailUrl: thumb);
  }
  if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' && browseId != null) {
    final rest = _withoutType(groups);
    return YtmPlaylist(
      browseId: browseId,
      title: title,
      author: rest.isEmpty ? null : _runsText(rest.first),
      thumbnailUrl: thumb,
    );
  }
  if (pageType != null) return null; // podcast, profile, ...

  final watch =
      _map(dig(play, ['watchEndpoint'])) ??
      _map(
        dig(cols[0].isEmpty ? null : cols[0].first, [
          'navigationEndpoint',
          'watchEndpoint',
        ]),
      );
  final videoId = _str(watch?['videoId']);
  if (videoId == null) return null;
  final videoType = _str(
    dig(watch, [
      'watchEndpointMusicSupportedConfigs',
      'watchEndpointMusicConfig',
      'musicVideoType',
    ]),
  );
  if (videoType != null && videoType.contains('PODCAST_EPISODE')) return null;
  final meta = _songMeta(subtitle);
  return YtmSong(
    videoId: videoId,
    title: title,
    artists: meta.artists,
    album: meta.album,
    albumBrowseId: meta.albumBrowseId,
    durationMs: meta.durationMs,
    thumbnailUrl: thumb,
    isVideo: _isVideoType(videoType, typeWord == 'Video'),
  );
});

/// A `playlistPanelVideoRenderer` (a radio / queue row) as a song. Also
/// accepts the `playlistPanelVideoWrapperRenderer` wrapper.
YtmSong? parsePanelVideo(Object? row) => _guard('panel row', () {
  var r = _map(dig(row, ['playlistPanelVideoRenderer']));
  r ??= _map(
    dig(row, [
      'playlistPanelVideoWrapperRenderer',
      'primaryRenderer',
      'playlistPanelVideoRenderer',
    ]),
  );
  if (r == null) return null;
  final videoId = _str(r['videoId']);
  final title = _runsText(_runs(r['title']));
  if (videoId == null || title == null) {
    AppLog.i('ytm parse: panel row without id or title dropped');
    return null;
  }
  final meta = _songMeta(
    _runs(r['longBylineText']),
    durationText: _runsText(_runs(r['lengthText'])),
  );
  final videoType = _str(
    dig(r, [
      'navigationEndpoint',
      'watchEndpoint',
      'watchEndpointMusicSupportedConfigs',
      'watchEndpointMusicConfig',
      'musicVideoType',
    ]),
  );
  return YtmSong(
    videoId: videoId,
    title: title,
    artists: meta.artists,
    album: meta.album,
    albumBrowseId: meta.albumBrowseId,
    durationMs: meta.durationMs,
    thumbnailUrl: bestThumbnail(dig(r, ['thumbnail', 'thumbnails'])),
    isVideo: _isVideoType(videoType, false),
  );
});

/// First continuation token in a `continuations` list.
String? parseContinuation(Object? continuations) {
  for (final c in _list(continuations)) {
    final m = _map(c);
    if (m == null) continue;
    for (final v in m.values) {
      final t = _str(dig(v, ['continuation']));
      if (t != null) return t;
    }
  }
  return null;
}

/// Rows and continuation token of a search response, first page or
/// continuation. Only `musicResponsiveListItemRenderer` rows are kept.
({List<Object?> rows, String? continuation}) searchRows(Json json) {
  final rows = <Object?>[];
  String? token;
  void addShelf(Object? shelf) {
    for (final c in _list(_map(shelf)?['contents'])) {
      final row = dig(c, ['musicResponsiveListItemRenderer']);
      if (row != null) {
        rows.add(row);
      } else {
        AppLog.i('ytm parse: skipped ${_map(c)?.keys.join(',')} in search');
      }
    }
    token ??= parseContinuation(_map(shelf)?['continuations']);
  }

  final cont = dig(json, ['continuationContents', 'musicShelfContinuation']);
  if (cont != null) {
    addShelf(cont);
  } else {
    final sections = dig(json, [
      'contents',
      'tabbedSearchResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
    ]);
    for (final s in _list(sections)) {
      final shelf = dig(s, ['musicShelfRenderer']);
      if (shelf != null) {
        addShelf(shelf);
        continue;
      }
      // The all tab: one row per itemSectionRenderer.
      for (final c in _list(dig(s, ['itemSectionRenderer', 'contents']))) {
        final row = dig(c, ['musicResponsiveListItemRenderer']);
        if (row != null) rows.add(row);
      }
    }
  }
  return (rows: rows, continuation: token);
}

/// Panel rows (`playlistPanelRenderer.contents`) and token of a `next`
/// response, first page or continuation.
({List<Object?> rows, String? continuation}) panelRows(Json json) {
  final panel =
      dig(json, ['continuationContents', 'playlistPanelContinuation']) ??
      dig(json, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer',
      ]);
  return (
    rows: _list(_map(panel)?['contents']),
    continuation: parseContinuation(_map(panel)?['continuations']),
  );
}
