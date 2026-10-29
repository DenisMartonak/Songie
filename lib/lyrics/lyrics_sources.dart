import 'lyrics.dart';

/// What one lyrics source found for a track.
sealed class SourceAnswer {
  const SourceAnswer();
}

final class Found extends SourceAnswer {
  const Found(this.lyrics);

  final TrackLyrics lyrics;
}

/// The source answered and has no lyrics for the track.
final class Nothing extends SourceAnswer {
  const Nothing();
}

/// The source could not answer (network, bad status, bad data).
final class Failed extends SourceAnswer {
  const Failed(this.error);

  final Object error;
}

/// What the sources are asked about, with `searchTitle` / `searchArtist`
/// already applied.
class LyricsQuery {
  const LyricsQuery({
    required this.title,
    required this.artist,
    this.album,
    this.durationSec,
    this.videoId,
  });

  final String title;
  final String artist;
  final String? album;
  final int? durationSec;
  final String? videoId;
}
