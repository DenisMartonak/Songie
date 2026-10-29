/// A stats period: the last [days] calendar days including today, in local
/// time.
enum StatsPeriod {
  week(7, '7 days'),
  month(30, '1 month'),
  halfYear(182, '6 months'),
  year(365, '12 months');

  const StatsPeriod(this.days, this.label);

  final int days;
  final String label;
}

/// Minutes heard in one bar of the chart: local [start] to [end] (exclusive).
class StatsBucket {
  const StatsBucket({
    required this.start,
    required this.end,
    required this.heard,
  });

  final DateTime start;
  final DateTime end;
  final Duration heard;
}

class ArtistStat {
  const ArtistStat({
    required this.name,
    required this.plays,
    required this.heard,
    this.artworkRef,
    this.sampleTrackId,
  });

  /// The most recently recorded spelling.
  final String name;
  final int plays;
  final Duration heard;

  /// Cover of the artist's most-played song in the period.
  final String? artworkRef;

  /// Id of that most-played song.
  final String? sampleTrackId;
}

class SongStat {
  const SongStat({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.mainArtist,
    required this.plays,
    required this.heard,
    this.artworkRef,
  });

  final String trackId;

  /// Title, artist line and cover from the latest listen's snapshots.
  final String title;
  final String artist;
  final String? artworkRef;

  /// The latest listen's main artist; empty when unknown.
  final String mainArtist;

  final int plays;
  final Duration heard;

  /// The artist to show: the main artist, else the artist line.
  String get displayArtist => mainArtist.isEmpty ? artist : mainArtist;
}

class PeriodStats {
  const PeriodStats({
    required this.period,
    required this.total,
    required this.previousTotal,
    required this.buckets,
    required this.topArtists,
    required this.topSongs,
  });

  final StatsPeriod period;
  final Duration total;

  /// Minutes in the same-length period just before; null when it has none.
  final Duration? previousTotal;
  final List<StatsBucket> buckets;

  /// At most 10 each, best first.
  final List<ArtistStat> topArtists;
  final List<SongStat> topSongs;

  /// No listens in the period (listens always have heard time).
  bool get isEmpty => total == Duration.zero;
}
