import '../core/log.dart';
import '../core/result.dart';
import 'clients.dart';
import 'innertube_client.dart';
import 'ytm_models.dart';
import 'ytm_parse.dart';

/// YouTube Music search and radio over the WEB_REMIX identity.
class YtmService {
  YtmService(this._c);

  final InnertubeClient _c;

  /// Search filter `params`, as recorded in docs/innertube-notes.md
  /// (playlists = Community playlists).
  static const searchParams = {
    YtmSearchKind.songs: 'EgWKAQIIAWoSEAUQCRADEAQQEBAKEA4QFRAR',
    YtmSearchKind.videos: 'EgWKAQIQAWoSEAUQCRADEAQQEBAKEA4QFRAR',
    YtmSearchKind.albums: 'EgWKAQIYAWoSEAUQCRADEAQQEBAKEA4QFRAR',
    YtmSearchKind.artists: 'EgWKAQIgAWoSEAUQCRADEAQQEBAKEA4QFRAR',
    YtmSearchKind.playlists: 'EgeKAQQoAEABahIQBRAJEAMQBBAQEAoQDhAVEBE%3D',
  };

  /// ytmusicapi-style continuation URL params (the token also stays in the
  /// body). Unverified against the live API until Plan 5 Task 11.
  static Map<String, String> _continuationQuery(String token) => {
    'ctoken': token,
    'continuation': token,
    'type': 'next',
  };

  Future<Result<YtmSearchPage>> search(
    String query,
    YtmSearchKind kind, {
    String? continuation,
  }) async {
    final res = await _c.call(
      kWebRemix,
      'search',
      continuation != null
          ? {'continuation': continuation}
          : {'query': query, 'params': searchParams[kind]},
      query: continuation == null ? null : _continuationQuery(continuation),
    );
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = searchRows(value);
        final items = <Object>[];
        var otherKind = 0;
        for (final row in page.rows) {
          final item = parseListItem(row);
          if (item == null) continue;
          if (_matches(kind, item)) {
            items.add(item);
          } else {
            otherKind++;
          }
        }
        if (otherKind > 0) {
          AppLog.i(
            'ytm search ${kind.name}: dropped $otherKind other-kind rows',
          );
        }
        return Ok(YtmSearchPage(items, page.continuation));
    }
  }

  static bool _matches(YtmSearchKind kind, Object item) => switch (kind) {
    YtmSearchKind.songs || YtmSearchKind.videos => item is YtmSong,
    YtmSearchKind.albums => item is YtmAlbum,
    YtmSearchKind.artists => item is YtmArtist,
    YtmSearchKind.playlists => item is YtmPlaylist,
  };

  /// The radio queue for [videoId]: its own radio (`RDAMVM<videoId>`), or
  /// with [playlistId] that radio playlist (an artist's radio) started from
  /// [videoId].
  Future<Result<YtmRadio>> radio(
    String videoId, {
    String? continuation,
    String? playlistId,
  }) async {
    final res = await _c.call(
      kWebRemix,
      'next',
      continuation != null
          ? {'continuation': continuation}
          : {
              'videoId': videoId,
              'playlistId': playlistId ?? 'RDAMVM$videoId',
              'params': 'wAEB',
              'isAudioOnly': true,
              'enablePersistentPlaylistPanel': true,
              'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
            },
      query: continuation == null ? null : _continuationQuery(continuation),
    );
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = panelRows(value);
        final songs = <YtmSong>[];
        YtmSong? current;
        for (final row in page.rows) {
          final s = parsePanelVideo(row);
          if (s == null) continue;
          if (continuation == null && current == null && s.videoId == videoId) {
            current = s;
          } else {
            songs.add(s);
          }
        }
        return Ok(YtmRadio(songs, page.continuation, current: current));
    }
  }

  Future<Result<YtmHome>> home({String? continuation}) async {
    final res = await _browse('FEmusic_home', continuation: continuation);
    return switch (res) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(parseHome(value)),
    };
  }

  Future<Result<YtmArtistPage>> artist(String browseId) async {
    final res = await _browse(browseId);
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = parseArtistPage(value, browseId);
        return page == null ? _unexpected('artist') : Ok(page);
    }
  }

  Future<Result<YtmAlbumPage>> album(String browseId) async {
    final res = await _browse(browseId);
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = parseAlbumPage(value, browseId);
        return page == null ? _unexpected('album') : Ok(page);
    }
  }

  /// [browseId] may be given with or without the `VL` prefix. A continuation
  /// page carries a stub [YtmPlaylistPage.playlist] (empty title): keep the
  /// first page's.
  Future<Result<YtmPlaylistPage>> playlist(
    String browseId, {
    String? continuation,
  }) async {
    final id = browseId.startsWith('VL') ? browseId : 'VL$browseId';
    final res = await _browse(id, continuation: continuation);
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = playlistRows(value);
        final tracks = parsePlaylistTracks(page.rows);
        if (continuation != null) {
          return Ok(
            YtmPlaylistPage(
              YtmPlaylist(browseId: id, title: ''),
              tracks,
              page.continuation,
            ),
          );
        }
        final header = parsePlaylistHeader(value, id);
        return header == null
            ? _unexpected('playlist')
            : Ok(YtmPlaylistPage(header, tracks, page.continuation));
    }
  }

  Future<Result<Json>> _browse(String browseId, {String? continuation}) =>
      _c.call(
        kWebRemix,
        'browse',
        continuation != null
            ? {'continuation': continuation}
            : {'browseId': browseId},
        query: continuation == null ? null : _continuationQuery(continuation),
      );

  static Result<T> _unexpected<T>(String what) =>
      Err(Failure(FailureKind.unknown, 'ytm $what: unexpected response shape'));
}
