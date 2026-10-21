import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// Starts at a stub page and, if [open], pushes Now Playing over it.
  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    ThemeSpec theme = ThemeSpec.builtInDefault,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Seeded before anything is mounted: writes while the app is live would
    // wait on stream updates that the fake clock never runs.
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one', artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
      await h.addTrack('t3', title: 'Song three');
    });
    await tester.pumpWidget(
      h.app(
        theme: theme,
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Shell stub')),
          ),
          GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage),
        ],
      ),
    );
    final router = GoRouter.of(tester.element(find.text('Shell stub')));
    router.push('/now-playing');
    await settle(tester);
    return router;
  }

  /// Queues the three seeded songs; the first one is playing.
  Future<void> playThree(WidgetTester tester) async {
    final tracks = await real(
      tester,
      () => (h.db.select(
        h.db.tracks,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    );
    await real(tester, () => h.player.playQueue(tracks));
    await settle(tester);
  }

  SongiesColors colors(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(NowPlayingPage)))
          .extension<SongiesColors>()!;

  Icon icon(WidgetTester tester, IconData data) =>
      tester.widget<Icon>(find.byIcon(data));

  List<String> queueIds() => [for (final t in h.player.state.queue) t.id];

  group('content', () {
    uiTest('shows title, artist and the play/pause circle', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      expect(find.text('Song one'), findsWidgets);
      expect(find.text('Artist one'), findsOneWidget);

      final circle = find.byKey(const Key('nowPlaying.playPause'));
      expect(tester.getSize(circle), const Size(64, 64));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(circle);
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    uiTest('the art is at most 360 square', (tester) async {
      await pumpApp(tester, size: const Size(1000, 1200));
      await playThree(tester);
      final size = tester.getSize(find.byKey(const Key('nowPlaying.art')));
      expect(size.width, lessThanOrEqualTo(360));
      expect(size.width, size.height);
    });

    uiTest('next and previous move through the queue', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await settle(tester);
      expect(h.player.state.index, 1);
      await tester.tap(find.byKey(const Key('nowPlaying.previous')));
      await settle(tester);
      expect(h.player.state.index, 0);
    });

    uiTest('shows elapsed and total time', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      h.backend.setPosition(const Duration(seconds: 84));
      await settle(tester);
      expect(find.text('1:24'), findsOneWidget);
      expect(find.text('3:20'), findsOneWidget);
    });

    uiTest('says so when nothing is playing', (tester) async {
      await pumpApp(tester);
      expect(find.text('Nothing playing'), findsOneWidget);
    });
  });

  group('controls', () {
    uiTest('shuffle turns on and takes the accent colour', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final accent = colors(tester).accent;
      expect(icon(tester, Icons.shuffle_rounded).color, isNot(accent));

      await tester.tap(find.byKey(const Key('nowPlaying.shuffle')));
      await settle(tester);
      expect(h.player.state.shuffle, isTrue);
      expect(icon(tester, Icons.shuffle_rounded).color, accent);

      await tester.tap(find.byKey(const Key('nowPlaying.shuffle')));
      await settle(tester);
      expect(h.player.state.shuffle, isFalse);
      expect(icon(tester, Icons.shuffle_rounded).color, isNot(accent));
    });

    uiTest('repeat cycles off, all, one with matching icons', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final accent = colors(tester).accent;
      final repeat = find.byKey(const Key('nowPlaying.repeat'));

      expect(h.player.state.repeat, RepeatMode.off);
      expect(icon(tester, Icons.repeat_rounded).color, isNot(accent));

      await tester.tap(repeat);
      await settle(tester);
      expect(h.player.state.repeat, RepeatMode.all);
      expect(icon(tester, Icons.repeat_rounded).color, accent);

      await tester.tap(repeat);
      await settle(tester);
      expect(h.player.state.repeat, RepeatMode.one);
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
      expect(icon(tester, Icons.repeat_one_rounded).color, accent);

      await tester.tap(repeat);
      await settle(tester);
      expect(h.player.state.repeat, RepeatMode.off);
      expect(icon(tester, Icons.repeat_rounded).color, isNot(accent));
    });

    uiTest('the scrubber seeks to half the duration at 50 %', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      h.backend.clearCalls();

      await tester.tap(find.byKey(const Key('nowPlaying.scrubber')));
      await settle(tester);

      final seeks = [
        for (final c in h.backend.calls)
          if (c.startsWith('seek:')) int.parse(c.substring('seek:'.length)),
      ];
      expect(seeks, hasLength(1));
      expect(seeks.single, closeTo(100000, 1000));
    });

    uiTest('dragging the scrubber previews the time, then seeks', (
      tester,
    ) async {
      await pumpApp(tester);
      await playThree(tester);
      h.backend.clearCalls();

      final slider = find.byKey(const Key('nowPlaying.scrubber'));
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(rect.left + 1, rect.center.dy),
      );
      await gesture.moveTo(rect.center);
      await tester.pump();
      expect(find.text('1:40'), findsOneWidget);
      // Nothing is sent until the finger lifts.
      expect(h.backend.calls.where((c) => c.startsWith('seek:')), isEmpty);

      await gesture.up();
      await settle(tester);
      final seeks = [
        for (final c in h.backend.calls)
          if (c.startsWith('seek:')) int.parse(c.substring('seek:'.length)),
      ];
      expect(seeks.single, closeTo(100000, 3000));
    });
  });

  group('background', () {
    uiTest('is the blurred artwork when blurNowPlaying is on', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    uiTest('is a glow gradient, with no blur, when it is off', (tester) async {
      await pumpApp(
        tester,
        theme: ThemeSpec.builtInDefault.copyWith(blurNowPlaying: false),
      );
      await playThree(tester);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byKey(const Key('nowPlaying.glow')), findsOneWidget);
    });
  });

  group('queue', () {
    Future<void> openQueue(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await settle(tester);
    }

    uiTest('lists the queue in playing order', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await openQueue(tester);
      expect(find.text('Song one'), findsWidgets);
      expect(find.text('Song two'), findsOneWidget);
      expect(find.text('Song three'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Song two')).dy,
        lessThan(tester.getTopLeft(find.text('Song three')).dy),
      );
    });

    uiTest('tapping a row plays it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await openQueue(tester);
      await tester.tap(find.text('Song three'));
      await settle(tester);
      expect(h.player.state.index, 2);
    });

    uiTest('dragging a handle reorders through PlayerService.move', (
      tester,
    ) async {
      await pumpApp(tester);
      await playThree(tester);
      await openQueue(tester);
      expect(queueIds(), ['t1', 't2', 't3']);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('queue.handle.0'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await settle(tester);
      expect(queueIds(), ['t2', 't1', 't3']);
      // The playing track kept playing; its index followed it.
      expect(h.player.state.current?.id, 't1');
    });

    uiTest('swiping a row away removes it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await openQueue(tester);

      await tester.drag(find.text('Song two'), const Offset(-600, 0));
      await settle(tester);
      expect(queueIds(), ['t1', 't3']);
      expect(find.text('Song two'), findsNothing);
    });
  });

  group('closing', () {
    uiTest('on a phone it is a full-screen page', (tester) async {
      await pumpApp(tester);
      // The page below is covered and not painted.
      expect(find.text('Shell stub'), findsNothing);
      expect(find.byType(NowPlayingPage), findsOneWidget);
    });

    uiTest('on a phone, swiping down closes it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.fling(
        find.byKey(const Key('nowPlaying.art')),
        const Offset(0, 300),
        1500,
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
      expect(find.text('Shell stub'), findsOneWidget);
    });

    uiTest('on a phone, a short drag down does not close it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.drag(
        find.byKey(const Key('nowPlaying.art')),
        const Offset(0, 40),
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
    });

    uiTest('on a phone, the chevron closes it', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.close')));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('on desktop it is a panel over the still-visible shell', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(find.text('Shell stub'), findsOneWidget);
      final panel = tester.getSize(find.byKey(const Key('nowPlaying.panel')));
      expect(panel.width, lessThan(1280));
      expect(panel.height, lessThanOrEqualTo(800));
    });

    uiTest('on desktop, the X closes it', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await tester.tap(find.byKey(const Key('nowPlaying.close')));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
      expect(find.text('Shell stub'), findsOneWidget);
    });

    uiTest('on desktop, tapping outside the panel closes it', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('on desktop, swiping down does not close it', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      await tester.fling(
        find.byKey(const Key('nowPlaying.art')),
        const Offset(0, 300),
        1500,
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
    });
  });
}
