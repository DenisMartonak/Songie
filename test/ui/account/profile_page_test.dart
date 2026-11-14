import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/ui/account/avatar.dart';
import 'package:songies/ui/account/profile_page.dart';
import 'package:songies/ui/profile/profile_view.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late Directory tmp;

  setUp(() async {
    h = await UiHarness.create();
    tmp = Directory.systemTemp.createTempSync('songies_profile_');
    h.paths = AppPaths.at(tmp);
    await h.paths!.ensureCreated();
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester,
    String location, {
    Size size = const Size(1000, 2400),
    bool nested = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: nested ? '/home/profile' : location,
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
        ],
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
            routes: [
              GoRoute(
                path: 'profile',
                builder: (_, _) => const Scaffold(body: ProfilePage()),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: ProfilePage()),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: SettingsPage()),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> signedIn() async {
    await h.accounts.signUp('den@x.com', 'password1', 'den');
    await h.accounts.verifySignup('den@x.com', h.accountBackend.goodCode);
  }

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;
  Finder key(String k) => find.byKey(Key(k));

  uiTest('signed in: the profile view with Edit profile and the menu; no '
      'sync status or Account heading', (tester) async {
    await signedIn();
    await pump(tester, '/profile');
    expect(find.byType(ProfileView), findsOneWidget);
    expect(tester.widget<Text>(key('profile.name')).data, 'den');
    expect(key('profile.edit'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(key('profile.menu'), findsOneWidget);
    expect(key('account.syncStatus'), findsNothing);
    expect(key('account.syncNow'), findsNothing);
    expect(find.text('Account'), findsNothing);
    // The email and the actions are tucked away until asked for.
    expect(key('account.email'), findsNothing);
    expect(key('account.logOut'), findsNothing);
    expect(key('account.delete'), findsNothing);
    final stats = key('profile.chart').evaluate().isNotEmpty
        ? key('profile.chart')
        : key('profile.empty');
    expect(stats, findsOneWidget);
    expect(top(tester, key('profile.name')), lessThan(top(tester, stats)));
  });

  uiTest('the menu holds Log out and Delete account', (tester) async {
    await signedIn();
    await pump(tester, '/profile');
    await tester.tap(key('profile.menu'));
    await settle(tester);
    expect(key('account.logOut'), findsOneWidget);
    expect(key('account.delete'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  uiTest('wide: Edit profile opens a dialog with picture, username and '
      'email', (tester) async {
    await signedIn();
    await pump(tester, '/profile');
    await tester.tap(key('profile.edit'));
    await settle(tester);
    final sheet = key('profile.editSheet');
    expect(
      find.ancestor(of: sheet, matching: find.byType(Dialog)),
      findsOneWidget,
    );
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    expect(
      tester.widget<Text>(inSheet(key('account.email'))).data,
      'den@x.com',
    );
    expect(inSheet(key('account.username')), findsOneWidget);
    expect(inSheet(key('profile.avatar')), findsOneWidget);
    expect(inSheet(find.byType(AccountAvatar)), findsOneWidget);

    await tester.tap(key('profile.editDone'));
    await settle(tester);
    expect(sheet, findsNothing);
  });

  uiTest('phone: Edit profile opens a bottom sheet', (tester) async {
    await signedIn();
    await pump(tester, '/profile', size: const Size(400, 900));
    await tester.tap(key('profile.edit'));
    await settle(tester);
    final sheet = key('profile.editSheet');
    expect(
      find.ancestor(of: sheet, matching: find.byType(BottomSheet)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: key('account.email')),
      findsOneWidget,
    );
  });

  uiTest('phone: Back on the left and the menu on the right of the top bar, '
      'Edit profile under the name', (tester) async {
    await signedIn();
    await pump(tester, '/profile', size: const Size(400, 900), nested: true);
    final menu = tester.getRect(key('profile.menu'));
    final back = tester.getRect(find.byTooltip('Back'));
    final avatar = tester.getRect(find.byType(AccountAvatar).first);
    final name = tester.getRect(key('profile.name'));
    final edit = tester.getRect(key('profile.edit'));
    expect(menu.bottom, lessThanOrEqualTo(avatar.top));
    expect(back.center.dy, closeTo(menu.center.dy, 1));
    expect(back.left, lessThan(100));
    expect(menu.right, greaterThan(300));
    expect(edit.top, greaterThan(name.bottom));
    expect(edit.center.dx, closeTo(200, 1));

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('home'), findsOneWidget);
  });

  uiTest('phone: no Back when there is nowhere to go back to', (tester) async {
    await signedIn();
    await pump(tester, '/profile', size: const Size(400, 900));
    expect(find.byTooltip('Back'), findsNothing);
    expect(key('profile.menu'), findsOneWidget);
  });

  uiTest('wide: Edit profile and the menu side by side at the far right', (
    tester,
  ) async {
    await signedIn();
    await pump(tester, '/profile', size: const Size(1400, 1200));
    final edit = tester.getRect(key('profile.edit'));
    final menu = tester.getRect(key('profile.menu'));
    final name = tester.getRect(key('profile.name'));
    expect(menu.left, greaterThan(edit.right));
    expect(menu.center.dy, closeTo(edit.center.dy, 1));
    expect(edit.left, greaterThan(name.right));
    // Content 1200 wide, centered in 1400, with 24 inside.
    expect(menu.right, closeTo(1276, 1));
  });

  uiTest('signed out: Sign up and Log in, no stats', (tester) async {
    await pump(tester, '/profile');
    expect(key('account.signUp'), findsOneWidget);
    expect(key('account.logIn'), findsOneWidget);
    expect(key('profile.period.week'), findsNothing);
    expect(key('profile.menu'), findsNothing);
    expect(key('profile.edit'), findsNothing);
  });

  uiTest('Settings has no Account section any more', (tester) async {
    await signedIn();
    await pump(tester, '/settings');
    expect(key('account.username'), findsNothing);
    expect(key('account.signUp'), findsNothing);
    expect(find.text('Account'), findsNothing);
  });

  uiTest('logging out returns the page to Sign up / Log in', (tester) async {
    await signedIn();
    await pump(tester, '/profile');
    await tester.tap(key('profile.menu'));
    await settle(tester);
    await tester.tap(key('account.logOut'));
    await settle(tester);
    expect(key('account.signUp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
