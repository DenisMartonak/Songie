import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/ui/account/profile_page.dart';
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

  Future<void> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
        ],
        routes: [
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

  uiTest('signed in: header, stats, then account actions in that order', (
    tester,
  ) async {
    await signedIn();
    await pump(tester, '/profile');
    final stats = key('stats.chart').evaluate().isNotEmpty
        ? key('stats.chart')
        : key('stats.empty');
    expect(stats, findsOneWidget);
    expect(key('account.email'), findsOneWidget);
    expect(top(tester, key('account.username')), lessThan(top(tester, stats)));
    expect(
      top(tester, stats),
      lessThan(top(tester, key('account.syncStatus'))),
    );
    expect(
      top(tester, key('account.syncStatus')),
      lessThan(top(tester, key('account.logOut'))),
    );
    expect(
      top(tester, key('account.logOut')),
      lessThanOrEqualTo(top(tester, key('account.delete'))),
    );
  });

  uiTest('signed out: Sign up and Log in, no stats', (tester) async {
    await pump(tester, '/profile');
    expect(key('account.signUp'), findsOneWidget);
    expect(key('account.logIn'), findsOneWidget);
    expect(key('stats.period.week'), findsNothing);
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
    await tester.ensureVisible(key('account.logOut'));
    await tester.tap(key('account.logOut'));
    await settle(tester);
    expect(key('account.signUp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
