import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/motion/equalizer_bars.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/shell/mini_player.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/widgets/artwork.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

const _long =
    'A very long song title that will never ever fit on a single line';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// Starts at a stub page and pushes Now Playing over it.
  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    ThemeSpec theme = ThemeSpec.builtInDefault,
    bool disableAnimations = false,
    String firstTitle = 'Song one',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: firstTitle, artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
      await h.addTrack('t3', title: 'Song three');
    });
    await tester.pumpWidget(
      h.app(
        theme: theme,
        disableAnimations: disableAnimations,
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

  /// Queues the three seeded songs; the first one is playing. With
  /// [settleAfter] false it only flushes (a looping animation may run).
  Future<void> playThree(WidgetTester tester, {bool settleAfter = true}) async {
    final tracks = await real(
      tester,
      () => (h.db.select(
        h.db.tracks,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    );
    await real(tester, () => h.player.playQueue(tracks));
    if (settleAfter) {
      await settle(tester);
    } else {
      await flush(tester);
    }
  }

  Finder art() => find.byKey(const Key('nowPlaying.art'));
  Finder page() => find.byKey(const Key('nowPlaying.page'));

  /// The slide around the title block showing [title].
  SlideTransition titleSlide(WidgetTester tester, String title) =>
      tester.widget<SlideTransition>(
        find.ancestor(
          of: find.text(title),
          matching: find.byKey(const Key('nowPlaying.titleSlide')),
        ),
      );

  group('artwork', () {
    uiTest('is full size while playing and 0.88 when paused', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final playing = tester.getRect(art()).width;

      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      expect(tester.getRect(art()).width / playing, closeTo(0.88, 0.001));

      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await settle(tester);
      expect(tester.getRect(art()).width, closeTo(playing, 0.001));
    });

    uiTest('crossfades and grows from 0.92 on a track change', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await flush(tester);
      await tester.pump(Motion.emphasized ~/ 2);
      // Old and new covers are both on screen mid-change.
      expect(art(), findsNWidgets(2));
      final scale = tester.widget<ScaleTransition>(
        find
            .ancestor(
              of: art().last,
              matching: find.byKey(const Key('nowPlaying.artChange')),
            )
            .first,
      );
      expect(scale.scale.value, inExclusiveRange(0.92, 1));
      await settle(tester);
      expect(art(), findsOneWidget);
    });

    uiTest('is the hero np-art', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final hero = tester.widget<Hero>(
        find.ancestor(of: art(), matching: find.byType(Hero)),
      );
      expect(hero.tag, 'np-art');
    });
  });

  group('title on a track change', () {
    uiTest('next slides it to the left', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await flush(tester);
      await tester.pump(Motion.emphasized ~/ 3);
      // The old title leaves to the left, the new one comes in from the right.
      expect(titleSlide(tester, 'Song one').position.value.dx, lessThan(0));
      expect(titleSlide(tester, 'Song two').position.value.dx, greaterThan(0));
      await settle(tester);
      expect(find.text('Song one'), findsNothing);
      expect(titleSlide(tester, 'Song two').position.value, Offset.zero);
    });

    uiTest('the slide is 16 px', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final rest = tester.getTopLeft(find.text('Song one')).dx;
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await flush(tester);
      // The incoming title starts 16 px to the right.
      expect(
        tester.getTopLeft(find.text('Song two')).dx,
        closeTo(rest + 16, 1),
      );
      await settle(tester);
    });

    uiTest('previous slides it to the right', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.previous')));
      await flush(tester);
      await tester.pump(Motion.emphasized ~/ 3);
      expect(titleSlide(tester, 'Song two').position.value.dx, greaterThan(0));
      expect(titleSlide(tester, 'Song one').position.value.dx, lessThan(0));
      await settle(tester);
    });
  });

  group('title in a two-song queue', () {
    uiTest('previous slides it to the right', (tester) async {
      await pumpApp(tester);
      final two = await real(
        tester,
        () => (h.db.select(
          h.db.tracks,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
      );
      await real(tester, () => h.player.playQueue(two.take(2).toList()));
      await settle(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await settle(tester);
      expect(h.player.state.index, 1);
      await tester.tap(find.byKey(const Key('nowPlaying.previous')));
      await flush(tester);
      await tester.pump(Motion.emphasized ~/ 3);
      expect(h.player.state.index, 0);
      expect(titleSlide(tester, 'Song one').position.value.dx, lessThan(0));
      expect(titleSlide(tester, 'Song two').position.value.dx, greaterThan(0));
      await settle(tester);
    });
  });

  group('play button', () {
    uiTest('is an animated play/pause icon on an accent circle', (
      tester,
    ) async {
      await pumpApp(tester);
      await playThree(tester);
      final button = find.byKey(const Key('nowPlaying.playPause'));
      final icon = tester.widget<AnimatedIcon>(
        find.descendant(of: button, matching: find.byType(AnimatedIcon)),
      );
      expect(icon.icon, AnimatedIcons.play_pause);
      // Playing shows the pause glyph (the end of play_pause).
      expect(icon.progress.value, 1);
      final accent = Theme.of(tester.element(button))
          .extension<SongiesColors>()!
          .accent;
      final fill = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(fill.color, accent);

      await tester.tap(button);
      await settle(tester);
      expect(icon.progress.value, 0);
    });

    uiTest('pulses once to 1.06 when pressed', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final button = find.byKey(const Key('nowPlaying.playPause'));
      final pulse = tester.widget<ScaleTransition>(
        find.descendant(of: button, matching: find.byType(ScaleTransition)),
      );
      expect(pulse.scale.value, 1);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(Motion.standard ~/ 2);
      expect(pulse.scale.value, closeTo(1.06, 0.01));
      await settle(tester);
      expect(pulse.scale.value, 1);
    });
  });

  group('swipe down to collapse', () {
    uiTest('a drag past 30 % of the height closes it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      // Slowly (240 px/s), so only the distance counts.
      await tester.timedDrag(
        art(),
        const Offset(0, 240),
        const Duration(seconds: 1),
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
      expect(find.text('Shell stub'), findsOneWidget);
    });

    uiTest('a drag of 10 % moves the page, then springs back', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final gesture = await tester.startGesture(tester.getCenter(art()));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The page follows the finger (less the touch slop), uncovering the
      // app underneath.
      expect(tester.getTopLeft(page()).dy, greaterThan(70));
      expect(find.text('Shell stub'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      await tester.pump(Motion.standard ~/ 2);
      expect(tester.getTopLeft(page()).dy, inExclusiveRange(0, 80));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(tester.getTopLeft(page()).dy, 0);
      // At rest the page is opaque again: the app below is not painted.
      expect(find.text('Shell stub'), findsNothing);
    });

    uiTest('mid-drag past the threshold, the app shows underneath', (
      tester,
    ) async {
      await pumpApp(tester);
      await playThree(tester);
      final gesture = await tester.startGesture(tester.getCenter(art()));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Shell stub'), findsOneWidget);
      expect(tester.getTopLeft(page()).dy, greaterThan(200));
      await gesture.up();
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('when there is nothing to pop, a long drag springs back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await real(tester, () => h.addTrack('t1'));
      await tester.pumpWidget(
        h.app(
          initialLocation: '/now-playing',
          routes: [GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage)],
        ),
      );
      await settle(tester);
      await playThree(tester);
      await tester.timedDrag(
        art(),
        const Offset(0, 300),
        const Duration(seconds: 1),
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(tester.getTopLeft(page()).dy, 0);
      // And it still answers a drag.
      await tester.drag(art(), const Offset(0, 60));
      await settle(tester);
      expect(tester.getTopLeft(page()).dy, 0);
    });

    /// The app answers input again and nothing is stuck mid-gesture: Now
    /// Playing opens and its close button closes it.
    Future<void> expectUsable(WidgetTester tester, GoRouter router) async {
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      expect(navigator.userGestureInProgress, isFalse);
      if (find.byType(NowPlayingPage).evaluate().isEmpty) {
        router.push('/now-playing');
        await settle(tester);
      }
      expect(find.byType(NowPlayingPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('nowPlaying.close')));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
      expect(find.text('Shell stub'), findsOneWidget);
    }

    uiTest('crossing the phone breakpoint mid-drag leaves nothing stuck', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      await playThree(tester);
      final gesture = await tester.startGesture(tester.getCenter(art()));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The window widens to desktop while the finger is down.
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectUsable(tester, router);
    });

    uiTest('system back mid-drag closes it and leaves nothing stuck', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      await playThree(tester);
      final gesture = await tester.startGesture(tester.getCenter(art()));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.binding.handlePopRoute();
      await tester.pump();
      // The finger keeps moving, then lifts, while the page leaves.
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(NowPlayingPage), findsNothing);
      await expectUsable(tester, router);
    });

    uiTest('a fast fling closes it', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.fling(art(), const Offset(0, 120), 1000);
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('on desktop, dragging the panel down closes it', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      final height = tester.getSize(find.byKey(const Key('nowPlaying.panel')));
      await tester.timedDrag(
        art(),
        Offset(0, height.height * 0.3),
        const Duration(seconds: 1),
      );
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('on desktop, a mouse drag over the queue does not move the panel', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final top = tester.getTopLeft(page()).dy;

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Song two')),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.getTopLeft(page()).dy, top);
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NowPlayingPage), findsOneWidget);
    });

    uiTest('on desktop, a mouse drag on the header closes it', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('NOW PLAYING')),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    uiTest('on desktop, a short drag springs back', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await playThree(tester);
      final top = tester.getTopLeft(page()).dy;
      await tester.drag(art(), const Offset(0, 60));
      await settle(tester);
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(tester.getTopLeft(page()).dy, top);
    });
  });

  group('background', () {
    uiTest('blur on: the cover blurred at σ 40 in its own layer', (
      tester,
    ) async {
      await pumpApp(tester);
      await playThree(tester);
      final blur = find.byType(ImageFiltered);
      expect(blur, findsOneWidget);
      expect(
        tester.widget<ImageFiltered>(blur).imageFilter,
        ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.clamp),
      );
      expect(
        find.ancestor(of: blur, matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      // Under the theme's gradient.
      expect(find.byKey(const Key('nowPlaying.glow')), findsOneWidget);

      // Not rebuilt (so not re-blurred) by a position tick or a pause.
      final before = tester.widget(blur);
      h.backend.setPosition(const Duration(seconds: 5));
      await flush(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await settle(tester);
      expect(tester.widget(blur), same(before));
    });

    test('over a white cover the header text still reaches AA', () {
      for (final spec in [
        ThemeSpec.builtInDefault,
        ThemeSpec.albumGlow,
        ThemeSpec.terminal,
        ThemeSpec.builtInDefault.copyWith(
          background: const Color(0xFFF4F4F4),
          surface: const Color(0xFFFFFFFF),
          text: const Color(0xFF111111),
        ),
      ]) {
        final c = SongiesColors.fromSpec(spec);
        final worst = blurWorstCaseTop(c);
        // The header's label is the text at 70 %.
        final label = Color.alphaBlend(c.text.withAlpha(179), worst);
        expect(contrastRatio(label, worst), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.text, worst), greaterThanOrEqualTo(4.5));
      }
    });

    uiTest('blur on: a readability scrim lies over the cover', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      final scrim = tester.widget<ColoredBox>(
        find.byKey(const Key('nowPlaying.scrim')),
      );
      final colors = Theme.of(tester.element(find.byType(NowPlayingPage)))
          .extension<SongiesColors>()!;
      expect(scrim.color, blurScrim(colors));
      expect(scrim.color.a, greaterThan(0));
    });

    uiTest('blur off: only the gradient, no filter', (tester) async {
      await pumpApp(
        tester,
        theme: ThemeSpec.builtInDefault.copyWith(blurNowPlaying: false),
      );
      await playThree(tester);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('nowPlaying.glow')), findsOneWidget);
    });
  });

  group('scrubber', () {
    double thumbRadius(WidgetTester tester) {
      final theme = SliderTheme.of(
        tester.element(find.byKey(const Key('nowPlaying.scrubber'))),
      );
      return theme.thumbShape!.getPreferredSize(true, false).width / 2;
    }

    uiTest('the thumb grows to 12 px only while dragging', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      expect(thumbRadius(tester), 0);
      final rect = tester.getRect(find.byKey(const Key('nowPlaying.scrubber')));
      final gesture = await tester.startGesture(
        Offset(rect.left + 2, rect.center.dy),
      );
      await gesture.moveTo(rect.center);
      await tester.pumpAndSettle();
      expect(thumbRadius(tester), 6);
      await gesture.up();
      await settle(tester);
      expect(thumbRadius(tester), 0);
    });

    uiTest('shows elapsed and remaining time', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      h.backend.setPosition(const Duration(seconds: 84));
      await settle(tester);
      expect(find.text('1:24'), findsOneWidget);
      expect(find.text('-1:56'), findsOneWidget);
    });

    uiTest('the buffered part is drawn at 30 % opacity', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      h.backend.setBuffered(const Duration(seconds: 100));
      await settle(tester);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('nowPlaying.scrubber')),
      );
      expect(slider.secondaryTrackValue, closeTo(0.5, 0.001));
      final theme = SliderTheme.of(
        tester.element(find.byKey(const Key('nowPlaying.scrubber'))),
      );
      final text = Theme.of(tester.element(find.byType(NowPlayingPage)))
          .extension<SongiesColors>()!
          .text;
      expect(theme.secondaryActiveTrackColor, text.withValues(alpha: 0.3));
    });
  });

  group('marquee', () {
    uiTest('a long title scrolls while playing, after 2 s', (tester) async {
      await pumpApp(tester, firstTitle: _long);
      await playThree(tester, settleAfter: false);
      final start = tester.getTopLeft(find.text(_long)).dx;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.getTopLeft(find.text(_long)).dx, start);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getTopLeft(find.text(_long)).dx, lessThan(start));
    });

    uiTest('paused, a long title stays still', (tester) async {
      await pumpApp(tester, firstTitle: _long);
      await playThree(tester, settleAfter: false);
      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await flush(tester);
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      final start = tester.getTopLeft(find.text(_long)).dx;
      await tester.pump(const Duration(seconds: 5));
      expect(tester.getTopLeft(find.text(_long)).dx, start);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('no idle animation', () {
    uiTest('paused and settled, no frame is scheduled', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });

    uiTest('playing a short title, settled, schedules nothing', (tester) async {
      await pumpApp(tester);
      await playThree(tester);
      expect(h.player.state.playing, isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    uiTest('the app going to the background while playing stops frames', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await pumpApp(tester, firstTitle: _long);
      await playThree(tester, settleAfter: false);
      // The marquee is running.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      // Back on screen, so the app can be torn down.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    uiTest('the queue bars stop when the app goes to the background', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await pumpApp(tester);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      // Past the tab's ink ripple, a one-shot.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EqualizerBars), findsOneWidget);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      // Back on screen, so the app can be torn down.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });
  });

  group('reduced motion', () {
    uiTest('track changes and play/pause are instant', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      await playThree(tester);
      final playing = tester.getRect(art()).width;

      // (The buttons' ink ripples still run: they are not Motion's.)
      await tester.tap(find.byKey(const Key('nowPlaying.next')));
      await flush(tester);
      expect(find.text('Song one'), findsNothing);
      expect(art(), findsOneWidget);
      expect(titleSlide(tester, 'Song two').position.value, Offset.zero);

      await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
      await flush(tester);
      expect(h.player.state.playing, isFalse);
      expect(tester.getRect(art()).width / playing, closeTo(0.88, 0.001));
    });

    uiTest('a long title does not scroll', (tester) async {
      await pumpApp(tester, disableAnimations: true, firstTitle: _long);
      await playThree(tester);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    uiTest('a short drag snaps back at once', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      await playThree(tester);
      await tester.drag(art(), const Offset(0, 80));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getTopLeft(page()).dy, 0);
    });
  });

  group('queue', () {
    uiTest('the playing row shows equalizer bars', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await settle(tester);
      final bars = tester.widget<EqualizerBars>(find.byType(EqualizerBars));
      expect(bars.playing, isTrue);
      // Only on the playing row.
      expect(
        find.ancestor(
          of: find.byType(EqualizerBars),
          matching: find.byKey(const Key('queue.row.0')),
        ),
        findsOneWidget,
      );
    });

    uiTest('a dragged row is lifted with a shadow', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      await playThree(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await settle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('queue.handle.1'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final lifted = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const Key('queue.row.1')),
              matching: find.byKey(const Key('queue.lifted')),
            )
            .first,
      );
      expect(lifted.elevation, greaterThan(0));
      await gesture.up();
      await settle(tester);
    });
  });

  group('hero', () {
    Future<void> pumpShellPart(WidgetTester tester, Widget part) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await real(tester, () => h.addTrack('t1'));
      await tester.pumpWidget(
        h.app(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(body: Center(child: part)),
            ),
            GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage),
          ],
        ),
      );
      await playThree(tester);
    }

    uiTest('the mini-player artwork is np-art', (tester) async {
      await pumpShellPart(
        tester,
        const SizedBox(width: 400, child: MiniPlayer()),
      );
      expect(tester.widget<Hero>(find.byType(Hero)).tag, 'np-art');
    });

    uiTest('the player bar artwork is np-art', (tester) async {
      await pumpShellPart(tester, const PlayerBar());
      expect(tester.widget<Hero>(find.byType(Hero)).tag, 'np-art');
    });

    uiTest('the player bar keeps its artwork with the panel open', (
      tester,
    ) async {
      await pumpShellPart(tester, const PlayerBar());
      GoRouter.of(tester.element(find.byType(PlayerBar))).push('/now-playing');
      await settle(tester);
      expect(find.byKey(const Key('nowPlaying.panel')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.byType(Artwork),
        ),
        findsOneWidget,
      );
    });
  });

  group('downloaded icon', () {
    uiTest('fades in', (tester) async {
      final yt = await real(tester, () async {
        await h.db
            .into(h.db.tracks)
            .insert(
              trackRow(id: 'y1', source: 'yt', ytVideoId: 'v1', title: 'Yt'),
            );
        await h.db
            .into(h.db.localFiles)
            .insert(
              LocalFilesCompanion.insert(
                trackId: 'y1',
                path: '/yt/v1.webm',
                state: 'done',
                bytes: 1,
                mtimeMs: 0,
              ),
            );
        return (h.db.select(
          h.db.tracks,
        )..where((t) => t.id.equals('y1'))).getSingle();
      });
      await pumpApp(tester, disableAnimations: false);
      await real(tester, () => h.player.playQueue([yt]));
      await flush(tester);
      final icon = find.byIcon(Icons.download_done);
      expect(icon, findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: icon,
              matching: find.byKey(const Key('nowPlaying.downloadedFade')),
            )
            .first,
      );
      expect(fade.opacity.value, lessThan(1));
      await settle(tester);
      expect(fade.opacity.value, 1);
    });
  });
}
