import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/ui/account/profile_page.dart';
import 'package:songies/ui/friends/friend_page.dart';
import 'package:songies/ui/friends/friends_page.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late String me;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// Signs in; [incoming] asked me, I asked [outgoing], [friends] are
  /// friends.
  Future<void> signedIn({
    List<String> incoming = const [],
    List<String> outgoing = const [],
    List<String> friends = const [],
  }) async {
    await h.accounts.signUp('me@x.com', 'password1', 'me');
    await h.accounts.verifySignup('me@x.com', h.accountBackend.goodCode);
    me = (h.accounts.state as SignedIn).profile.id;
    final f = h.friendsBackend..addUser(me, 'me');
    for (final id in [...incoming, ...outgoing, ...friends]) {
      f.addUser(id, 'user_$id');
    }
    for (final id in incoming) {
      f.me = id;
      await f.send(me);
    }
    f.me = me;
    for (final id in [...outgoing, ...friends]) {
      await f.send(id);
    }
    for (final id in friends) {
      f.me = id;
      await f.accept(me);
    }
    f.me = me;
  }

  Future<GoRouter> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: ProfilePage()),
            routes: [
              GoRoute(
                path: 'friends',
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
        ],
      ),
    );
    await settle(tester);
    return GoRouter.of(tester.element(find.byType(Scaffold).first));
  }

  Finder key(String k) => find.byKey(Key(k));
  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  uiTest('requests first, then sent, then friends', (tester) async {
    await signedIn(incoming: ['i1'], outgoing: ['o1'], friends: ['f1']);
    await pump(tester, '/profile/friends');
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Friends'), findsWidgets);
    expect(
      top(tester, key('friends.incoming.i1')),
      lessThan(top(tester, key('friends.outgoing.o1'))),
    );
    expect(
      top(tester, key('friends.outgoing.o1')),
      lessThan(top(tester, key('friends.friend.f1'))),
    );
  });

  uiTest('Accept moves a request into Friends; Decline removes it', (
    tester,
  ) async {
    await signedIn(incoming: ['i1', 'i2']);
    await pump(tester, '/profile/friends');
    await tester.tap(key('friends.accept.i1'));
    await settle(tester);
    expect(key('friends.incoming.i1'), findsNothing);
    expect(key('friends.friend.i1'), findsOneWidget);
    await tester.tap(key('friends.decline.i2'));
    await settle(tester);
    expect(key('friends.incoming.i2'), findsNothing);
    expect(find.text('Requests'), findsNothing);
  });

  uiTest('Cancel withdraws a sent request', (tester) async {
    await signedIn(outgoing: ['o1']);
    await pump(tester, '/profile/friends');
    await tester.tap(key('friends.cancel.o1'));
    await settle(tester);
    expect(key('friends.outgoing.o1'), findsNothing);
  });

  uiTest('tapping a friend opens their page; Remove asks and removes', (
    tester,
  ) async {
    await signedIn(friends: ['f1']);
    final router = await pump(tester, '/profile/friends');
    await tester.tap(key('friends.friend.f1'));
    await settle(tester);
    expect(router.state.uri.path, '/profile/friends/f1');
    expect(find.text('user_f1'), findsOneWidget);
    await tester.tap(key('friend.remove'));
    await settle(tester);
    expect(find.text('Remove user_f1 from your friends?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(h.friendsBackend.calls, isNot(contains('remove')));
    await tester.tap(key('friend.remove'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(tester);
    expect(router.state.uri.path, '/profile/friends');
    expect(key('friends.friend.f1'), findsNothing);
  });

  uiTest('no friends shows the empty state', (tester) async {
    await signedIn();
    await pump(tester, '/profile/friends');
    expect(
      find.text('No friends yet. Find people in Search under Songies Users.'),
      findsOneWidget,
    );
  });

  uiTest('the profile has a Friends row with the count', (tester) async {
    await signedIn(friends: ['f1', 'f2'], incoming: ['i1']);
    final router = await pump(tester, '/profile');
    expect(find.text('Friends · 2'), findsOneWidget);
    await tester.tap(key('profile.friends'));
    await settle(tester);
    expect(router.state.uri.path, '/profile/friends');
  });
}
