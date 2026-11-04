import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/downloads/downloads_banner.dart';
import 'package:songies/ui/island/island_host.dart';
import 'package:songies/ui/now_playing/now_playing_controls.dart';
import 'package:songies/ui/shell/bottom_nav.dart';
import 'package:songies/ui/shell/player_bar.dart';

import '../../helpers/fake_lyrics_service.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async {
    h = await UiHarness.create();
  });
  tearDown(() => h.dispose());

  Future<Track> seed(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1', title: 'Song one');
    return (h.db.select(h.db.tracks)).get().then((l) => l.first);
  });

  /// The real app's router in a [width] x 800 window.
  Future<GoRouter> open(
    WidgetTester tester, {
    required double width,
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          lyricsServiceProvider.overrideWithValue(FakeLyricsService()),
          hasCustomTitleBarProvider.overrideWithValue(false),
          ...extra,
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: router,
          builder: (context, child) => IslandHost(child: child!),
        ),
      ),
    );
    await settle(tester);
    return router;
  }

  void showIsland(WidgetTester tester) {
    Islands.of(tester.element(find.byType(Scaffold).first)).show('Hi');
  }

  uiTest('desktop: the island sits just above the player bar', (tester) async {
    final track = await seed(tester);
    await open(tester, width: 1280);
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final bottom = tester.getRect(find.byKey(const Key('island'))).bottom;
    expect(bottom, closeTo(tester.getRect(find.byType(PlayerBar)).top - 10, 1));
  });

  uiTest('phone: the island sits above the whole bottom stack', (tester) async {
    final track = await seed(tester);
    await open(
      tester,
      width: 400,
      extra: [downloadsBannerVisibleProvider.overrideWithValue(true)],
    );
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    expect(find.byType(DownloadsBanner), findsOneWidget);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final bottom = tester.getRect(find.byKey(const Key('island'))).bottom;
    expect(
      bottom,
      closeTo(tester.getRect(find.byType(DownloadsBanner)).top - 10, 1),
    );
  });

  uiTest('phone with nothing playing: above the bottom nav', (tester) async {
    await open(tester, width: 400);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final bottom = tester.getRect(find.byKey(const Key('island'))).bottom;
    expect(bottom, closeTo(tester.getRect(find.byType(BottomNav)).top - 10, 1));
  });

  uiTest('full-screen player open: the island rises from the controls', (
    tester,
  ) async {
    final track = await seed(tester);
    final router = await open(tester, width: 1280);
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    openNowPlaying(router);
    await settle(tester);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rect = tester.getRect(find.byKey(const Key('island')));
    // The block starts at the scrubber's slot, which is drawn 10 px higher.
    final scrubber = tester.getRect(find.byType(NowPlayingScrubber));
    expect(rect.bottom, closeTo(scrubber.top, 1));
    for (final f in [
      find.byType(NowPlayingControls),
      find.byType(NowPlayingScrubber),
    ]) {
      expect(rect.overlaps(tester.getRect(f)), isFalse);
    }
  });

  uiTest('after the full-screen player closes, the player bar is used again', (
    tester,
  ) async {
    final track = await seed(tester);
    final router = await open(tester, width: 1280);
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    openNowPlaying(router);
    await settle(tester);
    router.pop();
    await settle(tester);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final bottom = tester.getRect(find.byKey(const Key('island'))).bottom;
    expect(bottom, closeTo(tester.getRect(find.byType(PlayerBar)).top - 10, 1));
  });

  uiTest('while the full-screen player closes, the island never covers the '
      'player bar', (tester) async {
    final track = await seed(tester);
    final router = await open(tester, width: 1280);
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    openNowPlaying(router);
    await settle(tester);
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    router.pop();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final island = find.byKey(const Key('island'));
      final bar = find.byType(PlayerBar);
      if (island.evaluate().isEmpty || bar.evaluate().isEmpty) continue;
      expect(
        tester.getRect(island).bottom,
        lessThanOrEqualTo(tester.getRect(bar).top),
        reason: 'frame $i',
      );
    }
    await settle(tester);
  });

  uiTest('phone with the keyboard open: above the keyboard', (tester) async {
    await open(tester, width: 400);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    showIsland(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final bottom = tester.getRect(find.byKey(const Key('island'))).bottom;
    expect(bottom, closeTo(800 - 300 - 16, 1));
  });
}
