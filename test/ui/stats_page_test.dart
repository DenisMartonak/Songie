// The stats page: period picker, total and comparison, chart, top artists
// and top songs, and the empty state.
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/providers.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/stats/stats_repository.dart';
import 'package:songies/ui/stats/stats_page.dart';
import 'package:songies/ui/widgets/page_surface.dart';

import '../helpers/ui_harness.dart';

/// Scripted stats per period, recording which periods were asked for.
class _FakeStats implements StatsRepository {
  _FakeStats(this.byPeriod);

  final Map<StatsPeriod, PeriodStats> byPeriod;
  final List<StatsPeriod> watched = [];

  /// Periods whose stats arrive only when the test adds them.
  final Map<StatsPeriod, StreamController<PeriodStats>> held = {};

  @override
  Stream<PeriodStats> watch(StatsPeriod p) {
    watched.add(p);
    if (held[p] case final c?) return c.stream;
    return Stream.value(byPeriod[p]!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<StatsBucket> _days(int count, int minutesEach) => [
  for (var i = 0; i < count; i++)
    StatsBucket(
      start: DateTime(2026, 10, 30 - count + i),
      end: DateTime(2026, 10, 31 - count + i),
      heard: Duration(minutes: i == 0 ? 0 : minutesEach),
    ),
];

final _artists = [
  for (var i = 1; i <= 10; i++)
    ArtistStat(
      name: 'Artist $i',
      plays: 20 - i,
      heard: Duration(minutes: 60 - i),
      sampleTrackId: 's$i',
    ),
];

final _songs = [
  for (var i = 1; i <= 10; i++)
    SongStat(
      trackId: 's$i',
      title: 'Snapshot $i',
      artist: 'Artist $i feat. Guest',
      // The last has no known main artist: its artist line shows.
      mainArtist: i == 10 ? '' : 'Artist $i',
      plays: i == 1 ? 1 : 15 - i,
      heard: Duration(minutes: 40 - i),
    ),
];

PeriodStats _stats(
  StatsPeriod p, {
  required int total,
  int? previous,
  int bars = 7,
}) => PeriodStats(
  period: p,
  total: Duration(minutes: total),
  previousTotal: previous == null ? null : Duration(minutes: previous),
  buckets: _days(bars, 10),
  topArtists: total == 0 ? const [] : _artists,
  topSongs: total == 0 ? const [] : _songs,
);

final _empty = PeriodStats(
  period: StatsPeriod.year,
  total: Duration.zero,
  previousTotal: null,
  buckets: _days(12, 0),
  topArtists: const [],
  topSongs: const [],
);

void main() {
  late UiHarness h;
  late _FakeStats stats;

  setUp(() async {
    h = await UiHarness.create();
    stats = _FakeStats({
      StatsPeriod.week: _stats(StatsPeriod.week, total: 1234, previous: 1102),
      StatsPeriod.month: _stats(
        StatsPeriod.month,
        total: 46,
        previous: 50,
        bars: 30,
      ),
      StatsPeriod.halfYear: _stats(StatsPeriod.halfYear, total: 300, bars: 26),
      StatsPeriod.year: _empty,
    });
    h.stats = stats;
  });
  tearDown(() => h.dispose());

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    String? knownArtistPage,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home/stats',
        disableAnimations: disableAnimations,
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Text('home'),
            routes: [
              GoRoute(
                path: 'stats',
                builder: (_, _) => const PageSurface(child: StatsPage()),
              ),
              GoRoute(
                path: 'ytm/artist/:id',
                builder: (_, s) => Text('artist ${s.pathParameters['id']}'),
              ),
            ],
          ),
          GoRoute(
            path: '/search',
            builder: (_, _) => Consumer(
              builder: (_, ref, _) =>
                  Text('search: ${ref.watch(searchQueryProvider)}'),
            ),
          ),
        ],
        extraOverrides: [
          if (knownArtistPage != null)
            statsArtistPageProvider.overrideWithValue(
              (trackId) async => trackId == 's1' ? knownArtistPage : null,
            ),
        ],
      ),
    );
    await settle(tester);
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Finder bars() => find.descendant(
    of: find.byKey(const Key('stats.chart')),
    matching: find.byWidgetPredicate(
      (w) => switch (w.key) {
        ValueKey<String>(:final value) => value.startsWith('stats.bar.'),
        _ => false,
      },
    ),
  );

  uiTest('the picker switches periods and asks for each', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester);
    expect(stats.watched, [StatsPeriod.week]);
    expect(text(tester, 'stats.total'), '1,234 min');

    await tester.tap(find.byKey(const Key('stats.period.month')));
    await settle(tester);
    expect(stats.watched.last, StatsPeriod.month);
    expect(text(tester, 'stats.total'), '46 min');

    await tester.tap(find.byKey(const Key('stats.period.halfYear')));
    await settle(tester);
    expect(stats.watched.last, StatsPeriod.halfYear);

    await tester.tap(find.byKey(const Key('stats.period.year')));
    await settle(tester);
    expect(stats.watched.last, StatsPeriod.year);
  });

  uiTest('the total and the change with the previous period', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester);
    // 1234 / 1102 = +11.98 %.
    expect(text(tester, 'stats.change'), '+12% vs the previous 7 days');

    await tester.tap(find.byKey(const Key('stats.period.month')));
    await settle(tester);
    expect(text(tester, 'stats.change'), '−8% vs the previous month');

    await tester.tap(find.byKey(const Key('stats.period.halfYear')));
    await settle(tester);
    expect(text(tester, 'stats.total'), '300 min');
    expect(find.byKey(const Key('stats.change')), findsNothing);
  });

  uiTest('an unchanged total says so', (tester) async {
    size(tester, const Size(400, 800));
    stats.byPeriod[StatsPeriod.week] = _stats(
      StatsPeriod.week,
      total: 100,
      previous: 100,
    );
    await pumpPage(tester);
    expect(text(tester, 'stats.change'), 'Same as the previous 7 days');
  });

  uiTest('the chart has a bar per bucket; a tap shows its minutes', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester);
    expect(bars(), findsNWidgets(7));

    await tester.tap(find.byKey(const Key('stats.bar.6')));
    await tester.pumpAndSettle();
    expect(find.text('Thu 29 Oct · 10 min'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.byKey(const Key('stats.period.month')));
    await settle(tester);
    expect(bars(), findsNWidgets(30));
  });

  uiTest('top 5 artists and songs, then Show top 10', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester);
    expect(find.byKey(const Key('stats.artist.4')), findsOneWidget);
    expect(find.byKey(const Key('stats.artist.5')), findsNothing);
    expect(find.text('19 plays'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.artists.more')),
      200,
    );
    await tester.tap(find.byKey(const Key('stats.artists.more')));
    await settle(tester);
    expect(find.byKey(const Key('stats.artists.more')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.artist.9')),
      200,
    );
    expect(find.text('Artist 10'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.songs.more')),
      200,
    );
    expect(find.byKey(const Key('stats.song.5')), findsNothing);
    await tester.tap(find.byKey(const Key('stats.songs.more')));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('stats.song.9')), 200);
    expect(find.text('Snapshot 10'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('stats.song.9')),
        matching: find.text('Artist 10 feat. Guest'),
      ),
      findsOneWidget,
    );
    // One play reads "1 play".
    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.song.0')),
      -200,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stats.song.0')),
        matching: find.text('1 play'),
      ),
      findsOneWidget,
    );
    // Top songs show the main artist, not the whole artist line.
    expect(
      find.descendant(
        of: find.byKey(const Key('stats.song.0')),
        matching: find.text('Artist 1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Artist 1 feat. Guest'), findsNothing);
  });

  uiTest('tapping a song plays it; a removed song has no menu or tap', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await real(tester, () => h.addTrack('s1', title: 'Live title'));
    await pumpPage(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('stats.song.1')), 200);

    // Still in the library: the snapshot shows, the menu is there.
    expect(find.text('Snapshot 1'), findsOneWidget);
    expect(find.byKey(const Key('stats.song.menu.0')), findsOneWidget);
    // Removed: no menu.
    expect(find.byKey(const Key('stats.song.menu.1')), findsNothing);

    await tester.tap(find.byKey(const Key('stats.song.1')));
    await settle(tester);
    expect(h.player.state.queue, isEmpty);

    await tester.tap(find.byKey(const Key('stats.song.0')));
    await settle(tester);
    expect(h.player.state.queue.map((t) => t.id), ['s1']);
  });

  uiTest('an artist with a known page opens it', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester, knownArtistPage: 'UCone');
    await tester.tap(find.byKey(const Key('stats.artist.0')));
    await settle(tester);
    expect(find.text('artist UCone'), findsOneWidget);
  });

  uiTest('an artist without a known page opens Search for their name', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester, knownArtistPage: 'UCone');
    await tester.tap(find.byKey(const Key('stats.artist.1')));
    await settle(tester);
    expect(find.byType(StatsPage), findsNothing);
    expect(find.text('search: Artist 2'), findsOneWidget);
  });

  uiTest('a library song gives no artist page, so Search opens', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    // Library tracks keep no YouTube Music artist page (the song menu's
    // Go to artist rule).
    await real(tester, () => h.addTrack('s1'));
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('stats.artist.0')));
    await settle(tester);
    expect(find.text('search: Artist 1'), findsOneWidget);
    expect(find.textContaining('artist U'), findsNothing);
  });

  uiTest('a soft-deleted top song has no menu and its tap does nothing', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await real(tester, () async {
      await h.addTrack('s1');
      await (h.db.update(h.db.tracks)..where((t) => t.id.equals('s1'))).write(
        const TracksCompanion(deleted: Value(true)),
      );
    });
    await pumpPage(tester);
    expect(find.text('Snapshot 1'), findsOneWidget);
    expect(find.byKey(const Key('stats.song.menu.0')), findsNothing);
    await tester.tap(find.byKey(const Key('stats.song.0')));
    await settle(tester);
    expect(h.player.state.queue, isEmpty);
  });

  uiTest('the old stats stay until the new period arrives', (tester) async {
    size(tester, const Size(400, 800));
    final month = StreamController<PeriodStats>();
    addTearDown(month.close);
    stats.held[StatsPeriod.month] = month;
    await pumpPage(tester);
    expect(text(tester, 'stats.total'), '1,234 min');

    await tester.tap(find.byKey(const Key('stats.period.month')));
    await settle(tester);
    expect(stats.watched.last, StatsPeriod.month);
    // Still the week's, dimmed, with nothing animating.
    expect(text(tester, 'stats.total'), '1,234 min');
    expect(tester.binding.hasScheduledFrame, isFalse);

    month.add(stats.byPeriod[StatsPeriod.month]!);
    await settle(tester);
    expect(text(tester, 'stats.total'), '46 min');
    expect(text(tester, 'stats.change'), '\u22128% vs the previous month');
  });

  uiTest('an empty period shows only the message', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('stats.period.year')));
    await settle(tester);
    expect(find.byKey(const Key('stats.empty')), findsOneWidget);
    expect(find.text('Nothing played in this period yet'), findsOneWidget);
    expect(find.byKey(const Key('stats.total')), findsNothing);
    expect(find.byKey(const Key('stats.chart')), findsNothing);
    expect(find.byKey(const Key('stats.artist.0')), findsNothing);
    expect(find.byKey(const Key('stats.song.0')), findsNothing);
  });

  for (final s in const [Size(400, 800), Size(1280, 800)]) {
    uiTest('nothing overflows at ${s.width.round()}x${s.height.round()}', (
      tester,
    ) async {
      size(tester, s);
      await pumpPage(tester);
      for (final p in StatsPeriod.values) {
        await tester.tap(find.byKey(Key('stats.period.${p.name}')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('stats.period.month')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('stats.artists.more')),
        200,
      );
      await tester.tap(find.byKey(const Key('stats.artists.more')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('stats.songs.more')),
        200,
      );
      await tester.tap(find.byKey(const Key('stats.songs.more')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('stats.song.9')),
        200,
      );
      expect(tester.takeException(), isNull);
    });
  }

  uiTest('with reduced motion nothing keeps animating', (tester) async {
    size(tester, const Size(400, 800));
    await pumpPage(tester, disableAnimations: true);
    await tester.tap(find.byKey(const Key('stats.period.month')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('stats.bar.3')));
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
