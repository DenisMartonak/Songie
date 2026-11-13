import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:songies/ui/search/search_page.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// Signs in as `me` before the app starts; others exist on the server.
  Future<String> signedIn() async {
    await h.accounts.signUp('me@x.com', 'password1', 'me');
    await h.accounts.verifySignup('me@x.com', h.accountBackend.goodCode);
    final id = (h.accounts.state as SignedIn).profile.id;
    h.friendsBackend
      ..me = id
      ..addUser(id, 'me')
      ..addUser('d1', 'den')
      ..addUser('d2', 'dex')
      ..addUser('z1', 'zed');
    return id;
  }

  Future<void> pumpSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (_, _) => const Scaffold(body: SearchPage()),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('search.field')), text);
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await settle(tester);
  }

  Future<void> openUsers(WidgetTester tester) async {
    final tab = find.byKey(const Key('search.tab.users'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await settle(tester);
  }

  Finder key(String k) => find.byKey(Key(k));

  String label(WidgetTester tester, String id) => tester
      .widget<Text>(
        find.descendant(
          of: key('friends.action.$id'),
          matching: find.byType(Text),
        ),
      )
      .data!;

  uiTest('the Songies Users tab finds people by name', (tester) async {
    final me = await signedIn();
    await pumpSearch(tester);
    await type(tester, 'de');
    await openUsers(tester);
    expect(find.text('Songies Users'), findsOneWidget);
    expect(key('friends.user.d1'), findsOneWidget);
    expect(key('friends.user.d2'), findsOneWidget);
    expect(key('friends.user.z1'), findsNothing);
    expect(key('friends.user.$me'), findsNothing);
    expect(label(tester, 'd1'), 'Add friend');
  });

  uiTest('typing on the Songies Users tab asks YouTube Music nothing', (
    tester,
  ) async {
    await signedIn();
    await pumpSearch(tester);
    await type(tester, 'de');
    await openUsers(tester);
    h.ytm.calls.clear();
    await type(tester, 'dex');
    await type(tester, 'zed');
    expect(h.ytm.calls, isEmpty);
    expect(find.byKey(const Key('friends.user.z1')), findsOneWidget);
  });

  uiTest('short queries and nobody found say so', (tester) async {
    await signedIn();
    await pumpSearch(tester);
    await type(tester, 'd');
    await openUsers(tester);
    expect(find.text('Type at least 2 letters'), findsOneWidget);
    await type(tester, 'qq');
    expect(find.text('No Songies users found'), findsOneWidget);
  });

  uiTest('signed out it asks to log in', (tester) async {
    await pumpSearch(tester);
    await type(tester, 'de');
    await openUsers(tester);
    expect(find.text('Log in to find friends'), findsOneWidget);
    expect(h.friendsBackend.calls, isNot(contains('search')));
  });

  uiTest('Add friend becomes Requested; Requested cancels; Accept accepts', (
    tester,
  ) async {
    await signedIn();
    // dex already asked.
    final me = h.friendsBackend.me;
    h.friendsBackend.me = 'd2';
    await h.friendsBackend.send(me);
    h.friendsBackend.me = me;
    await pumpSearch(tester);
    await type(tester, 'de');
    await openUsers(tester);
    expect(label(tester, 'd2'), 'Accept');

    await tester.tap(key('friends.action.d1'));
    await settle(tester);
    expect(label(tester, 'd1'), 'Requested');
    await tester.tap(key('friends.action.d1'));
    await settle(tester);
    expect(label(tester, 'd1'), 'Add friend');

    await tester.tap(key('friends.action.d2'));
    await settle(tester);
    expect(label(tester, 'd2'), 'Friends');
  });

  uiTest('an action offline says so and keeps the button', (tester) async {
    await signedIn();
    await pumpSearch(tester);
    await type(tester, 'de');
    await openUsers(tester);
    h.friendsBackend.error = const FriendsException(FriendsError.offline);
    await tester.tap(key('friends.action.d1'));
    await settle(tester);
    expect(find.text("You're offline"), findsOneWidget);
    expect(label(tester, 'd1'), 'Add friend');
    h.friendsBackend.error = null;
    await tester.tap(key('friends.action.d1'));
    await settle(tester);
    expect(label(tester, 'd1'), 'Requested');
  });
}
