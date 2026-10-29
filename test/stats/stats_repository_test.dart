import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/providers.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/stats/stats_repository.dart';

import '../helpers/test_db.dart';

var _seq = 0;

ListensCompanion _listen({
  required DateTime at,
  String trackId = 't1',
  Duration heard = const Duration(minutes: 3),
  bool counted = true,
  String mainArtist = 'Artist',
  String? title,
  String? artist,
  String? artworkRef,
}) {
  _seq++;
  return ListensCompanion.insert(
    id: 'l$_seq',
    clock: '${_seq.toString().padLeft(13, '0')}-00000-dev',
    originDevice: 'dev',
    localSeq: _seq,
    trackId: trackId,
    startedAt: at,
    heardMs: heard.inMilliseconds,
    counted: counted,
    mainArtist: mainArtist,
    titleSnapshot: title ?? 'Title $trackId',
    artistSnapshot: artist ?? mainArtist,
    artworkRef: Value(artworkRef),
  );
}

void main() {
  late AppDatabase db;
  // "Local" time is UTC in these tests unless a test injects its own
  // toLocal, so results do not depend on the machine's time zone.
  final now = DateTime.utc(2026, 10, 29, 12);
  late StatsRepository repo;

  StatsRepository make({
    DateTime Function(DateTime utc)? toLocal,
    Duration throttle = const Duration(seconds: 5),
  }) => StatsRepository(
    db,
    now: () => now,
    toLocal: toLocal ?? (u) => u,
    throttle: throttle,
  );

  Future<void> insert(List<ListensCompanion> rows) =>
      db.batch((b) => b.insertAll(db.listens, rows));

  setUp(() {
    db = testDb();
    repo = make();
  });
  tearDown(() => db.close());

  test('StatsPeriod has the day counts and labels', () {
    expect(StatsPeriod.values.map((p) => p.days), [7, 30, 182, 365]);
    expect(StatsPeriod.values.map((p) => p.label), [
      '7 days',
      '1 month',
      '6 months',
      '12 months',
    ]);
  });

  group('totals', () {
    test('sums the period and the previous period', () async {
      await insert([
        // Today and the first day of the 7-day period (Oct 23).
        _listen(at: DateTime.utc(2026, 10, 29, 8)),
        _listen(at: DateTime.utc(2026, 10, 23, 0, 0)),
        // Previous period: Oct 16 .. Oct 22.
        _listen(
          at: DateTime.utc(2026, 10, 22, 23, 59),
          heard: const Duration(minutes: 10),
        ),
        _listen(
          at: DateTime.utc(2026, 10, 16),
          heard: const Duration(minutes: 1),
        ),
        // Before the previous period: ignored.
        _listen(at: DateTime.utc(2026, 10, 15, 23, 59)),
      ]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.period, StatsPeriod.week);
      expect(s.total, const Duration(minutes: 6));
      expect(s.previousTotal, const Duration(minutes: 11));
      expect(s.isEmpty, isFalse);
    });

    test('previousTotal is null when the previous period is empty', () async {
      await insert([_listen(at: DateTime.utc(2026, 10, 28))]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.total, const Duration(minutes: 3));
      expect(s.previousTotal, isNull);
    });

    test('a period with no listens is empty', () async {
      await insert([_listen(at: DateTime.utc(2026, 10, 20))]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.isEmpty, isTrue);
      expect(s.total, Duration.zero);
      expect(s.previousTotal, const Duration(minutes: 3));
      expect(s.topArtists, isEmpty);
      expect(s.topSongs, isEmpty);
      expect(s.buckets, hasLength(7));
    });

    test('deleted listens are ignored', () async {
      await insert([
        _listen(at: DateTime.utc(2026, 10, 28))
            .copyWith(deleted: const Value(true)),
      ]);
      expect((await repo.period(StatsPeriod.week)).isEmpty, isTrue);
    });
  });

  group('buckets', () {
    DateTime d(DateTime t) => DateTime.utc(t.year, t.month, t.day, t.hour);

    test('week has 7 daily buckets ending tomorrow', () async {
      final b = (await repo.period(StatsPeriod.week)).buckets;
      expect(b, hasLength(7));
      expect(d(b.first.start), DateTime.utc(2026, 10, 23));
      expect(d(b.first.end), DateTime.utc(2026, 10, 24));
      expect(d(b.last.start), DateTime.utc(2026, 10, 29));
      expect(d(b.last.end), DateTime.utc(2026, 10, 30));
    });

    test('month has 30 daily buckets', () async {
      final b = (await repo.period(StatsPeriod.month)).buckets;
      expect(b, hasLength(30));
      expect(d(b.first.start), DateTime.utc(2026, 9, 30));
      expect(d(b.last.end), DateTime.utc(2026, 10, 30));
      for (var i = 1; i < b.length; i++) {
        expect(b[i].start, b[i - 1].end);
      }
    });

    test('halfYear has 26 rolling 7-day blocks ending today', () async {
      final b = (await repo.period(StatsPeriod.halfYear)).buckets;
      expect(b, hasLength(26));
      expect(d(b.first.start), DateTime.utc(2026, 5, 1));
      expect(d(b.first.end), DateTime.utc(2026, 5, 8));
      expect(d(b.last.start), DateTime.utc(2026, 10, 23));
      expect(d(b.last.end), DateTime.utc(2026, 10, 30));
      for (var i = 1; i < b.length; i++) {
        expect(b[i].start, b[i - 1].end);
      }
    });

    test('year has calendar months, the oldest starting at the period '
        'start', () async {
      final b = (await repo.period(StatsPeriod.year)).buckets;
      // Oct 30 2025 .. Oct 29 2026: Oct 2025 (partial) + 12 months.
      expect(b, hasLength(13));
      expect(d(b.first.start), DateTime.utc(2025, 10, 30));
      expect(d(b.first.end), DateTime.utc(2025, 11, 1));
      expect(d(b[1].start), DateTime.utc(2025, 11, 1));
      expect(d(b[1].end), DateTime.utc(2025, 12, 1));
      expect(d(b.last.start), DateTime.utc(2026, 10, 1));
      expect(d(b.last.end), DateTime.utc(2026, 10, 30));
    });

    test('year has 12 buckets when the period starts on the 1st', () async {
      repo = StatsRepository(
        db,
        now: () => DateTime.utc(2026, 10, 31, 12),
        toLocal: (u) => u,
      );
      final b = (await repo.period(StatsPeriod.year)).buckets;
      expect(b, hasLength(12));
      expect(d(b.first.start), DateTime.utc(2025, 11, 1));
      expect(d(b.first.end), DateTime.utc(2025, 12, 1));
    });

    test('each listen lands wholly in the bucket of its start', () async {
      await insert([
        _listen(at: DateTime.utc(2026, 10, 27, 10)),
        _listen(at: DateTime.utc(2026, 10, 27, 20)),
        _listen(
          at: DateTime.utc(2026, 10, 29, 1),
          heard: const Duration(minutes: 1),
        ),
      ]);
      final b = (await repo.period(StatsPeriod.week)).buckets;
      expect(b.map((x) => x.heard.inMinutes), [0, 0, 0, 0, 6, 0, 1]);
    });

    test('a listen at 23:59 counts on that day even when it ran past '
        'midnight', () async {
      await insert([
        _listen(
          at: DateTime.utc(2026, 10, 27, 23, 59),
          heard: const Duration(minutes: 40),
        ),
      ]);
      final b = (await repo.period(StatsPeriod.week)).buckets;
      expect(b.map((x) => x.heard.inMinutes), [0, 0, 0, 0, 40, 0, 0]);
    });

    test('each listen lands on its local day across a DST shift', () async {
      // Local is UTC until Oct 26 00:00 UTC, then UTC+1.
      final shift = DateTime.utc(2026, 10, 26);
      DateTime toLocal(DateTime u) =>
          u.isBefore(shift) ? u : u.add(const Duration(hours: 1));
      repo = make(toLocal: toLocal);
      await insert([
        // Before the shift: 23:30 local on Oct 24.
        _listen(
          at: DateTime.utc(2026, 10, 24, 23, 30),
          heard: const Duration(minutes: 1),
        ),
        // After the shift: 23:30 UTC is 00:30 local on Oct 28.
        _listen(
          at: DateTime.utc(2026, 10, 27, 23, 30),
          heard: const Duration(minutes: 2),
        ),
        // 22:59 UTC is 23:59 local on Oct 27.
        _listen(
          at: DateTime.utc(2026, 10, 27, 22, 59),
          heard: const Duration(minutes: 4),
        ),
        // 23:30 UTC on Oct 29 is 00:30 local on Oct 30: tomorrow, excluded.
        _listen(
          at: DateTime.utc(2026, 10, 29, 23, 30),
          heard: const Duration(minutes: 8),
        ),
      ]);
      final b = (await repo.period(StatsPeriod.week)).buckets;
      expect(b.map((x) => x.heard.inMinutes), [0, 1, 0, 0, 4, 2, 0]);
    });
  });

  group('top artists', () {
    test('ranked by plays, then minutes, then name', () async {
      final day = DateTime.utc(2026, 10, 28);
      await insert([
        // B: 2 plays, 6 min.
        _listen(at: day, mainArtist: 'B', trackId: 'b1'),
        _listen(at: day, mainArtist: 'B', trackId: 'b1'),
        // C: 2 plays, 6 min + 10 min uncounted = 16 min.
        _listen(at: day, mainArtist: 'C', trackId: 'c1'),
        _listen(at: day, mainArtist: 'C', trackId: 'c1'),
        _listen(
          at: day,
          mainArtist: 'C',
          trackId: 'c1',
          heard: const Duration(minutes: 10),
          counted: false,
        ),
        // A: 2 plays, 6 min, ties with B, wins by name.
        _listen(at: day, mainArtist: 'A', trackId: 'a1'),
        _listen(at: day, mainArtist: 'A', trackId: 'a1'),
        // D: 3 plays.
        for (var i = 0; i < 3; i++)
          _listen(at: day, mainArtist: 'D', trackId: 'd1'),
        // Empty main artist: excluded.
        for (var i = 0; i < 5; i++)
          _listen(at: day, mainArtist: '  ', trackId: 'x1'),
      ]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.topArtists.map((a) => a.name), ['D', 'C', 'A', 'B']);
      final c = s.topArtists[1];
      expect(c.plays, 2);
      expect(c.heard, const Duration(minutes: 16));
    });

    test('names merge case-insensitively with the latest spelling', () async {
      await insert([
        _listen(at: DateTime.utc(2026, 10, 27), mainArtist: 'Daft Punk'),
        _listen(at: DateTime.utc(2026, 10, 28), mainArtist: 'daft punk '),
        _listen(at: DateTime.utc(2026, 10, 26), mainArtist: 'DAFT PUNK'),
      ]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.topArtists, hasLength(1));
      expect(s.topArtists.single.name, 'daft punk');
      expect(s.topArtists.single.plays, 3);
    });

    test('artwork comes from the most-played song', () async {
      final day = DateTime.utc(2026, 10, 28);
      await insert([
        _listen(at: day, mainArtist: 'A', trackId: 's1', artworkRef: 'one'),
        _listen(at: day, mainArtist: 'A', trackId: 's2', artworkRef: 'two'),
        _listen(at: day, mainArtist: 'A', trackId: 's2', artworkRef: 'two'),
        _listen(
          at: day,
          mainArtist: 'A',
          trackId: 's1',
          artworkRef: 'one',
          heard: const Duration(minutes: 30),
          counted: false,
        ),
      ]);
      final a = (await repo.period(StatsPeriod.week)).topArtists.single;
      expect(a.artworkRef, 'two');
      expect(a.sampleTrackId, 's2');
    });

    test('holds at most 10', () async {
      await insert([
        for (var i = 0; i < 15; i++)
          _listen(
            at: DateTime.utc(2026, 10, 28),
            mainArtist: 'Artist $i',
            trackId: 't$i',
          ),
      ]);
      final s = await repo.period(StatsPeriod.week);
      expect(s.topArtists, hasLength(10));
      expect(s.topSongs, hasLength(10));
    });
  });

  group('top songs', () {
    test('ranked by plays then minutes, with the latest snapshot', () async {
      await insert([
        _listen(at: DateTime.utc(2026, 10, 28), trackId: 's1'),
        _listen(
          at: DateTime.utc(2026, 10, 27),
          trackId: 's2',
          title: 'Old title',
          artist: 'Old artist',
          artworkRef: 'old',
        ),
        _listen(
          at: DateTime.utc(2026, 10, 28, 9),
          trackId: 's2',
          title: 'New title',
          artist: 'New artist',
          artworkRef: 'new',
        ),
        _listen(
          at: DateTime.utc(2026, 10, 25),
          trackId: 's3',
          heard: const Duration(minutes: 9),
        ),
        _listen(
          at: DateTime.utc(2026, 10, 25),
          trackId: 's4',
          heard: const Duration(minutes: 20),
          counted: false,
        ),
      ]);
      final songs = (await repo.period(StatsPeriod.week)).topSongs;
      expect(songs.map((s) => s.trackId), ['s2', 's3', 's1', 's4']);
      final s2 = songs.first;
      expect(s2.title, 'New title');
      expect(s2.artist, 'New artist');
      expect(s2.artworkRef, 'new');
      expect(s2.plays, 2);
      expect(s2.heard, const Duration(minutes: 6));
      expect(songs.last.plays, 0);
      expect(songs.last.heard, const Duration(minutes: 20));
    });
  });

  test('a year of 40,000 listens answers in under 500 ms', () async {
    const n = 40000;
    final start = DateTime.utc(2025, 10, 30);
    final span = const Duration(days: 365).inMinutes;
    await insert([
      for (var i = 0; i < n; i++)
        _listen(
          at: start.add(Duration(minutes: span * i ~/ n)),
          trackId: 't${i % 2000}',
          mainArtist: 'Artist ${i % 300}',
          counted: i % 7 != 0,
        ),
    ]);
    // Warm up once so the timing measures the query, not first-use setup.
    await repo.period(StatsPeriod.week);
    final sw = Stopwatch()..start();
    final s = await repo.period(StatsPeriod.year);
    sw.stop();
    printOnFailure('period(year): ${sw.elapsedMilliseconds} ms');
    expect(s.total, const Duration(minutes: 3 * n));
    expect(s.buckets, hasLength(13));
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  group('watch', () {
    test('emits again after a new listen and coalesces bursts', () async {
      repo = make(throttle: const Duration(milliseconds: 300));
      final got = <PeriodStats>[];
      final sub = repo.watch(StatsPeriod.week).listen(got.add);
      addTearDown(sub.cancel);

      await _until(() => got.isNotEmpty);
      expect(got.single.isEmpty, isTrue);

      // First change: emitted promptly.
      await insert([_listen(at: DateTime.utc(2026, 10, 28))]);
      await _until(() => got.length == 2);
      expect(got[1].total, const Duration(minutes: 3));

      // A burst inside the throttle window: one trailing emission with the
      // final state.
      for (var i = 0; i < 5; i++) {
        await insert([_listen(at: DateTime.utc(2026, 10, 28))]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(got, hasLength(3));
      expect(got.last.total, const Duration(minutes: 18));
    });

    test('stops watching when cancelled', () async {
      repo = make(throttle: const Duration(milliseconds: 50));
      final got = <PeriodStats>[];
      final sub = repo.watch(StatsPeriod.week).listen(got.add);
      await _until(() => got.isNotEmpty);
      await sub.cancel();
      await insert([_listen(at: DateTime.utc(2026, 10, 28))]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(got, hasLength(1));
    });
  });

  group('providers', () {
    test('the period starts at 7 days and can be changed', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(statsPeriodProvider), StatsPeriod.week);
      c.read(statsPeriodProvider.notifier).select(StatsPeriod.year);
      expect(c.read(statsPeriodProvider), StatsPeriod.year);
    });

    test('periodStatsProvider streams the repository\'s stats', () async {
      await insert([_listen(at: DateTime.utc(2026, 10, 28))]);
      final c = ProviderContainer(
        overrides: [statsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(periodStatsProvider(StatsPeriod.week), (_, _) {});
      addTearDown(sub.close);
      final s = await c.read(periodStatsProvider(StatsPeriod.week).future);
      expect(s.total, const Duration(minutes: 3));
    });
  });
}

Future<void> _until(bool Function() ok) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ok()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
