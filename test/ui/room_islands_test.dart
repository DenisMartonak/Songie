import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/providers.dart';
import 'package:songies/remote/remote_protocol.dart';
import 'package:songies/room/room_service.dart';
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

  Future<void> pump(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [...rig.overrides, ...extra],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: RoomIslands(child: Text('Home'))),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: Text('Profile page')),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  void invite(WidgetTester tester, String code) =>
      containerOf(tester).read(roomInviteProvider.notifier).set(code);

  group('every room notice shows as an island', () {
    const texts = [
      'This room has ended',
      'This room is full',
      'Room not found',
      'The room ended',
      'You were removed from the room',
      'anna joined',
      'anna left',
      'anna added Song a',
      'You can now add songs',
      'You now have full control',
      'You can listen only',
      "Can't play Song a here, joining in at the next song",
      "Local files can't be shared in a room",
      "Couldn't reach the room",
      'Update Songies to join this room',
    ];
    for (final text in texts) {
      uiTest(text, (tester) async {
        final notices = StreamController<RoomNotice>.broadcast();
        addTearDown(notices.close);
        await pump(
          tester,
          extra: [roomNoticesProvider.overrideWithValue(notices.stream)],
        );
        notices.add(RoomNoticeText(text));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(text), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await rig.dispose(tester);
      });
    }

    uiTest('a sign-in notice offers Sign in, which opens Settings', (
      tester,
    ) async {
      final notices = StreamController<RoomNotice>.broadcast();
      addTearDown(notices.close);
      await pump(
        tester,
        extra: [roomNoticesProvider.overrideWithValue(notices.stream)],
      );
      notices.add(
        const RoomNoticeText(
          'You need a Songies account to join a room',
          signIn: true,
        ),
      );
      await tester.pump();
      // Let the island finish rising before tapping its action.
      await tester.pumpAndSettle();
      expect(
        find.text('You need a Songies account to join a room'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Profile page'), findsOneWidget);
      await rig.dispose(tester);
    });
  });

  uiTest('an invite while signed out asks to sign in', (tester) async {
    rig.profile = null;
    await pump(tester);
    invite(tester, 'ABCD2345');
    await tester.pump();
    await tester.pump();
    expect(
      find.text('You need a Songies account to join a room'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
    expect(rig.backend.calls, isEmpty);
    expect(containerOf(tester).read(roomInviteProvider), isNull);
    await tester.pump(const Duration(seconds: 5));
    await rig.dispose(tester);
  });

  uiTest('an invite while idle joins the room', (tester) async {
    await pump(tester);
    await rig.hostRoom(tester);
    invite(tester, 'ABCD2345');
    await rig.run(tester, Future.value());
    expect(rig.backend.calls, contains('join ABCD2345'));
    expect(rig.service!.status, isA<RoomGuesting>());
    await rig.dispose(tester);
  });

  uiTest('an invite while hosting asks to leave the room first', (
    tester,
  ) async {
    await pump(tester);
    await rig.run(tester, rig.service!.open(userId: 'u1', name: 'me'));

    invite(tester, 'ABCD2345');
    await tester.pumpAndSettle();
    expect(find.text('Leave the current room?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rig.service!.status, isA<RoomHosting>());
    expect(rig.backend.calls, isNot(contains('join ABCD2345')));

    invite(tester, 'ABCD2345');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      rig.backend.calls,
      containsAllInOrder(['end room1', 'join ABCD2345']),
    );
    // Nobody hosts that room now: the join gives up, as a stale room.
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('This room has ended'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await rig.dispose(tester);
  });

  uiTest('an invite while controlling a device asks to stop first', (
    tester,
  ) async {
    await pump(tester);
    await rig.hostRoom(tester);
    const pc = RemotePresence(
      deviceId: 'pc',
      name: 'Office PC',
      platform: 'linux',
      appVersion: '1.0.0',
      playing: false,
    );
    await rig.remoteHub.channelFor('pc').join(pc);
    await flush(tester);
    final controller = containerOf(tester).read(remoteControllerProvider)!;
    await controller.select(pc);
    await tester.pump();

    invite(tester, 'ABCD2345');
    await tester.pumpAndSettle();
    expect(find.text('Stop controlling Office PC?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await rig.run(tester, Future.value());
    expect(controller.link, isNull);
    expect(rig.service!.status, isA<RoomGuesting>());
    await rig.dispose(tester);
  });
}
