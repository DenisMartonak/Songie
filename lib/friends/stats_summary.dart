import 'dart:convert';

import '../stats/artist_photos.dart';
import '../stats/stats_models.dart';
import 'activity_backend.dart' show NowPlaying;

/// Someone's stats as friends see them: each period's minutes, chart, top
/// artists and top songs, worked out on day [at] (local).
///
/// Stored as `activity.top`. The JSON also keeps the old top-10 keys
/// (`artists`, `songs`, from the month) so older apps still read it;
/// such an old payload reads back as just the month, [legacy].
class StatsSummary {
  StatsSummary({required this.at, required this.periods, this.legacy = false});

  /// Under the server's 64 kB limit, with room to spare: the server
  /// measures the jsonb text (`p_top::text`), which adds a space after each
  /// ':' and ',' that this compact JSON does not have.
  static const int maxBytes = 54000;

  /// Entries kept per list.
  static const int most = 10;

  /// The day the stats were worked out (local, no time).
  final DateTime at;
  final Map<StatsPeriod, PeriodStats> periods;

  /// Read from an old app's payload: names and titles of the month only.
  final bool legacy;

  /// The JSON to publish, at most [maxBytes] encoded: when too big, the
  /// lists are cut from the year first, then half a year, the week and
  /// last the month.
  Map<String, Object?> toJson() {
    final lists = {
      for (final MapEntry(key: p, value: s) in periods.entries)
        p: (
          artists: [for (final a in s.topArtists.take(most)) _artistJson(a)],
          songs: [for (final x in s.topSongs.take(most)) _songJson(x)],
        ),
    };

    Map<String, Object?> build() {
      final m = lists[StatsPeriod.month];
      return {
        'v': 2,
        'at': _day(at),
        'periods': {
          for (final MapEntry(key: p, value: s) in periods.entries)
            p.name: {
              'total': s.total.inMilliseconds,
              'prev': ?s.previousTotal?.inMilliseconds,
              'buckets': [
                for (final b in s.buckets)
                  [_day(b.start), b.heard.inMilliseconds],
              ],
              'artists': lists[p]!.artists,
              'songs': lists[p]!.songs,
            },
        },
        // What older apps read: the month's names and titles.
        'artists': [
          for (final a in m?.artists ?? const <Map<String, Object?>>[])
            {'name': a['name']},
        ],
        'songs': [
          for (final s in m?.songs ?? const <Map<String, Object?>>[])
            {
              'title': s['title'],
              'artist': s['artist'],
              'videoId': ?s['videoId'],
            },
        ],
      };
    }

    var json = build();
    const order = [
      StatsPeriod.year,
      StatsPeriod.halfYear,
      StatsPeriod.week,
      StatsPeriod.month,
    ];
    while (_bytes(json) > maxBytes) {
      final l = [for (final p in order) ?lists[p]]
          .where((l) => l.artists.isNotEmpty || l.songs.isNotEmpty)
          .firstOrNull;
      if (l == null) break;
      // The longer list loses its last entry (a song on a tie).
      l.songs.length >= l.artists.length
          ? l.songs.removeLast()
          : l.artists.removeLast();
      json = build();
    }
    return json;
  }

  /// This device's stats on day [at]: every period from [period], with the
  /// top artists' photos and pages from [photos] (looked up first, once,
  /// for the artists of all periods).
  static Future<StatsSummary> gather({
    required DateTime at,
    required Future<PeriodStats> Function(StatsPeriod) period,
    required ArtistPhotos photos,
  }) async {
    final periods = {for (final p in StatsPeriod.values) p: await period(p)};
    await photos.fill([for (final s in periods.values) ...s.topArtists]);
    return StatsSummary(
      at: at,
      periods: {
        for (final MapEntry(key: p, value: s) in periods.entries)
          p: PeriodStats(
            period: s.period,
            total: s.total,
            previousTotal: s.previousTotal,
            buckets: s.buckets,
            topArtists: photos.apply(s.topArtists),
            topSongs: s.topSongs,
          ),
      },
    );
  }

  /// Lenient: entries of the wrong shape are skipped; null when [j] is not
  /// a map. A map without `periods` is an old payload.
  static StatsSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    final periods = j['periods'];
    if (periods is! Map) return _legacy(j);
    final at = _parseDay(j['at']) ?? _today();
    return StatsSummary(
      at: at,
      periods: {
        for (final p in StatsPeriod.values) p: ?_period(p, periods[p.name], at),
      },
    );
  }

  static StatsSummary _legacy(Map<dynamic, dynamic> j) {
    final artists = j['artists'];
    final songs = j['songs'];
    final read = [
      if (songs is List)
        for (final s in songs) ?NowPlaying.fromJson(s),
    ].take(most);
    return StatsSummary(
      at: _today(),
      legacy: true,
      periods: {
        StatsPeriod.month: PeriodStats(
          period: StatsPeriod.month,
          total: Duration.zero,
          previousTotal: null,
          buckets: const [],
          topArtists: [
            if (artists is List)
              for (final a in artists)
                if (a is Map && a['name'] is String)
                  ArtistStat(
                    name: a['name'] as String,
                    plays: 0,
                    heard: Duration.zero,
                  ),
          ].take(most).toList(),
          topSongs: [
            for (final (i, s) in read.indexed)
              SongStat(
                trackId: _trackId(StatsPeriod.month, i, s.videoId),
                title: s.title,
                artist: s.artist,
                mainArtist: '',
                plays: 0,
                heard: Duration.zero,
                videoId: s.videoId,
              ),
          ],
        ),
      },
    );
  }

  static PeriodStats? _period(StatsPeriod p, Object? j, DateTime at) {
    if (j is! Map) return null;
    final total = _ms(j['total']);
    if (total == null) return null;
    final prev = j['prev'];
    final rawBuckets = j['buckets'];
    final starts = <(DateTime, Duration)>[
      if (rawBuckets is List)
        for (final b in rawBuckets)
          if (b is List && b.length == 2)
            if ((_parseDay(b[0]), _ms(b[1])) case (final d?, final ms?))
              (d, ms),
    ];
    final artists = j['artists'];
    final songs = j['songs'];
    final readSongs = [
      if (songs is List)
        for (final s in songs) ?_song(s),
    ].take(most);
    return PeriodStats(
      period: p,
      total: total,
      previousTotal: prev == null ? null : _ms(prev),
      buckets: [
        for (final (i, (start, heard)) in starts.indexed)
          StatsBucket(
            start: start,
            end: i + 1 < starts.length
                ? starts[i + 1].$1
                : DateTime(at.year, at.month, at.day + 1),
            heard: heard,
          ),
      ],
      topArtists: [
        if (artists is List)
          for (final a in artists) ?_artist(a),
      ].take(most).toList(),
      topSongs: [
        for (final (i, s) in readSongs.indexed)
          SongStat(
            trackId: _trackId(p, i, s.videoId),
            title: s.title,
            artist: s.artist,
            mainArtist: '',
            plays: s.plays,
            heard: s.heard,
            videoId: s.videoId,
          ),
      ],
    );
  }

  static ArtistStat? _artist(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final heard = _ms(j['ms'] ?? 0);
    final plays = _int(j['plays'] ?? 0);
    if (name is! String || heard == null || plays == null) return null;
    final photo = j['photo'];
    final browseId = j['browseId'];
    return ArtistStat(
      name: name,
      plays: plays,
      heard: heard,
      photoUrl: photo is String ? photo : null,
      browseId: browseId is String ? browseId : null,
    );
  }

  static ({
    String title,
    String artist,
    int plays,
    Duration heard,
    String? videoId,
  })?
  _song(Object? j) {
    if (j is! Map) return null;
    final title = j['title'];
    final artist = j['artist'];
    final heard = _ms(j['ms'] ?? 0);
    final plays = _int(j['plays'] ?? 0);
    if (title is! String ||
        artist is! String ||
        heard == null ||
        plays == null) {
      return null;
    }
    final videoId = j['videoId'];
    return (
      title: title,
      artist: artist,
      plays: plays,
      heard: heard,
      videoId: videoId is String ? videoId : null,
    );
  }

  static Map<String, Object?> _artistJson(ArtistStat a) => {
    'name': a.name,
    'ms': a.heard.inMilliseconds,
    'plays': a.plays,
    'photo': ?a.photoUrl,
    'browseId': ?a.browseId,
  };

  static Map<String, Object?> _songJson(SongStat s) => {
    'title': s.title,
    'artist': s.displayArtist,
    'ms': s.heard.inMilliseconds,
    'plays': s.plays,
    'videoId': ?s.videoId,
  };

  static String _trackId(StatsPeriod p, int i, String? videoId) =>
      videoId == null ? 'friend:${p.name}:$i' : 'yt:$videoId';

  static int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;

  static Duration? _ms(Object? v) =>
      _int(v) == null ? null : Duration(milliseconds: _int(v)!);

  static int _bytes(Object? json) => utf8.encode(jsonEncode(json)).length;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// A local `YYYY-MM-DD` day; null for anything else.
  static DateTime? _parseDay(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
}
