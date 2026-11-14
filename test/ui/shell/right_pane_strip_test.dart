import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/shell/right_pane_state.dart';
import 'package:songies/ui/shell/right_pane_strip.dart';
import 'package:songies/ui/shell/sidebar.dart';

import '../../helpers/fake_lyrics_service.dart';
import '../../helpers/room_rig.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;
  late GoRouter router;
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');

  setUp(() async {
    h = await UiHarness.create();
    rig = RoomRig(h);
    h.friendsBackend
      ..addUser('u1', 'me')
      ..me = 'u1';
    h.activityBackend
      ..friendsOf = ((id) => id == 'u1' ? {'f1', 'f2'} : {'u1'})
      ..me = 'u1';
  });
  tearDown(() => h.dispose());

  Future<void> befriend(List<String> ids) async {
    final f = h.friendsBackend;
    for (final id in ids) {
      f.addUser(id, 'user_$id');
      f.me = id;
      await f.send('u1');
      f.me = 'u1';
      await f.accept(id);
    }
  }

  /// The whole desktop app with the pane closed.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one');
      await h.addTrack('t2', title: 'Song two');
      await SettingsRepository(h.db).setBool(kRightPaneOpen, false);
    });
    router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          ...rig.overrides,
          lyricsServiceProvider.overrideWithValue(FakeLyricsService()),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
  }

  final strip = find.byKey(const Key('rightPane.strip'));
  final pane = find.byKey(const Key('rightPane'));
  Finder face(String id) => find.byKey(Key('rightPane.strip.$id'));

  Future<MouseCursor?> cursorOver(WidgetTester tester, Finder finder) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(finder));
    await tester.pump();
    return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
  }

  uiTest('closing shows the strip with each friend face, a dot for those '
      'listening', (tester) async {
    await befriend(['f1', 'f2']);
    h.activityBackend.me = 'f1';
    await h.activityBackend.publishNowPlaying(halo);
    h.activityBackend.me = 'u1';
    await pumpApp(tester);
    expect(pane, findsNothing);
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).width, RightPaneStrip.width);
    expect(tester.getTopRight(strip).dx, 1280 - 8);
    expect(face('f1'), findsOneWidget);
    expect(face('f2'), findsOneWidget);
    expect(
      find.descendant(
        of: face('f1'),
        matching: find.byKey(const Key('rightPane.strip.dot')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: face('f2'),
        matching: find.byKey(const Key('rightPane.strip.dot')),
      ),
      findsNothing,
    );
    expect(find.byTooltip('user_f1'), findsOneWidget);
    expect(find.byTooltip('Show friends'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('in a room the strip shows the count', (tester) async {
    await pumpApp(tester);
    expect(find.descendant(of: strip, matching: find.text('2')), findsNothing);
    await rig.hostRoom(tester);
    await rig.run(
      tester,
      rig.service!.join('ABCD2345', userId: 'u1', name: 'me'),
    );
    expect(
      find.descendant(of: strip, matching: find.text('2')),
      findsOneWidget,
    );
    await rig.dispose(tester);
  });

  uiTest('clicking the strip opens the pane on Friends, even after Lyrics '
      'was shown', (tester) async {
    await befriend(['f1']);
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Sidebar)),
    );
    await tester.runAsync(
      () => container.read(rightPaneProvider).toggle(RightPaneContent.lyrics),
    );
    await settle(tester);
    expect(find.text('Lyrics'), findsWidgets);
    await tester.runAsync(() => container.read(rightPaneProvider).close());
    await settle(tester);
    expect(strip, findsOneWidget);
    await tester.tap(strip);
    await settle(tester);
    expect(pane, findsOneWidget);
    expect(strip, findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('rightPane.title'))).data,
      'Friends',
    );
    await rig.dispose(tester);
  });

  uiTest('the strip shows the hand cursor', (tester) async {
    await pumpApp(tester);
    expect(await cursorOver(tester, strip), SystemMouseCursors.click);
    await rig.dispose(tester);
  });

  uiTest('a narrow window keeps the strip beside the page and the sidebar '
      'expanded', (tester) async {
    await pumpApp(tester, size: const Size(900, 800));
    expect(tester.takeException(), isNull);
    expect(strip, findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('sidebar'))).width,
      Sidebar.expandedWidth,
    );
    final shell = find.byType(StatefulNavigationShell);
    expect(
      tester.getTopRight(shell).dx,
      lessThanOrEqualTo(tester.getTopLeft(strip).dx),
    );
    await rig.dispose(tester);
  });

  uiTest('signed out: only the people icon', (tester) async {
    await befriend(['f1']);
    rig.profile = null;
    await pumpApp(tester);
    expect(strip, findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.byIcon(Icons.group_rounded)),
      findsOneWidget,
    );
    expect(face('f1'), findsNothing);
    await rig.dispose(tester);
  });
}
