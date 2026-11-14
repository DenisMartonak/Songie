import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/friends/stats_summary.dart';
import 'package:songies/stats/artist_photos.dart';
import 'package:songies/stats/stats_models.dart';

import '../helpers/test_db.dart';

/// [j] as Postgres prints jsonb (`p_top::text`): a space after each ':'
/// and ',' between items.
String jsonbText(Object? j) => switch (j) {
  Map() =>
    '{${[for (final e in j.entries) '${jsonEncode(e.key)}: ${jsonbText(e.value)}'].join(', ')}}',
  List() => '[${[for (final v in j) jsonbText(v)].join(', ')}]',
  _ => jsonEncode(j),
};

void main() {
  final at = DateTime(2026, 11, 14);

  PeriodStats period(StatsPeriod p, {String name = 'Beyonce'}) => PeriodStats(
    period: p,
    total: Duration(minutes: 100 + p.days),
    previousTotal: p == StatsPeriod.week ? null : Duration(minutes: p.days),
    buckets: [
      StatsBucket(
        start: DateTime(2026, 11, 12),
        end: DateTime(2026, 11, 13),
        heard: const Duration(minutes: 30),
      ),
      StatsBucket(
        start: DateTime(2026, 11, 13),
        end: DateTime(2026, 11, 15),
        heard: const Duration(minutes: 70),
      ),
    ],
    topArtists: [
      ArtistStat(
        name: '$name ${p.name}',
        plays: 7,
        heard: const Duration(minutes: 20),
        photoUrl: 'https://img/${p.name}',
        browseId: 'UC${p.name}',
      ),
    ],
    topSongs: [
      SongStat(
        trackId: 'yt:v${p.name}',
        title: 'Halo ${p.name}',
        artist: 'Beyonce',
        mainArtist: '',
        plays: 3,
        heard: const Duration(minutes: 12),
        videoId: 'v${p.name}',
      ),
    ],
  );

  StatsSummary? trip(StatsSummary s) =>
      StatsSummary.fromJson(jsonDecode(jsonEncode(s.toJson())));

  test('round trip keeps every period', () {
    final s = StatsSummary(
      at: at,
      periods: {for (final p in StatsPeriod.values) p: period(p)},
    );
    final got = trip(s)!;
    expect(got.legacy, isFalse);
    expect(got.at, at);
    expect(got.periods.keys.toSet(), StatsPeriod.values.toSet());
    for (final p in StatsPeriod.values) {
      final want = s.periods[p]!;
      final g = got.periods[p]!;
      expect(g.period, p);
      expect(g.total, want.total);
      expect(g.previousTotal, want.previousTotal);
      expect(g.buckets, hasLength(2));
      expect(g.buckets[0].start, DateTime(2026, 11, 12));
      // A bucket ends where the next starts; the last at the day after `at`.
      expect(g.buckets[0].end, DateTime(2026, 11, 13));
      expect(g.buckets[1].start, DateTime(2026, 11, 13));
      expect(g.buckets[1].end, DateTime(2026, 11, 15));
      expect(g.buckets[0].heard, const Duration(minutes: 30));
      expect(g.buckets[1].heard, const Duration(minutes: 70));
      final a = g.topArtists.single;
      final wa = want.topArtists.single;
      expect(a.name, wa.name);
      expect(a.plays, wa.plays);
      expect(a.heard, wa.heard);
      expect(a.photoUrl, wa.photoUrl);
      expect(a.browseId, wa.browseId);
      final song = g.topSongs.single;
      final ws = want.topSongs.single;
      expect(song.trackId, ws.trackId);
      expect(song.title, ws.title);
      expect(song.artist, ws.artist);
      expect(song.mainArtist, '');
      expect(song.plays, ws.plays);
      expect(song.heard, ws.heard);
      expect(song.videoId, ws.videoId);
      expect(song.coverUrl, 'https://i.ytimg.com/vi/v${p.name}/hqdefault.jpg');
    }
  });

  test('json keeps the old keys', () {
    final s = StatsSummary(
      at: at,
      periods: {for (final p in StatsPeriod.values) p: period(p)},
    );
    final j = s.toJson();
    expect(j['v'], 2);
    expect(j['at'], '2026-11-14');
    expect(j['artists'], [
      {'name': 'Beyonce month'},
    ]);
    expect(j['songs'], [
      {'title': 'Halo month', 'artist': 'Beyonce', 'videoId': 'vmonth'},
    ]);
    final week = (j['periods']! as Map)['week'] as Map;
    expect(week.containsKey('prev'), isFalse);
    expect(week['buckets'], [
      ['2026-11-12', 30 * 60000],
      ['2026-11-13', 70 * 60000],
    ]);
  });

  test('old payload reads as legacy month', () {
    final s = StatsSummary.fromJson(const {
      'artists': [
        {'name': 'A'},
      ],
      'songs': [
        {'title': 'T', 'artist': 'B'},
      ],
    })!;
    expect(s.legacy, isTrue);
    expect(s.periods.keys, [StatsPeriod.month]);
    final m = s.periods[StatsPeriod.month]!;
    expect(m.topArtists.single.name, 'A');
    expect(m.topSongs.single.title, 'T');
    expect(m.topSongs.single.artist, 'B');
    expect(m.topSongs.single.trackId, 'friend:month:0');
    expect(m.total, Duration.zero);
    expect(m.buckets, isEmpty);
    expect(StatsSummary.fromJson(null), isNull);
    expect(StatsSummary.fromJson('x'), isNull);
  });

  test('bad entries are skipped', () {
    final s = StatsSummary.fromJson(const {
      'v': 2,
      'at': '2026-11-14',
      'periods': {
        'month': {
          'total': 60000,
          'buckets': 5,
          'artists': [
            {'name': 'Bad', 'ms': 'x'},
            {'name': 'Good', 'ms': 1000, 'plays': 2},
            7,
          ],
          'songs': [
            {'artist': 'No title', 'ms': 1},
            {'title': 'Fine', 'artist': 'X', 'ms': 2000, 'plays': 1},
          ],
        },
        'week': 'nope',
      },
    })!;
    expect(s.legacy, isFalse);
    expect(s.periods.keys, [StatsPeriod.month]);
    expect(s.periods.containsKey(StatsPeriod.year), isFalse);
    final m = s.periods[StatsPeriod.month]!;
    expect(m.total, const Duration(minutes: 1));
    expect(m.previousTotal, isNull);
    expect(m.buckets, isEmpty);
    expect(m.topArtists.map((a) => a.name), ['Good']);
    expect(m.topArtists.single.heard, const Duration(seconds: 1));
    expect(m.topSongs.map((x) => x.title), ['Fine']);
    expect(m.topSongs.single.trackId, 'friend:month:0');
  });

  test('toJson trims to maxBytes', () {
    final long = 'x' * 2000;
    PeriodStats big(StatsPeriod p) => PeriodStats(
      period: p,
      total: const Duration(hours: 1),
      previousTotal: null,
      buckets: const [],
      topArtists: [
        for (var i = 0; i < 10; i++)
          ArtistStat(name: '$i$long', plays: 1, heard: Duration.zero),
      ],
      topSongs: [
        for (var i = 0; i < 10; i++)
          SongStat(
            trackId: 't$i',
            title: '$i$long',
            artist: long,
            mainArtist: '',
            plays: 1,
            heard: Duration.zero,
          ),
      ],
    );
    final s = StatsSummary(
      at: at,
      periods: {for (final p in StatsPeriod.values) p: big(p)},
    );
    final j = s.toJson();
    expect(
      utf8.encode(jsonEncode(j)).length,
      lessThanOrEqualTo(StatsSummary.maxBytes),
    );
    final got = StatsSummary.fromJson(jsonDecode(jsonEncode(j)))!;
    int count(StatsPeriod p) =>
        got.periods[p]!.topArtists.length + got.periods[p]!.topSongs.length;
    // Year goes first, then half a year, then the week; the month last.
    expect(count(StatsPeriod.year), 0);
    expect(count(StatsPeriod.halfYear), 0);
    expect(count(StatsPeriod.week), 0);
    expect(count(StatsPeriod.month), greaterThan(0));
    // The periods themselves stay.
    expect(got.periods[StatsPeriod.year]!.total, const Duration(hours: 1));

    // Room for the month and the week: only year and half a year are cut.
    final small = StatsSummary(
      at: at,
      periods: {
        for (final p in StatsPeriod.values)
          p: p == StatsPeriod.month || p == StatsPeriod.week
              ? period(p)
              : big(p),
      },
    );
    final g2 = StatsSummary.fromJson(jsonDecode(jsonEncode(small.toJson())))!;
    expect(g2.periods[StatsPeriod.week]!.topArtists, hasLength(1));
    expect(g2.periods[StatsPeriod.month]!.topSongs, hasLength(1));
    expect(g2.periods[StatsPeriod.year]!.topArtists, isEmpty);
  });

  test('maxBytes leaves room for the spaces jsonb text adds', () {
    // Many short entries: the most separators per byte.
    PeriodStats many(StatsPeriod p) => PeriodStats(
      period: p,
      total: const Duration(hours: 1),
      previousTotal: const Duration(hours: 1),
      buckets: [
        for (var i = 0; i < 400; i++)
          StatsBucket(
            start: DateTime(2025, 1, 1).add(Duration(days: i)),
            end: DateTime(2025, 1, 2).add(Duration(days: i)),
            heard: const Duration(seconds: 1),
          ),
      ],
      topArtists: [
        for (var i = 0; i < 10; i++)
          ArtistStat(name: 'a', plays: 1, heard: Duration.zero),
      ],
      topSongs: const [],
    );
    final j = StatsSummary(
      at: at,
      periods: {for (final p in StatsPeriod.values) p: many(p)},
    ).toJson();
    final compact = utf8.encode(jsonEncode(j)).length;
    final spaced = utf8.encode(jsonbText(j)).length;
    // The spaces add well under the room maxBytes keeps below 64 kB.
    expect(
      (spaced - compact) / compact,
      lessThan((65536 - StatsSummary.maxBytes) / StatsSummary.maxBytes),
    );
  });

  test(
    'gather fills photos and pages from the cache into every period',
    () async {
      final db = testDb();
      addTearDown(db.close);
      final photos = ArtistPhotos(
        settings: SettingsRepository(db),
        saved: () async => const {},
        browseIdForTrack: (t) async => 'UC-$t',
        artist: (b) async => (browseId: b, photoUrl: 'https://img/$b'),
      );
      final s = await StatsSummary.gather(
        at: at,
        period: (p) async => PeriodStats(
          period: p,
          total: const Duration(minutes: 5),
          previousTotal: null,
          buckets: const [],
          topArtists: [
            ArtistStat(
              name: 'Artist ${p.name}',
              plays: 1,
              heard: const Duration(minutes: 5),
              sampleTrackId: p.name,
            ),
          ],
          topSongs: const [],
        ),
        photos: photos,
      );
      for (final p in StatsPeriod.values) {
        final a = s.periods[p]!.topArtists.single;
        expect(a.browseId, 'UC-${p.name}');
        expect(a.photoUrl, 'https://img/UC-${p.name}');
      }
      expect(s.at, at);
    },
  );
}
