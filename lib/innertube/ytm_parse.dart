import '../core/log.dart';
import 'ytm_models.dart';
import '../lyrics/lyrics.dart';

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

final _yearRe = RegExp(r'^\d{4}$');

/// Artist and year of an album subtitle ("Album • Daft Punk • 2013",
/// "Single • 2023", "2013").
({String? artist, String? year}) _albumSubtitle(List<List<Json>> groups) {
  String? artist;
  String? year;
  for (final g in _withoutType(groups)) {
    final t = _runsText(g);
    if (t == null) continue;
    if (_yearRe.hasMatch(t)) {
      year = t;
    } else if (!_typeWords.contains(t)) {
      artist ??= t;
    }
  }
  return (artist: artist, year: year);
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
    final meta = _albumSubtitle(groups);
    return YtmAlbum(
      browseId: browseId,
      title: title,
      artist: meta.artist,
      year: meta.year,
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
  final meta = _songMeta(
    subtitle,
    durationText: _runsText(
      _runs(
        dig(r, [
          'fixedColumns',
          0,
          'musicResponsiveListItemFixedColumnRenderer',
          'text',
        ]),
      ),
    ),
  );
  var album = meta.album;
  var albumId = meta.albumBrowseId;
  if (album == null) {
    // Artist-page and playlist rows put the album in a later column.
    for (final c in cols.skip(2)) {
      for (final run in c) {
        final id = _browseId(run);
        if (id != null && id.startsWith('MPRE') && _str(run['text']) != null) {
          album = _str(run['text']);
          albumId = id;
        }
      }
    }
  }
  return YtmSong(
    videoId: videoId,
    title: title,
    artists: meta.artists,
    album: album,
    albumBrowseId: albumId,
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
    final tabs = _list(
      dig(json, ['contents', 'tabbedSearchResultsRenderer', 'tabs']),
    );
    if (tabs.length > 1) {
      AppLog.i(
        'ytm parse: search has ${tabs.length} tabs, read only the first',
      );
    }
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
      final top = _map(s)?.keys.join(',');
      if (top != 'itemSectionRenderer' && top != 'musicCardShelfRenderer') {
        AppLog.i('ytm parse: skipped section $top in search');
      }
      // The all tab: one row per itemSectionRenderer.
      for (final c in _list(dig(s, ['itemSectionRenderer', 'contents']))) {
        final row = dig(c, ['musicResponsiveListItemRenderer']);
        if (row != null) {
          rows.add(row);
        } else {
          final key = _map(c)?.keys.join(',');
          if (key != 'messageRenderer') {
            AppLog.i('ytm parse: skipped $key in an item section');
          }
        }
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

// ---------------------------------------------------------------------------
// Browse pages: home, artist, album, playlist.

/// A `musicTwoRowItemRenderer` (a carousel tile) as an album, playlist, artist
/// or song / video; null for anything else or a tile with a missing piece.
Object? parseTwoRowItem(Object? renderer) => _guard('two-row item', () {
  final r = _map(renderer);
  if (r == null) return null;
  final title = _runsText(_runs(r['title']));
  if (title == null) {
    AppLog.i('ytm parse: two-row item without a title dropped');
    return null;
  }
  final subtitle = _runs(r['subtitle']);
  final groups = _groups(subtitle);
  final thumb = bestThumbnail(
    dig(r, [
      'thumbnailRenderer',
      'musicThumbnailRenderer',
      'thumbnail',
      'thumbnails',
    ]),
  );
  final nav = r['navigationEndpoint'];
  final pageType = _pageType(nav);
  final browseId = _str(dig(nav, ['browseEndpoint', 'browseId']));

  if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' && browseId != null) {
    final meta = _albumSubtitle(groups);
    return YtmAlbum(
      browseId: browseId,
      title: title,
      artist: meta.artist,
      year: meta.year,
      thumbnailUrl: thumb,
      playlistId: _str(
        dig(r, [
          'thumbnailOverlay',
          'musicItemThumbnailOverlayRenderer',
          'content',
          'musicPlayButtonRenderer',
          'playNavigationEndpoint',
          'watchPlaylistEndpoint',
          'playlistId',
        ]),
      ),
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
  if (pageType != null) return null;

  final watch = _map(dig(nav, ['watchEndpoint']));
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
    thumbnailUrl: thumb,
    isVideo: _isVideoType(videoType, false),
  );
});

/// A shelf row: a list item or a two-row tile.
Object? _shelfItem(Object? c) {
  final list = dig(c, ['musicResponsiveListItemRenderer']);
  if (list != null) return parseListItem(list);
  final tile = dig(c, ['musicTwoRowItemRenderer']);
  if (tile != null) return parseTwoRowItem(tile);
  AppLog.i('ytm parse: skipped ${_map(c)?.keys.join(',')} in a shelf');
  return null;
}

/// A `musicCarouselShelfRenderer` or `musicShelfRenderer` section as a shelf.
/// Null for another section type, a shelf without a title, or one whose rows
/// all fail to parse; a single bad row is dropped alone.
YtmShelf? parseShelf(Object? section) => _guard('shelf', () {
  final m = _map(section);
  if (m == null) return null;
  final key = m.keys.firstWhere(
    (k) => k == 'musicCarouselShelfRenderer' || k == 'musicShelfRenderer',
    orElse: () => '',
  );
  if (key.isEmpty) {
    AppLog.i('ytm parse: skipped section ${m.keys.join(',')}');
    return null;
  }
  final body = _map(m[key]);
  final Object? titleNode = key == 'musicShelfRenderer'
      ? dig(body, ['title'])
      : dig(body, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']);
  final title = _runsText(_runs(titleNode));
  final rows = _list(body?['contents']);
  final items = <Object>[];
  for (final c in rows) {
    final item = _shelfItem(c);
    if (item != null) items.add(item);
  }
  if (title == null || items.isEmpty) {
    AppLog.i(
      'ytm parse: dropped $key (title ${title == null ? 'missing' : 'ok'}, '
      '${items.length} of ${rows.length} rows parsed)',
    );
    return null;
  }
  if (items.length < rows.length) {
    AppLog.i('ytm parse: $key kept ${items.length} of ${rows.length} rows');
  }
  return YtmShelf(title, items);
});

/// Section list contents and continuation token of a browse response: a home
/// continuation, a single-column page (home, artist) or the secondary column
/// of a two-column page (album, playlist).
({List<Object?> sections, String? continuation}) browseSections(Json json) {
  final cont = dig(json, ['continuationContents', 'sectionListContinuation']);
  final list =
      cont ??
      dig(json, [
        'contents',
        'singleColumnBrowseResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
      ]) ??
      dig(json, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
      ]);
  return (
    sections: _list(_map(list)?['contents']),
    continuation: parseContinuation(_map(list)?['continuations']),
  );
}

YtmHome parseHome(Json json) {
  final page = browseSections(json);
  final shelves = <YtmShelf>[];
  for (final s in page.sections) {
    final shelf = parseShelf(s);
    if (shelf != null) shelves.add(shelf);
  }
  return YtmHome(shelves, page.continuation);
}

List<YtmSong> _songs(Iterable<Object?> rows, String what) {
  final out = <YtmSong>[];
  var dropped = 0;
  for (final row in rows) {
    final item = parseListItem(dig(row, ['musicResponsiveListItemRenderer']));
    if (item is YtmSong) {
      out.add(item);
    } else {
      dropped++;
    }
  }
  if (dropped > 0) AppLog.i('ytm parse: $what dropped $dropped rows');
  return out;
}

String? _headerThumb(Object? header) => bestThumbnail(
  dig(header, [
    'thumbnail',
    'musicThumbnailRenderer',
    'thumbnail',
    'thumbnails',
  ]),
);

/// "EP" / "EPs" as a word, so "Deep cuts" is not a singles shelf.
final _epWord = RegExp(r'\beps?\b', caseSensitive: false);

/// The artist page; null when the header (and so the name) is missing.
YtmArtistPage? parseArtistPage(Json json, String browseId) =>
    _guard('artist page', () {
      final header =
          dig(json, ['header', 'musicImmersiveHeaderRenderer']) ??
          dig(json, ['header', 'musicVisualHeaderRenderer']);
      final name = _runsText(_runs(dig(header, ['title'])));
      if (name == null) {
        AppLog.i('ytm parse: artist page without a header name');
        return null;
      }
      final artist = YtmArtist(
        browseId: browseId,
        name: name,
        thumbnailUrl: _headerThumb(header),
      );
      final topSongs = <YtmSong>[];
      final albums = <YtmAlbum>[];
      final singles = <YtmAlbum>[];
      final similar = <YtmArtist>[];
      var haveTop = false;
      for (final s in browseSections(json).sections) {
        final isSongShelf = dig(s, ['musicShelfRenderer']) != null;
        if (isSongShelf && haveTop) continue;
        final shelf = parseShelf(s);
        if (shelf == null) continue;
        if (isSongShelf) {
          haveTop = true;
          topSongs.addAll(shelf.items.whereType<YtmSong>());
          continue;
        }
        final title = shelf.title.toLowerCase();
        if (shelf.items.every((i) => i is YtmArtist)) {
          similar.addAll(shelf.items.cast<YtmArtist>());
        } else if (shelf.items.every((i) => i is YtmAlbum)) {
          final target = title.contains('single') || _epWord.hasMatch(title)
              ? singles
              : title.contains('album')
              ? albums
              : null;
          if (target == null) {
            AppLog.i('ytm parse: skipped album shelf "${shelf.title}"');
            continue;
          }
          target.addAll(
            shelf.items.cast<YtmAlbum>().map((a) => _withArtist(a, name)),
          );
        }
        // Videos, playlists, live performances and the like are not used.
      }
      final listeners = _runsText(_runs(dig(header, ['monthlyListenerCount'])));
      final count = listeners?.split(' ').first;
      return YtmArtistPage(
        artist: artist,
        monthlyListeners: count == null || count.isEmpty ? null : count,
        topSongs: topSongs,
        albums: albums,
        singles: singles,
        similar: similar,
        radioPlaylistId: _str(
          dig(header, [
            'startRadioButton',
            'buttonRenderer',
            'navigationEndpoint',
            'watchEndpoint',
            'playlistId',
          ]),
        ),
      );
    });

YtmAlbum _withArtist(YtmAlbum a, String artist) => a.artist != null
    ? a
    : YtmAlbum(
        browseId: a.browseId,
        title: a.title,
        artist: artist,
        year: a.year,
        thumbnailUrl: a.thumbnailUrl,
        playlistId: a.playlistId,
      );

/// First value stored under [key] anywhere inside [v].
Object? _findKey(Object? v, String key) {
  if (v is Map) {
    if (v.containsKey(key)) return v[key];
    for (final x in v.values) {
      final f = _findKey(x, key);
      if (f != null) return f;
    }
  } else if (v is List) {
    for (final x in v) {
      final f = _findKey(x, key);
      if (f != null) return f;
    }
  }
  return null;
}

Object? _twoColumnHeader(Json json) => dig(json, [
  'contents',
  'twoColumnBrowseResultsRenderer',
  'tabs',
  0,
  'tabRenderer',
  'content',
  'sectionListRenderer',
  'contents',
  0,
  'musicResponsiveHeaderRenderer',
]);

String? _microformatTitle(Json json) =>
    _str(dig(json, ['microformat', 'microformatDataRenderer', 'title']));

/// The album page; null when no title can be found. Tracks without art take
/// the album's art, and every track carries the album's title and id.
YtmAlbumPage? parseAlbumPage(Json json, String browseId) =>
    _guard('album page', () {
      final header = _twoColumnHeader(json);
      final title =
          _runsText(_runs(dig(header, ['title']))) ?? _microformatTitle(json);
      if (title == null) {
        AppLog.i('ytm parse: album page without a title');
        return null;
      }
      var playlistId = _str(
        dig(_findKey(header, 'watchPlaylistEndpoint'), ['playlistId']),
      );
      if (playlistId == null) {
        final canonical = _str(
          dig(json, ['microformat', 'microformatDataRenderer', 'urlCanonical']),
        );
        final id = canonical == null
            ? null
            : Uri.tryParse(canonical)?.queryParameters['list'];
        if (id != null && id.startsWith('OLAK5uy_')) playlistId = id;
      }
      final sub = _albumSubtitle(_groups(_runs(dig(header, ['subtitle']))));
      final thumb = _headerThumb(header);
      final shelf = _list(browseSections(json).sections)
          .map((s) => dig(s, ['musicShelfRenderer']))
          .firstWhere((s) => s != null, orElse: () => null);
      final tracks = [
        for (final t in _songs(_list(_map(shelf)?['contents']), 'album tracks'))
          YtmSong(
            videoId: t.videoId,
            title: t.title,
            artists: t.artists,
            album: title,
            albumBrowseId: browseId,
            durationMs: t.durationMs,
            thumbnailUrl: t.thumbnailUrl ?? thumb,
            isVideo: t.isVideo,
          ),
      ];
      final artist =
          _runsText(_runs(dig(header, ['straplineTextOne']))) ??
          (tracks.isEmpty || tracks.first.artists.isEmpty
              ? sub.artist
              : tracks.first.artistLine);
      return YtmAlbumPage(
        YtmAlbum(
          browseId: browseId,
          title: title,
          artist: artist,
          year: sub.year,
          thumbnailUrl: thumb,
          playlistId: playlistId,
        ),
        tracks,
      );
    });

/// Playlist rows and token of a first page or a continuation (either the
/// `continuationContents` or the `appendContinuationItemsAction` shape).
({List<Object?> rows, String? continuation}) playlistRows(Json json) {
  final cont =
      dig(json, ['continuationContents', 'musicPlaylistShelfContinuation']) ??
      dig(json, ['continuationContents', 'musicShelfContinuation']);
  if (cont != null) {
    return (
      rows: _list(_map(cont)?['contents']),
      continuation: parseContinuation(_map(cont)?['continuations']),
    );
  }
  final items = _list(
    dig(json, [
      'onResponseReceivedActions',
      0,
      'appendContinuationItemsAction',
      'continuationItems',
    ]),
  );
  if (items.isNotEmpty) {
    String? token;
    final rows = <Object?>[];
    for (final c in items) {
      final t = _str(
        dig(c, [
          'continuationItemRenderer',
          'continuationEndpoint',
          'continuationCommand',
          'token',
        ]),
      );
      if (t != null) {
        token ??= t;
      } else {
        rows.add(c);
      }
    }
    return (rows: rows, continuation: token);
  }
  final page = browseSections(json);
  for (final s in page.sections) {
    final shelf =
        dig(s, ['musicPlaylistShelfRenderer']) ??
        dig(s, ['musicShelfRenderer']);
    if (shelf != null) {
      return (
        rows: _list(_map(shelf)?['contents']),
        continuation:
            parseContinuation(_map(shelf)?['continuations']) ??
            page.continuation,
      );
    }
  }
  return (rows: const [], continuation: page.continuation);
}

/// The playlist header; null when no title can be found.
YtmPlaylist? parsePlaylistHeader(Json json, String browseId) => _guard(
  'playlist header',
  () {
    final header = _twoColumnHeader(json);
    final title =
        _runsText(_runs(dig(header, ['title']))) ?? _microformatTitle(json);
    if (title == null) {
      AppLog.i('ytm parse: playlist page without a title');
      return null;
    }
    final author =
        _str(
          dig(header, ['facepile', 'avatarStackViewModel', 'text', 'content']),
        ) ??
        _runsText(_runs(dig(header, ['straplineTextOne'])));
    return YtmPlaylist(
      browseId: browseId,
      title: title,
      author: author,
      thumbnailUrl: _headerThumb(header),
    );
  },
);

List<YtmSong> parsePlaylistTracks(List<Object?> rows) =>
    _songs(rows, 'playlist');

/// The browse id of the Lyrics tab in a `next` response: the tab titled
/// "Lyrics", else (localized titles) the first tab whose id starts with
/// `MPLY`. A tab without an endpoint (no lyrics) gives null.
String? lyricsBrowseId(Json nextJson) {
  final tabs = _list(
    dig(nextJson, [
      'contents',
      'singleColumnMusicWatchNextResultsRenderer',
      'tabbedRenderer',
      'watchNextTabbedResultsRenderer',
      'tabs',
    ]),
  );
  String? idOf(Object? tab) =>
      _str(dig(tab, ['tabRenderer', 'endpoint', 'browseEndpoint', 'browseId']));
  for (final tab in tabs) {
    if (dig(tab, ['tabRenderer', 'title']) == 'Lyrics') return idOf(tab);
  }
  for (final tab in tabs) {
    final id = idOf(tab);
    if (id != null && id.startsWith('MPLY')) return id;
  }
  return null;
}

/// Plain lyrics from a lyrics `browse` response; null when there is no text.
TrackLyrics? parseLyricsBrowse(Json json) {
  final shelf = dig(json, [
    'contents',
    'sectionListRenderer',
    'contents',
    0,
    'musicDescriptionShelfRenderer',
  ]);
  final text = _runsText(_runs(dig(shelf, ['description'])));
  if (text == null) return null;
  return TrackLyrics(
    kind: LyricsKind.plain,
    source: LyricsSource.youtube,
    text: text,
    credit: _runsText(_runs(dig(shelf, ['footer']))),
  );
}
