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

/// A titled row of home or artist-page items ([YtmSong], [YtmAlbum],
/// [YtmArtist] and [YtmPlaylist], mixed).
class YtmShelf {
  const YtmShelf(this.title, this.items);

  final String title;
  final List<Object> items;
}

class YtmHome {
  const YtmHome(this.shelves, this.continuation);

  final List<YtmShelf> shelves;
  final String? continuation;
}

class YtmArtistPage {
  const YtmArtistPage({
    required this.artist,
    this.topSongs = const [],
    this.albums = const [],
    this.singles = const [],
    this.similar = const [],
    this.radioPlaylistId,
  });

  final YtmArtist artist;
  final List<YtmSong> topSongs;
  final List<YtmAlbum> albums;
  final List<YtmAlbum> singles;
  final List<YtmArtist> similar;
  final String? radioPlaylistId;
}

class YtmAlbumPage {
  const YtmAlbumPage(this.album, this.tracks);

  final YtmAlbum album;
  final List<YtmSong> tracks;
}

class YtmPlaylistPage {
  const YtmPlaylistPage(this.playlist, this.tracks, this.continuation);

  final YtmPlaylist playlist;
  final List<YtmSong> tracks;
  final String? continuation;
}
