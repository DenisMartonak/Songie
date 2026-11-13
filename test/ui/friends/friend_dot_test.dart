import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/account/avatar.dart';
import 'package:songies/ui/account/profile_page.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// Signs in; `ben` has asked to be friends.
  Future<String> signedInWithRequest() async {
    await h.accounts.signUp('me@x.com', 'password1', 'me');
    await h.accounts.verifySignup('me@x.com', h.accountBackend.goodCode);
    final me = (h.accounts.state as SignedIn).profile.id;
    h.friendsBackend
      ..addUser(me, 'me')
      ..addUser('b', 'ben')
      ..me = 'b';
    await h.friendsBackend.send(me);
    h.friendsBackend.me = me;
    return me;
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(
              body: Column(
                children: [
                  AccountButton(),
                  Expanded(child: ProfilePage()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder dotIn(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byKey(const Key('friends.dot')),
  );

  uiTest('a waiting request shows a dot on your picture and the Friends row', (
    tester,
  ) async {
    await signedInWithRequest();
    await pump(tester);
    expect(dotIn('shell.account'), findsOneWidget);
    expect(dotIn('profile.friends'), findsOneWidget);
    expect(find.byTooltip('me · friend requests waiting'), findsOneWidget);
  });

  uiTest('accepting the last request removes the dots', (tester) async {
    await signedInWithRequest();
    await pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    );
    await tester.runAsync(
      () => container.read(friendsServiceProvider).accept('b'),
    );
    await settle(tester);
    expect(find.byKey(const Key('friends.dot')), findsNothing);
    expect(find.byTooltip('me'), findsOneWidget);
  });

  uiTest('signed out there is no dot', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('friends.dot')), findsNothing);
  });
}
