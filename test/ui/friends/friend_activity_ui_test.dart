import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/ui/friends/friend_page.dart';
import 'package:songies/ui/friends/friends_page.dart';

import '../../helpers/room_rig.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');

  setUp(() async {
    h = await UiHarness.create();
    rig = RoomRig(h);
    // The rig signs the app in as u1; f1 is a friend.
    final f = h.friendsBackend
      ..addUser('u1', 'me')
      ..addUser('f1', 'fay')
      ..me = 'u1';
    await f.send('f1');
    f.me = 'f1';
    await f.accept('u1');
    f.me = 'u1';
    h.activityBackend
      ..friendsOf = ((id) => id == 'u1' ? {'f1'} : {'u1'})
      ..me = 'u1';
  });
  tearDown(() => h.dispose());

  /// Publishes as the friend.
  Future<void> asFay(Future<void> Function(FakeActivity a) f) async {
    h.activityBackend.me = 'f1';
    await f(h.activityBackend);
    h.activityBackend.me = 'u1';
  }

  Future<void> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        extraOverrides: rig.overrides,
        routes: [
          GoRoute(
            path: '/profile/friends',
            builder: (_, _) => const Scaffold(body: FriendsPage()),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (_, s) => Scaffold(
                  body: FriendPage(userId: s.pathParameters['userId']!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(Key(k));

  uiTest('a listening friend shows what they play on their row', (
    tester,
  ) async {
    await asFay((a) => a.publishNowPlaying(halo));
    await pump(tester, '/profile/friends');
    expect(
      tester.widget<Text>(key('friends.listening.f1')).data,
      '♪ Halo · Beyonce',
    );
    await rig.dispose(tester);
  });

  uiTest("a friend's page shows now playing, top artists and top songs", (
    tester,
  ) async {
    await asFay((a) async {
      await a.publishNowPlaying(halo);
      await a.publishTop(
        TopSummary(
          artists: [for (var i = 1; i <= 12; i++) 'Artist $i'],
          songs: const [halo],
        ),
      );
    });
    await pump(tester, '/profile/friends/f1');
    expect(
      find.descendant(
        of: key('friend.nowPlaying'),
        matching: find.text('Halo'),
      ),
      findsOneWidget,
    );
    expect(key('friend.join'), findsNothing);
    expect(find.text('Top artists'), findsOneWidget);
    expect(find.text('Top songs'), findsOneWidget);
    expect(find.text('Artist 10'), findsOneWidget);
    expect(find.text('Artist 11'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('Join appears when they host and joins their room', (tester) async {
    await pump(tester, '/profile/friends/f1');
    await rig.hostRoom(tester);
    await asFay((a) => a.publishNowPlaying(halo, roomCode: 'ABCD2345'));
    // The page asks again every minute while open.
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(key('friend.join'), findsOneWidget);
    await tester.tap(key('friend.join'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomGuesting>());
    await rig.dispose(tester);
  });

  uiTest('a stale or unshared status says Not listening right now', (
    tester,
  ) async {
    await asFay((a) async {
      await a.publishNowPlaying(halo);
      await a.setSharing(const Sharing(listening: false, top: false));
    });
    await pump(tester, '/profile/friends/f1');
    expect(key('friend.notListening'), findsOneWidget);
    expect(find.text('Not listening right now'), findsOneWidget);
    expect(find.text('Top artists'), findsNothing);
    await rig.dispose(tester);
  });
}

typedef FakeActivity = ActivityBackend;
