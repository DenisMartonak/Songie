import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/ui/room/room_strip.dart';
import 'package:songies/ui/shell/right_pane_state.dart';

import '../helpers/room_rig.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;

  setUp(() async {
    h = await UiHarness.create();
    rig = RoomRig(h);
  });
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: rig.overrides,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Column(children: [RoomStrip(), Spacer(), RoomChip()]),
            ),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  final strip = find.byKey(const Key('room.strip'));
  final chip = find.byKey(const Key('room.chip'));
  final popup = find.byKey(const Key('room.popup'));

  /// Stores the right pane closed and on Lyrics, so showing Friends shows.
  Future<void> paneClosedOnLyrics(WidgetTester tester) async {
    final container = containerOf(tester);
    // Keeps the setting loaded, as the desktop shell does.
    final sub = container.listen(rightPaneOpenProvider, (_, _) {});
    addTearDown(sub.close);
    container
        .read(rightPaneContentProvider.notifier)
        .show(RightPaneContent.lyrics);
    await real(
      tester,
      () => SettingsRepository(h.db).setBool(kRightPaneOpen, false),
    );
    for (
      var i = 0;
      i < 10 && container.read(rightPaneOpenProvider) != false;
      i++
    ) {
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
    }
    expect(container.read(rightPaneOpenProvider), isFalse);
  }

  /// The pane is open on Friends.
  Future<void> expectPaneOnFriends(WidgetTester tester) async {
    final container = containerOf(tester);
    for (
      var i = 0;
      i < 10 && container.read(rightPaneOpenProvider) != true;
      i++
    ) {
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
    }
    expect(container.read(rightPaneOpenProvider), isTrue);
    expect(container.read(rightPaneContentProvider), RightPaneContent.friends);
  }

  uiTest('no room: no strip and no chip', (tester) async {
    await pump(tester);
    expect(strip, findsNothing);
    expect(chip, findsNothing);
    await rig.dispose(tester);
  });

  for (final (role, text) in [
    (RoomRole.listener, 'Listening with denis'),
    (RoomRole.queue, 'Listening with denis · can add songs'),
    (RoomRole.full, 'Listening with denis · full control'),
  ]) {
    uiTest('guest strip as ${role.name}: "$text"', (tester) async {
      await pump(tester);
      await rig.joinAs(tester, role);
      expect(
        find.descendant(of: strip, matching: find.text(text)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.byIcon(Icons.headphones_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip, matching: find.text('Listening with denis')),
        findsOneWidget,
      );
      await rig.dispose(tester);
    });
  }

  uiTest('the guest strip\'s Leave leaves, the music playing on', (
    tester,
  ) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.listener);
    await tester.tap(find.descendant(of: strip, matching: find.text('Leave')));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomIdle>());
    expect(strip, findsNothing);
    expect(h.player.state.playing, isTrue);
    await rig.dispose(tester);
  });

  uiTest(
    'host strip: "Your room · 2 listening", Manage shows the room in the right pane',
    (tester) async {
      await pump(tester);
      await rig.run(tester, rig.service!.open(userId: 'u1', name: 'me'));
      await rig.guestJoins(tester, 'g1', 'anna');
      await rig.guestJoins(tester, 'g2', 'bob');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: strip,
          matching: find.text('Your room · 2 listening'),
        ),
        findsOneWidget,
      );
      await paneClosedOnLyrics(tester);
      await tester.tap(
        find.descendant(of: strip, matching: find.text('Manage')),
      );
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      await expectPaneOnFriends(tester);
      await rig.dispose(tester);
    },
  );

  uiTest('on the desktop, tapping the strip shows the room in the right '
      'pane, not a dialog', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.listener);
    await paneClosedOnLyrics(tester);
    await tester.tap(strip);
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    await expectPaneOnFriends(tester);
    await rig.dispose(tester);
  });

  uiTest('on a phone, tapping the strip opens the room sheet', (tester) async {
    await pump(tester, size: const Size(400, 900));
    await rig.joinAs(tester, RoomRole.listener);
    await tester.tap(strip);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room.sheet')), findsOneWidget);
    await rig.dispose(tester);
  });
}
