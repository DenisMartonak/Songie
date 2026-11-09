import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/ui/room/room_strip.dart';

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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
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

  uiTest('host strip: "Your room · 2 listening", Manage opens the panel', (
    tester,
  ) async {
    await pump(tester);
    await rig.run(tester, rig.service!.open(userId: 'u1', name: 'me'));
    await rig.guestJoins(tester, 'g1', 'anna');
    await rig.guestJoins(tester, 'g2', 'bob');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: strip, matching: find.text('Your room · 2 listening')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: strip, matching: find.text('Manage')));
    await tester.pumpAndSettle();
    expect(find.text('Listen together'), findsOneWidget);
    expect(find.text('End room'), findsOneWidget);
    await rig.dispose(tester);
  });
}
