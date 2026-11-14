import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/stats_summary.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/stats/stats_models.dart';
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

  Future<void> pump(
    WidgetTester tester,
    String location, {
    Size size = const Size(500, 1600),
  }) async {
    tester.view.physicalSize = size;
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
        StatsSummary(
          at: DateTime(2026, 11, 14),
          periods: {
            StatsPeriod.month: PeriodStats(
              period: StatsPeriod.month,
              total: const Duration(hours: 1),
              previousTotal: null,
              buckets: const [],
              topArtists: [
                for (var i = 1; i <= 12; i++)
                  ArtistStat(name: 'Artist $i', plays: 1, heard: Duration.zero),
              ],
              topSongs: const [
                SongStat(
                  trackId: 'yt:v1',
                  title: 'Halo',
                  artist: 'Beyonce',
                  mainArtist: '',
                  plays: 1,
                  heard: Duration.zero,
                  videoId: 'v1',
                ),
              ],
            ),
          },
        ),
      );
    });
    await pump(tester, '/profile/friends/f1');
    expect(
      tester.widget<Text>(key('profile.listening')).textSpan!.toPlainText(),
      'Listening to Halo · Beyonce',
    );
    expect(key('profile.join'), findsNothing);
    expect(find.text('Top 10 artists'), findsOneWidget);
    expect(find.text('Top 10 songs'), findsOneWidget);
    expect(find.text('Artist 5'), findsOneWidget);
    expect(find.text('Artist 6'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('Join appears when they host and joins their room', (tester) async {
    await pump(tester, '/profile/friends/f1');
    await rig.hostRoom(tester);
    await asFay((a) => a.publishNowPlaying(halo, roomCode: 'ABCD2345'));
    // The page asks again every minute while open.
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(key('profile.join'), findsOneWidget);
    await tester.tap(key('profile.join'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomGuesting>());
    await rig.dispose(tester);
  });

  uiTest('an unshared status shows no listening and says they do not '
      'share', (tester) async {
    await asFay((a) async {
      await a.publishNowPlaying(halo);
      await a.setSharing(listening: false, top: false);
    });
    await pump(tester, '/profile/friends/f1');
    expect(key('profile.listening'), findsNothing);
    expect(find.text("fay doesn't share their stats"), findsOneWidget);
    expect(find.text('Top 10 artists'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest("a friend's page has Back and the menu, no Edit profile", (
    tester,
  ) async {
    await pump(tester, '/profile/friends/f1');
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(key('profile.edit'), findsNothing);
    expect(find.text('Edit profile'), findsNothing);
    final menu = tester.getRect(key('profile.menu'));
    expect(menu.top, lessThan(tester.getRect(key('profile.name')).top));
    await tester.tap(key('profile.menu'));
    await settle(tester);
    expect(key('friend.remove'), findsOneWidget);
    expect(find.text('Remove friend'), findsOneWidget);
    expect(key('account.logOut'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest("wide: a friend's page has only the menu at the far right", (
    tester,
  ) async {
    await pump(tester, '/profile/friends/f1', size: const Size(1400, 900));
    expect(key('profile.edit'), findsNothing);
    expect(find.text('Edit profile'), findsNothing);
    final menu = tester.getRect(key('profile.menu'));
    // Content 1200 wide, centered in 1400, with 24 inside.
    expect(menu.right, closeTo(1276, 1));
    expect(menu.left, greaterThan(tester.getRect(key('profile.name')).right));
    // Nothing else sits beside it in the header's button row.
    final buttons = find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is IconButton,
    );
    final beside = tester
        .widgetList(buttons)
        .map((w) => tester.getRect(find.byWidget(w)))
        .where((r) => (r.center.dy - menu.center.dy).abs() < menu.height / 2)
        .where((r) => r.left > tester.getRect(key('profile.name')).right)
        // An M3 IconButton is a ButtonStyleButton inside: one rect each.
        .toSet();
    expect(beside, {menu});
    await rig.dispose(tester);
  });

  uiTest('Remove friend asks, removes and goes back without a "Not in your '
      'friends" frame', (tester) async {
    await pump(tester, '/profile/friends');
    await tester.tap(key('friends.friend.f1'));
    await settle(tester);
    await tester.tap(key('profile.menu'));
    await settle(tester);
    await tester.tap(key('friend.remove'));
    await settle(tester);
    expect(find.text('Remove fay from your friends?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Not in your friends'), findsNothing);
    }
    await settle(tester);
    expect(find.byType(FriendPage), findsNothing);
    expect(key('friends.friend.f1'), findsNothing);
    await rig.dispose(tester);
  });
}

typedef FakeActivity = ActivityBackend;
