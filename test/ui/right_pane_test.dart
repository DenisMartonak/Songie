import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/lyrics/lyrics_view.dart';
import 'package:songies/ui/now_playing/now_playing_queue.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/shell/right_pane.dart';
import 'package:songies/ui/shell/right_pane_friends.dart';
import 'package:songies/ui/shell/right_pane_state.dart';
import 'package:songies/ui/shell/sidebar.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/room_rig.dart';
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

  Widget app({List<Override> extra = const []}) => ProviderScope(
    overrides: [
      ...h.overrides,
      ...extra,
      lyricsServiceProvider.overrideWithValue(service),
      hasCustomTitleBarProvider.overrideWithValue(false),
    ],
    child: MaterialApp.router(
      theme: buildThemeData(ThemeSpec.builtInDefault),
      routerConfig: router,
    ),
  );

  /// Sets the window to [size] and adds the seeded songs.
  Future<void> setUpWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one', artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
    });
    router = buildRouter();
  }

  /// The whole app on a desktop window ([size], 1280x800 by default); with
  /// [play], the seeded songs are queued and the first one plays.
  Future<void> pumpApp(
    WidgetTester tester, {
    bool play = true,
    Size size = const Size(1280, 800),
    List<Override> extra = const [],
  }) async {
    await setUpWindow(tester, size);
    await tester.pumpWidget(app(extra: extra));
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

  final lyricsButton = find.byKey(const Key('playerBar.lyrics'));
  final queueButton = find.byKey(const Key('playerBar.queue'));
  final close = find.byKey(const Key('rightPane.close'));
  final pane = find.byKey(const Key('rightPane'));
  final title = find.byKey(const Key('rightPane.title'));

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
  }

  String titleText(WidgetTester tester) => tester.widget<Text>(title).data!;

  SongiesColors colorsOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(PlayerBar)))
          .extension<SongiesColors>()!;

  Icon iconOf(WidgetTester tester, Finder button) => tester.widget<Icon>(
    find.descendant(of: button, matching: find.byType(Icon)),
  );

  uiTest('open by default on Friends, 320 px, right of the main pane', (
    tester,
  ) async {
    await pumpApp(tester);
    final shell = find.byType(StatefulNavigationShell);
    expect(pane, findsOneWidget);
    expect(tester.getSize(pane).width, 320);
    expect(tester.getTopRight(pane).dx, 1280 - 8);
    expect(
      tester.getTopLeft(pane).dx,
      greaterThan(tester.getTopRight(shell).dx),
    );
    expect(titleText(tester), 'Friends');
    expect(
      find.descendant(of: pane, matching: find.byType(RightPaneFriends)),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(close).tooltip, 'Close');
    // Same surface as the main pane: the background colour, rounded.
    final surface = tester.widget<ColoredBox>(
      find.descendant(of: pane, matching: find.byType(ColoredBox)).first,
    );
    expect(surface.color, colorsOf(tester).background);
  });

  uiTest('the Lyrics button sits before Queue', (tester) async {
    await pumpApp(tester);
    expect(
      tester.getCenter(lyricsButton).dx,
      lessThan(tester.getCenter(queueButton).dx),
    );
    expect(tester.widget<IconButton>(lyricsButton).tooltip, 'Lyrics');
  });

  uiTest('Lyrics shows lyrics in the pane; Lyrics again goes back to Friends', (
    tester,
  ) async {
    await pumpApp(tester);
    final colors = colorsOf(tester);
    expect(iconOf(tester, lyricsButton).icon, Icons.lyrics_outlined);

    await tap(tester, lyricsButton);
    expect(titleText(tester), 'Lyrics');
    final view = tester.widget<LyricsView>(
      find.descendant(of: pane, matching: find.byType(LyricsView)),
    );
    expect(view.density, LyricsDensity.compact);
    expect(find.textContaining('First invented line'), findsOneWidget);
    expect(find.byType(RightPaneFriends), findsNothing);
    expect(iconOf(tester, lyricsButton).icon, Icons.lyrics);
    expect(tester.widget<IconButton>(lyricsButton).color, colors.accent);

    await tap(tester, lyricsButton);
    expect(pane, findsOneWidget);
    expect(titleText(tester), 'Friends');
    expect(find.byType(LyricsView), findsNothing);
    expect(iconOf(tester, lyricsButton).icon, Icons.lyrics_outlined);
    expect(tester.widget<IconButton>(lyricsButton).color, colors.mutedText);
  });

  uiTest('Queue shows the queue in the pane, and does not open Now Playing', (
    tester,
  ) async {
    await pumpApp(tester);
    final colors = colorsOf(tester);
    final path = router.state.uri.path;
    expect(tester.widget<IconButton>(queueButton).color, colors.mutedText);

    await tap(tester, queueButton);
    expect(router.state.uri.path, path);
    expect(titleText(tester), 'Queue');
    expect(
      find.descendant(of: pane, matching: find.byType(NowPlayingQueue)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pane, matching: find.text('Song two')),
      findsOneWidget,
    );
    expect(iconOf(tester, queueButton).icon, Icons.queue_music_rounded);
    expect(tester.widget<IconButton>(queueButton).color, colors.accent);
    expect(tester.widget<IconButton>(queueButton).isSelected, isTrue);

    // Lyrics from the queue switches straight to lyrics.
    await tap(tester, lyricsButton);
    expect(titleText(tester), 'Lyrics');
    expect(tester.widget<IconButton>(queueButton).color, colors.mutedText);

    await tap(tester, queueButton);
    await tap(tester, queueButton);
    expect(titleText(tester), 'Friends');
    expect(find.byType(NowPlayingQueue), findsNothing);
  });

  uiTest('the X closes the pane, whatever it shows; reopening keeps working', (
    tester,
  ) async {
    await pumpApp(tester);
    final shell = find.byType(StatefulNavigationShell);
    final openRight = tester.getTopRight(shell).dx;

    await tap(tester, close);
    expect(pane, findsNothing);
    // The strip stays, 40 px and its gap, beside the page and its own gap.
    expect(tester.getTopRight(shell).dx, 1280 - 48 - 8);
    expect(tester.getTopRight(shell).dx, greaterThan(openRight));

    await tap(tester, lyricsButton);
    expect(titleText(tester), 'Lyrics');
    await tap(tester, close);
    expect(pane, findsNothing);
    expect(find.byType(LyricsView), findsNothing);
    expect(iconOf(tester, lyricsButton).icon, Icons.lyrics_outlined);

    await tap(tester, queueButton);
    expect(titleText(tester), 'Queue');
    await tap(tester, close);
    expect(pane, findsNothing);
    expect(find.byType(NowPlayingQueue), findsNothing);

    await tap(tester, lyricsButton);
    expect(pane, findsOneWidget);
    expect(titleText(tester), 'Lyrics');
    expect(tester.getTopRight(shell).dx, openRight);
  });

  uiTest('no lyrics lookups while the pane shows Friends or is closed', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(pane, findsOneWidget);
    expect(find.byType(LyricsView), findsNothing);
    expect(service.lookups, isEmpty);

    await tap(tester, close);
    await real(tester, () => h.player.next());
    await settle(tester);
    expect(service.lookups, isEmpty);

    await tap(tester, queueButton);
    expect(service.lookups, isEmpty);

    await tap(tester, lyricsButton);
    expect(service.lookups.map((l) => l.id), ['t2']);
  });

  uiTest('with no song, Lyrics shows an empty pane', (tester) async {
    await pumpApp(tester, play: false);
    await tap(tester, lyricsButton);
    expect(find.byType(LyricsView), findsOneWidget);
    expect(
      find.descendant(of: find.byType(LyricsView), matching: find.byType(Text)),
      findsNothing,
    );
    expect(service.lookups, isEmpty);
  });

  uiTest('a stored closed pane never shows at startup', (tester) async {
    await setUpWindow(tester, const Size(1280, 800));
    await real(
      tester,
      () => SettingsRepository(h.db).setBool(kRightPaneOpen, false),
    );
    await tester.pumpWidget(app());
    for (var t = 0; t < 500; t += 16) {
      expect(pane, findsNothing, reason: 'at $t ms');
      // Lets the stored setting load on the real clock.
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pane, findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RightPane)),
    );
    expect(container.read(rightPaneOpenProvider), isFalse);
  });

  uiTest('a stored open pane appears at full width, without sliding in', (
    tester,
  ) async {
    await setUpWindow(tester, const Size(1280, 800));
    await tester.pumpWidget(app());
    var seen = false;
    for (var t = 0; t < 500; t += 16) {
      if (pane.evaluate().isNotEmpty) {
        seen = true;
        expect(tester.getSize(find.byType(RightPane)).width, 320 + 8);
      } else {
        expect(
          find.descendant(
            of: find.byType(RightPane),
            matching: find.byType(AnimatedSize),
          ),
          findsNothing,
          reason: 'at $t ms',
        );
      }
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(seen, isTrue);
  });

  uiTest('Space toggles play after clicking the X and the Lyrics button', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(h.player.state.playing, isTrue);

    await tap(tester, close);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(h.player.state.playing, isFalse);

    await tap(tester, lyricsButton);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(h.player.state.playing, isTrue);
    expect(pane, findsOneWidget);
  });

  uiTest('stays open across tabs', (tester) async {
    await pumpApp(tester);
    await tap(tester, lyricsButton);
    router.go('/library');
    await settle(tester);
    expect(router.state.uri.path, '/library');
    expect(pane, findsOneWidget);
    expect(find.textContaining('First invented line'), findsOneWidget);
    router.go('/home');
    await settle(tester);
    expect(pane, findsOneWidget);
    expect(titleText(tester), 'Lyrics');
  });

  uiTest('opens and closes over Motion.standard', (tester) async {
    await pumpApp(tester);
    await tester.tap(close);
    await tester.pump();
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final closing = tester.getSize(find.byType(RightPane)).width;
    expect(closing, greaterThan(0));
    expect(closing, lessThan(320 + 8));
    expect(closing, greaterThan(40 + 8));
    await settle(tester);
    expect(tester.getSize(find.byType(RightPane)).width, 40 + 8);

    await tester.tap(lyricsButton);
    await tester.pump();
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getSize(find.byType(RightPane)).width;
    expect(opening, greaterThan(40 + 8));
    expect(opening, lessThan(320 + 8));
    await settle(tester);
    expect(tester.getSize(find.byType(RightPane)).width, 320 + 8);
  });

  uiTest('opens at once under reduced motion', (tester) async {
    await pumpApp(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(close);
    await tester.pump();
    await flush(tester);
    expect(tester.getSize(find.byType(RightPane)).width, 40 + 8);
    await tester.tap(lyricsButton);
    await tester.pump();
    await flush(tester);
    expect(tester.getSize(find.byType(RightPane)).width, 320 + 8);
  });

  group('narrow windows', () {
    final sidebar = find.byKey(const Key('sidebar'));
    final shell = find.byType(StatefulNavigationShell);

    for (final (width, overlay) in [(720.0, true), (800.0, false)]) {
      uiTest('${width.toInt()}x800 on Home: the sidebar collapses while '
          'open, nothing overflows', (tester) async {
        await pumpApp(tester, size: Size(width, 800));
        expect(router.state.uri.path, '/home');
        expect(tester.takeException(), isNull);
        expect(pane, findsOneWidget);
        expect(tester.getSize(pane).width, 320);
        expect(tester.getTopRight(pane).dx, width - 8);
        expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
        final paneRight = tester.getTopRight(shell).dx;
        if (overlay) {
          // Over the right of the content, which keeps its width.
          expect(paneRight, width - 8);
          expect(tester.getTopLeft(pane).dx, lessThan(paneRight));
        } else {
          expect(tester.getTopLeft(pane).dx, greaterThan(paneRight));
          expect(tester.getSize(shell).width, greaterThanOrEqualTo(360));
        }
        // The collapse button can't undo what the pane needs.
        final toggleButton = tester.widget<IconButton>(
          find.byKey(const Key('sidebar.toggle')),
        );
        expect(toggleButton.onPressed, isNull);

        // Closing gives the user's own (expanded) sidebar back.
        await tap(tester, close);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(sidebar).width, Sidebar.expandedWidth);
      });
    }

    uiTest('a sidebar the user collapsed stays collapsed after the pane '
        'closes', (tester) async {
      await pumpApp(tester, size: const Size(800, 800));
      await tap(tester, close);
      await tap(tester, find.byKey(const Key('sidebar.toggle')));
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
      await tap(tester, lyricsButton);
      await tap(tester, close);
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
    });

    uiTest('widening the window past 1000 px gives the sidebar back while '
        'the pane stays open', (tester) async {
      await pumpApp(tester, size: const Size(800, 800));
      expect(tester.getSize(sidebar).width, Sidebar.collapsedWidth);
      tester.view.physicalSize = const Size(1280, 800);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(pane, findsOneWidget);
      expect(tester.getSize(sidebar).width, Sidebar.expandedWidth);
    });
  });

  group('signed in', () {
    late RoomRig rig;

    setUp(() {
      rig = RoomRig(h);
      h.friendsBackend
        ..addUser('u1', 'me')
        ..me = 'u1';
      h.activityBackend.me = 'u1';
    });

    final field = find.byKey(const Key('room.joinField'));

    uiTest('the room code field in the pane takes typing, and Join joins', (
      tester,
    ) async {
      await pumpApp(tester, extra: rig.overrides);
      await rig.hostRoom(tester);
      expect(find.descendant(of: pane, matching: field), findsOneWidget);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'ABCD-2345');
      await tester.pump();
      expect(find.text('ABCD-2345'), findsOneWidget);
      await tester.tap(find.text('Join a room'));
      await rig.run(tester, Future.value());
      expect(find.text('Not a room code or link'), findsNothing);
      expect(rig.backend.calls, contains('join ABCD2345'));
      await rig.dispose(tester);
    });

    uiTest('Space still toggles play after clicking Start a room', (
      tester,
    ) async {
      await pumpApp(tester, extra: rig.overrides);
      expect(h.player.state.playing, isTrue);
      await tester.tap(find.text('Start a room'));
      await rig.run(tester, Future.value());
      expect(rig.service!.status, isA<RoomHosting>());
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      await rig.dispose(tester);
    });

    uiTest('Space typed in the room code field types, not toggles play', (
      tester,
    ) async {
      await pumpApp(tester, extra: rig.overrides);
      expect(h.player.state.playing, isTrue);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'AB');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(h.player.state.playing, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await rig.dispose(tester);
    });

    uiTest('holds a close watch only while the pane shows Friends', (
      tester,
    ) async {
      await pumpApp(tester, extra: rig.overrides);
      final friends = containerOf(tester).read(friendsServiceProvider);
      expect(friends.closeWatches, 1);
      await tap(tester, lyricsButton);
      expect(friends.closeWatches, 0);
      await tap(tester, lyricsButton);
      expect(friends.closeWatches, 1);
      await tap(tester, queueButton);
      expect(friends.closeWatches, 0);
      await tap(tester, queueButton);
      expect(friends.closeWatches, 1);
      await tap(tester, close);
      expect(friends.closeWatches, 0);
      await tap(tester, lyricsButton);
      await tap(tester, lyricsButton);
      expect(friends.closeWatches, 1);
      await rig.dispose(tester);
    });

    uiTest('showing Friends after Lyrics loads the friends again', (
      tester,
    ) async {
      await pumpApp(tester, extra: rig.overrides);
      await tap(tester, lyricsButton);
      final before = h.friendsBackend.calls.where((c) => c == 'load').length;
      await tap(tester, lyricsButton);
      expect(
        h.friendsBackend.calls.where((c) => c == 'load').length,
        greaterThan(before),
      );
      await rig.dispose(tester);
    });
  });
}
