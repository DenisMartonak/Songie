// YouTube Music models. Kept small: only what the UI and the player need.

class YtmArtistRef {
  const YtmArtistRef({this.browseId, required this.name});

  final String? browseId;
  final String name;
}

class YtmSong {
  const YtmSong({
    required this.videoId,
    required this.title,
    this.artists = const [],
    this.album,
    this.albumBrowseId,
    this.durationMs,
    this.thumbnailUrl,
    this.isVideo = false,
  });

  final String videoId;
  final String title;
  final List<YtmArtistRef> artists;
  final String? album;
  final String? albumBrowseId;
  final int? durationMs;
  final String? thumbnailUrl;

  /// A music video (or user upload) rather than an audio track.
  final bool isVideo;

  String get artistLine => artists.map((a) => a.name).join(', ');
}

class YtmAlbum {
  const YtmAlbum({
    required this.browseId,
    required this.title,
    this.artist,
    this.year,
    this.thumbnailUrl,
    this.playlistId,
  });

  final String browseId;
  final String title;
  final String? artist;
  final String? year;
  final String? thumbnailUrl;
  final String? playlistId;
}

class YtmArtist {
  const YtmArtist({
    required this.browseId,
    required this.name,
    this.thumbnailUrl,
  });

  final String browseId;
  final String name;
  final String? thumbnailUrl;
}

class YtmPlaylist {
  const YtmPlaylist({
    required this.browseId,
    required this.title,
    this.author,
    this.thumbnailUrl,
  });

  final String browseId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
}

enum YtmSearchKind { songs, videos, albums, artists, playlists }

/// One page of search results; [items] hold one model type per kind
/// ([YtmSong] for songs and videos, [YtmAlbum], [YtmArtist], [YtmPlaylist]).
class YtmSearchPage {
  const YtmSearchPage(this.items, this.continuation);

  final List<Object> items;
  final String? continuation;
}

/// A radio queue. [current] is the seed song with its rich metadata (only on
/// the first page); [songs] never contain it.
class YtmRadio {
  const YtmRadio(this.songs, this.continuation, {this.current});

  final List<YtmSong> songs;
  final String? continuation;
  final YtmSong? current;
}
