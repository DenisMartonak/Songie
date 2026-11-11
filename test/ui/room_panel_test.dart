import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/ui/room/room_button.dart';
import 'package:songies/ui/room/room_islands.dart';

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
              body: RoomIslands(child: Center(child: RoomButton())),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Settings page')),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('room.button')));
    await tester.pumpAndSettle();
  }

  uiTest('idle: Start a room and Join a room', (tester) async {
    await pump(tester);
    await openPanel(tester);
    expect(find.text('Listen together'), findsOneWidget);
    expect(find.text('Start a room'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('signed out: the panel asks to sign in', (tester) async {
    rig.profile = null;
    await pump(tester);
    await openPanel(tester);
    expect(
      find.text('You need a Songies account to join a room'),
      findsOneWidget,
    );
    expect(find.text('Start a room'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('a code that is not one says so', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tester.enterText(find.byKey(const Key('room.joinField')), 'nope');
    await tester.tap(find.text('Join a room'));
    await tester.pump();
    expect(find.text('Not a room code or link'), findsOneWidget);
    expect(rig.backend.calls, isEmpty);
    await rig.dispose(tester);
  });

  uiTest('joining by link from the panel', (tester) async {
    await pump(tester);
    await rig.hostRoom(tester);
    await openPanel(tester);
    await tester.enterText(
      find.byKey(const Key('room.joinField')),
      'songies://room/abcd-2345',
    );
    await tester.tap(find.text('Join a room'));
    await rig.run(tester, Future.value());
    expect(rig.backend.calls, contains('join ABCD2345'));
    expect(rig.service!.status, isA<RoomGuesting>());
    // The panel now shows the room as a guest.
    expect(find.text('Leave'), findsOneWidget);
    expect(find.text('denis'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('hosting: the link, the people and their roles', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tester.tap(find.text('Start a room'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomHosting>());
    expect(
      find.text('https://denismartonak.github.io/Songie/r/ABCD2345'),
      findsOneWidget,
    );
    expect(find.text('Code ABCD-2345'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    // Share link is for phones (Android).
    expect(find.text('Share link'), findsNothing);
    expect(find.text('End room'), findsOneWidget);

    await rig.guestJoins(tester, 'g1', 'anna');
    await rig.guestJoins(tester, 'g2', 'bob', platform: 'linux');
    await tester.pumpAndSettle();
    expect(find.text('anna'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    // This device and bob's.
    expect(find.text('Desktop'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('room.role.g1')));
    await tester.pumpAndSettle();
    expect(find.text('Listener'), findsWidgets);
    expect(find.text('Full control'), findsOneWidget);
    await tester.tap(find.text('Queue').last);
    await rig.run(tester, Future.value());
    expect((rig.service!.status as RoomHosting).roles, {'g1': RoomRole.queue});
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('hosting: removing someone asks first', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tester.tap(find.text('Start a room'));
    await rig.run(tester, Future.value());
    await rig.guestJoins(tester, 'g1', 'anna');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room.remove.g1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove anna?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await rig.run(tester, Future.value());
    expect(rig.hub.sent.whereType<RoomKickMsg>().single.deviceId, 'g1');
    await rig.dispose(tester);
  });

  uiTest('hosting: End room asks first, then ends it', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tester.tap(find.text('Start a room'));
    await rig.run(tester, Future.value());
    await tester.tap(find.text('End room'));
    await tester.pumpAndSettle();
    expect(find.text('End the room?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rig.service!.status, isA<RoomHosting>());
    await tester.tap(find.text('End room'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End room'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomIdle>());
    expect(rig.backend.calls, contains('end room1'));
    await rig.dispose(tester);
  });

  uiTest('guesting: everyone with their roles, read-only, and Leave', (
    tester,
  ) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.queue);
    await rig.guestJoins(tester, 'g2', 'bob');
    await rig.run(tester, rig.host.setRole('g2', RoomRole.full));
    await openPanel(tester);
    expect(find.text('denis'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Full control'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.byKey(const Key('room.role.g2')), findsNothing);
    expect(find.byKey(const Key('room.remove.g2')), findsNothing);
    await tester.tap(find.text('Leave'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomIdle>());
    // Leaving keeps the music playing.
    expect(h.player.state.playing, isTrue);
    await rig.dispose(tester);
  });
}
