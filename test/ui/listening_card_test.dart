// Home's "Your listening" card: content, empty state, navigation, placement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songies/providers.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/stats/stats_repository.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/stats/listening_card.dart';

import '../helpers/ui_harness.dart';

class _FakeStats implements StatsRepository {
  _FakeStats(this.stats);

  final PeriodStats stats;

  @override
  Stream<PeriodStats> watch(StatsPeriod p) => Stream.value(stats);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PeriodStats _week({int minutes = 123, List<ArtistStat>? artists}) =>
    PeriodStats(
      period: StatsPeriod.week,
      total: Duration(minutes: minutes),
      previousTotal: null,
      buckets: [
        for (var i = 0; i < 7; i++)
          StatsBucket(
            start: DateTime(2026, 10, 23 + i),
            end: DateTime(2026, 10, 24 + i),
            heard: Duration(minutes: minutes == 0 ? 0 : 5 + i),
          ),
      ],
      topArtists:
          artists ??
          (minutes == 0
              ? const []
              : const [
                  ArtistStat(
                    name: 'Daft Punk',
                    plays: 12,
                    heard: Duration(minutes: 40),
                  ),
                ]),
      topSongs: const [],
    );

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester,
    PeriodStats stats, {
    Size size = const Size(400, 800),
    Widget home = const Scaffold(body: Center(child: ListeningCard())),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    h.stats = _FakeStats(stats);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => home,
            routes: [
              GoRoute(
                path: 'stats',
                builder: (_, _) => Consumer(
                  builder: (_, ref, _) =>
                      Text('stats ${ref.watch(statsPeriodProvider).name}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('shows the week minutes, a 7-bar chart and the top artist', (
    tester,
  ) async {
    await pump(tester, _week());
    expect(find.text('Your listening'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('home.listening.minutes'))).data,
      '123 min',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('home.listening.top'))).data,
      'Most played: Daft Punk · 12 plays',
    );
    expect(
      find.bySemanticsLabel(
        'Your listening: 123 min in the last 7 days, most played Daft Punk',
      ),
      findsOneWidget,
    );
  });

  uiTest('no top artist hides the top line', (tester) async {
    await pump(tester, _week(artists: const []));
    expect(find.byKey(const Key('home.listening.minutes')), findsOneWidget);
    expect(find.byKey(const Key('home.listening.top')), findsNothing);
  });

  uiTest('no listens says so, at the same height', (tester) async {
    await pump(tester, _week(minutes: 0));
    expect(find.text('Your listening stats will show up here'), findsOneWidget);
    expect(find.byKey(const Key('home.listening.minutes')), findsNothing);
    // The same height as the card with content (ListeningCard.height).
    expect(
      tester.getSize(find.byKey(const Key('home.listening'))).height,
      ListeningCard.height,
    );
  });

  uiTest('with content it is the same height, under 120', (tester) async {
    await pump(tester, _week());
    final height = tester
        .getSize(find.byKey(const Key('home.listening')))
        .height;
    expect(height, ListeningCard.height);
    expect(height, lessThanOrEqualTo(120));
  });

  uiTest('a tap opens the stats page on the week', (tester) async {
    await pump(tester, _week());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ListeningCard)),
    );
    container.read(statsPeriodProvider.notifier).select(StatsPeriod.year);
    await tester.tap(find.byKey(const Key('home.listening')));
    await settle(tester);
    expect(find.text('stats week'), findsOneWidget);
  });

  for (final size in const [Size(400, 800), Size(1280, 800)]) {
    uiTest('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await pump(tester, _week(), size: size);
      expect(tester.takeException(), isNull);
    });
    uiTest('no overflow when empty at ${size.width.toInt()}', (tester) async {
      await pump(tester, _week(minutes: 0), size: size);
      expect(tester.takeException(), isNull);
    });
  }

  uiTest('on Home it sits between the tiles and Your playlists, in view', (
    tester,
  ) async {
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      await real(tester, () async {
        await h.addTrack('t$i');
        ids.add(await h.addPlaylist('List $i', ['t$i']));
      });
    }
    await pump(tester, _week(), home: const Scaffold(body: HomePage()));
    final card = tester.getRect(find.byType(ListeningCard));
    final title = tester.getRect(find.text('Your playlists'));
    for (final id in ids.take(4)) {
      final tile = tester.getRect(find.byKey(Key('home.tile.$id')));
      expect(tile.bottom, lessThanOrEqualTo(card.top));
    }
    expect(card.bottom, lessThanOrEqualTo(title.top));
    expect(title.top, lessThan(800));
  });

  uiTest('with no playlists it follows the empty state', (tester) async {
    await pump(tester, _week(), home: const Scaffold(body: HomePage()));
    expect(
      tester.getTopLeft(find.byType(ListeningCard)).dy,
      greaterThan(tester.getBottomLeft(find.text('Your music lives here')).dy),
    );
  });
}
