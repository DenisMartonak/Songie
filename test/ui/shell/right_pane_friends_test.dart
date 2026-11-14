import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/room/join_room_dialog.dart';
import 'package:songies/ui/shell/right_pane_friends.dart';

import '../../helpers/room_rig.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');
  const me = Profile(id: 'u1', username: 'me', email: 'me@example.com');

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

  /// [ids] become friends of u1.
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

  Future<void> asUser(String id, Future<void> Function() f) async {
    h.activityBackend.me = id;
    await f();
    h.activityBackend.me = 'u1';
  }

  /// [own] replaces the rig's account override (its first one).
  Future<void> pump(WidgetTester tester, {List<Override>? own}) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [...?own, ...rig.overrides.skip(own == null ? 0 : 1)],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: RightPaneFriends()),
          ),
          GoRoute(
            path: '/profile/friends',
            builder: (_, s) => Text('at ${s.uri.path}'),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (_, s) => Text('at ${s.uri.path}'),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(Key(k));

  uiTest('room on top, then friends with what they play and Join', (
    tester,
  ) async {
    await befriend(['f1', 'f2']);
    await asUser(
      'f1',
      () => h.activityBackend.publishNowPlaying(halo, roomCode: 'ABCD2345'),
    );
    await pump(tester);
    expect(key('rightPane.friends'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(
      find.descendant(
        of: key('rightPane.friend.f1'),
        matching: find.text('♪ Halo · Beyonce'),
      ),
      findsOneWidget,
    );
    expect(key('rightPane.join.f1'), findsOneWidget);
    expect(key('rightPane.friend.f2'), findsOneWidget);
    expect(key('rightPane.join.f2'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('Join asks to join the friend room', (tester) async {
    await befriend(['f1']);
    await asUser(
      'f1',
      () => h.activityBackend.publishNowPlaying(halo, roomCode: 'ABCD2345'),
    );
    await pump(tester);
    await tester.tap(key('rightPane.join.f1'));
    await rig.run(tester, Future.value());
    expect(rig.backend.calls, contains('join ABCD2345'));
    await rig.dispose(tester);
  });

  uiTest('a friend opens their page', (tester) async {
    await befriend(['f1']);
    await pump(tester);
    await tester.tap(key('rightPane.friend.f1'));
    await settle(tester);
    expect(find.text('at /profile/friends/f1'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('requests and find friends links', (tester) async {
    // Not loaded yet: neither link.
    await pump(tester);
    // Loaded with nothing: Find friends.
    expect(key('rightPane.findFriends'), findsOneWidget);
    expect(key('rightPane.requests'), findsNothing);
    await tester.tap(key('rightPane.findFriends'));
    await settle(tester);
    expect(find.text('at /profile/friends'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('one request reads 1 request, two read 2 requests', (tester) async {
    final f = h.friendsBackend
      ..addUser('a', 'a')
      ..addUser('b', 'b');
    f.me = 'a';
    await f.send('u1');
    f.me = 'u1';
    await pump(tester);
    expect(find.text('1 request'), findsOneWidget);
    expect(key('rightPane.findFriends'), findsOneWidget);
    await rig.dispose(tester);

    f.me = 'b';
    await f.send('u1');
    f.me = 'u1';
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.text('2 requests'), findsOneWidget);
    await tester.tap(key('rightPane.requests'));
    await settle(tester);
    expect(find.text('at /profile/friends'), findsOneWidget);
  });

  uiTest('no links before the friends have loaded', (tester) async {
    final gate = Completer<void>();
    h.friendsBackend.loadGates.add(gate.future);
    await pump(tester);
    expect(key('rightPane.findFriends'), findsNothing);
    expect(key('rightPane.requests'), findsNothing);
    gate.complete();
    await settle(tester);
    expect(key('rightPane.findFriends'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('holds a close watch while shown, released when gone', (tester) async {
    await pump(tester);
    final service = containerOf(tester).read(friendsServiceProvider);
    expect(service.closeWatches, 1);
    await tester.pumpWidget(const SizedBox());
    expect(service.closeWatches, 0);
    await rig.dispose(tester);
  });

  uiTest('signing out leaves only the sign-in line', (tester) async {
    await befriend(['f1']);
    final account = StreamController<AccountState>();
    addTearDown(account.close);
    account.add(const SignedIn(me));
    await pump(
      tester,
      own: [accountStateProvider.overrideWith((ref) => account.stream)],
    );
    final service = containerOf(tester).read(friendsServiceProvider);
    expect(key('rightPane.friend.f1'), findsOneWidget);
    expect(service.closeWatches, 1);
    account.add(const SignedOut());
    await settle(tester);
    expect(key('rightPane.friend.f1'), findsNothing);
    expect(find.text(kRoomSignInText), findsOneWidget);
    expect(service.closeWatches, 0);
    expect(tester.takeException(), isNull);
    await rig.dispose(tester);
  });
}
