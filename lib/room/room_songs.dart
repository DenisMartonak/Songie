import '../data/database.dart';
import '../innertube/ytm_models.dart';
import '../library/yt_tracks.dart';
import 'room_protocol.dart';

/// The room song for [t]: a YouTube track keeps its video id, a local file
/// has none (guests cannot play it).
RoomSong roomSongOf(Track t) {
  final id = t.source == 'local' ? null : t.ytVideoId;
  return RoomSong(
    videoId: id,
    title: t.title,
    artist: t.artist,
    album: (t.album ?? '').isEmpty ? null : t.album,
    durationMs: t.durationMs > 0 ? t.durationMs : null,
  );
}

/// A track per song, in the same positions: YouTube songs go through
/// [store]; local songs are null.
Future<List<Track?>> tracksForSongs(
  List<RoomSong> songs,
  YtTrackStore store,
) async {
  final out = <Track?>[];
  for (final s in songs) {
    final id = s.videoId;
    if (id == null) {
      out.add(null);
      continue;
    }
    final made = await store.upsertAll([
      YtmSong(
        videoId: id,
        title: s.title,
        artists: s.artist.isEmpty ? const [] : [YtmArtistRef(name: s.artist)],
        album: s.album,
        durationMs: s.durationMs,
        thumbnailUrl: s.artUrl,
      ),
    ]);
    out.add(made.isEmpty ? null : made.first);
  }
  return out;
}
