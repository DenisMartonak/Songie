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
    );
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final page = searchRows(value);
        final items = <Object>[];
        for (final row in page.rows) {
          final item = parseListItem(row);
          if (item != null && _matches(kind, item)) items.add(item);
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

  Future<Result<YtmRadio>> radio(String videoId, {String? continuation}) async {
    final res = await _c.call(
      kWebRemix,
      'next',
      continuation != null
          ? {'continuation': continuation}
          : {
              'videoId': videoId,
              'playlistId': 'RDAMVM$videoId',
              'params': 'wAEB',
              'isAudioOnly': true,
              'enablePersistentPlaylistPanel': true,
              'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
            },
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
}
