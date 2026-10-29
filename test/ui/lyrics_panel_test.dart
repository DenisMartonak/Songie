import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/lyrics/lyrics_panel.dart';
import 'package:songies/ui/lyrics/lyrics_view.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/shell/sidebar.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late FakeLyricsService service;
  late GoRouter router;

  setUp(() async {
    h = await UiHarness.create();
    service = FakeLyricsService()
      ..answers['t1'] = const LyricsShown(
        TrackLyrics(
          kind: LyricsKind.plain,
          source: LyricsSource.lrclib,
          text: 'First invented line\nSecond invented line',
        ),
      );
  });
  tearDown(() => h.dispose());

  /// The whole app on a desktop window ([size], 1280x800 by default); with [play], the seeded
  /// songs are queued and the first one plays.
  Future<void> pumpApp(
    WidgetTester tester, {
    bool play = true,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one', artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
    });
    router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          lyricsServiceProvider.overrideWithValue(service),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
    if (play) {
      final tracks = await real(
        tester,
        () => (h.db.select(
          h.db.tracks,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
      );
      await real(tester, () => h.player.playQueue(tracks));
      await settle(tester);
    }
  }

  final button = find.byKey(const Key('playerBar.lyrics'));
  final panel = find.byKey(const Key('lyricsPanel'));

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(button);
    await settle(tester);
  }

  SongiesColors colorsOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(PlayerBar)))
          .extension<SongiesColors>()!;

  uiTest('closed by default: no panel and no lookups', (tester) async {
    await pumpApp(tester);
    expect(button, findsOneWidget);
    expect(panel, findsNothing);
    expect(find.byType(LyricsView), findsNothing);
    expect(service.lookups, isEmpty);
  });

  uiTest('the Lyrics button sits before Queue', (tester) async {
    await pumpApp(tester);
    expect(
      tester.getCenter(button).dx,
      lessThan(tester.getCenter(find.byKey(const Key('playerBar.queue'))).dx),
    );
    expect(tester.widget<IconButton>(button).tooltip, 'Lyrics');
  });

  uiTest('toggles a compact panel, 320 px wide, right of the main pane', (
    tester,
  ) async {
    await pumpApp(tester);
    final shell = find.byType(StatefulNavigationShell);
    final paneRight = tester.getTopRight(shell).dx;

    await toggle(tester);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, 320);
    expect(tester.getTopRight(panel).dx, 1280 - 8);
    expect(
      tester.getTopLeft(panel).dx,
      greaterThan(tester.getTopRight(shell).dx),
    );
    expect(tester.getTopRight(shell).dx, lessThan(paneRight));
    final view = tester.widget<LyricsView>(
      find.descendant(of: panel, matching: find.byType(LyricsView)),
    );
    expect(view.density, LyricsDensity.compact);
    expect(find.textContaining('First invented line'), findsOneWidget);
    expect(service.lookups.map((l) => l.id), ['t1']);
    // Same surface as the main pane: the background colour, rounded.
    final surface = tester.widget<ColoredBox>(
      find.descendant(of: panel, matching: find.byType(ColoredBox)).first,
    );
    expect(surface.color, colorsOf(tester).background);

    await toggle(tester);
    expect(panel, findsNothing);
    expect(find.byType(LyricsView), findsNothing);
    expect(tester.getTopRight(shell).dx, paneRight);
  });

  uiTest('the button shows the open state', (tester) async {
    await pumpApp(tester);
    final colors = colorsOf(tester);
    Icon icon() => tester.widget<Icon>(
      find.descendant(of: button, matching: find.byType(Icon)),
    );
    expect(icon().icon, Icons.lyrics_outlined);

    await toggle(tester);
    expect(icon().icon, Icons.lyrics);
    final open = tester.widget<IconButton>(button);
    expect(open.color, colors.accent);

    await toggle(tester);
    expect(icon().icon, Icons.lyrics_outlined);
  });

  uiTest('stays open across tabs', (tester) async {
    await pumpApp(tester);
    await toggle(tester);
    router.go('/library');
    await settle(tester);
    expect(router.state.uri.path, '/library');
    expect(panel, findsOneWidget);
    expect(find.textContaining('First invented line'), findsOneWidget);
    router.go('/home');
    await settle(tester);
    expect(panel, findsOneWidget);
  });

  uiTest('with no song, the panel is empty but still toggles', (tester) async {
    await pumpApp(tester, play: false);
    await toggle(tester);
    expect(panel, findsOneWidget);
    expect(find.byType(LyricsView), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(Text)),
      findsNothing,
    );
    expect(service.lookups, isEmpty);

    await toggle(tester);
    expect(panel, findsNothing);
    await toggle(tester);
    expect(panel, findsOneWidget);
  });

  uiTest('opens and closes over Motion.standard', (tester) async {
    await pumpApp(tester);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getSize(find.byType(LyricsPanel)).width;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(320 + 8));
    await settle(tester);
    expect(tester.getSize(find.byType(LyricsPanel)).width, 320 + 8);
  });

  uiTest('opens at once under reduced motion', (tester) async {
    await pumpApp(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(tester.getSize(find.byType(LyricsPanel)).width, 320 + 8);
  });

  group('narrow windows', () {
    final sidebar = find.byKey(const Key('sidebar'));
    final shell = find.byType(StatefulNavigationShell);

    for (final (width, overlay) in [(720.0, true), (800.0, false)]) {
      uiTest('${width.toInt()}x800 on Home: the sidebar collapses while '
          'open, nothing overflows', (tester) async {
        await pumpApp(tester, size: Size(width, 800));
        expect(router.state.uri.path, '/home');
        expect(tester.getSize(sidebar).width, Sidebar.expandedWidth);

        await toggle(tester);
        expect(tester.takeException(), isNull);
        expect(panel, findsOneWidget);
        expect(tester.getSize(panel).width, 320);
        expect(tester.getTopRight(panel).dx, width - 8);
        expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
        final paneRight = tester.getTopRight(shell).dx;
        if (overlay) {
          // Over the right of the content, which keeps its width.
          expect(paneRight, width - 8);
          expect(tester.getTopLeft(panel).dx, lessThan(paneRight));
        } else {
          expect(tester.getTopLeft(panel).dx, greaterThan(paneRight));
          expect(tester.getSize(shell).width, greaterThanOrEqualTo(360));
        }
        // The collapse button can't undo what the panel needs.
        final toggleButton = tester.widget<IconButton>(
          find.byKey(const Key('sidebar.toggle')),
        );
        expect(toggleButton.onPressed, isNull);

        // Closing gives the user's own (expanded) sidebar back.
        await toggle(tester);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(sidebar).width, Sidebar.expandedWidth);
      });
    }

    uiTest('a sidebar the user collapsed stays collapsed after the panel '
        'closes', (tester) async {
      await pumpApp(tester, size: const Size(800, 800));
      await tester.tap(find.byKey(const Key('sidebar.toggle')));
      await settle(tester);
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
      await toggle(tester);
      await toggle(tester);
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
    });

    uiTest('widening the window past 1000 px gives the sidebar back while '
        'the panel stays open', (tester) async {
      await pumpApp(tester, size: const Size(800, 800));
      await toggle(tester);
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
      tester.view.physicalSize = const Size(1280, 800);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(panel, findsOneWidget);
      expect(tester.getSize(sidebar).width, Sidebar.expandedWidth);
    });
  });
}
