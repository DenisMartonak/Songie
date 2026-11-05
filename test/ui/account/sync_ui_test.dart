import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/sync/cloud/sync_status.dart';
import 'package:songies/ui/account/account_dialogs.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late Directory tmp;
  final now = DateTime(2026, 11, 5, 12);

  setUp(() async {
    h = await UiHarness.create();
    h.now = () => now;
    tmp = Directory.systemTemp.createTempSync('songies_sync_ui_');
    h.paths = AppPaths.at(tmp);
    await h.paths!.ensureCreated();
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpAccount(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        navigatorKey: navigatorKey,
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
        ],
        routes: [
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

  String statusText(WidgetTester tester) =>
      tester.widget<Text>(key('account.syncStatus')).data!;

  uiTest('Account shows Synced / Syncing… / Waiting for internet and Last '
      'synced', (tester) async {
    await signedIn();
    h.cloudSync.emit(
      SyncStatus(
        SyncPhase.idle,
        lastSynced: now.subtract(const Duration(minutes: 5)),
      ),
    );
    await pumpAccount(tester);
    expect(statusText(tester), 'Synced');
    expect(find.text('Last synced 5 min ago'), findsOneWidget);
    final syncNow = key('account.syncNow');
    expect(tester.widget<TextButton>(syncNow).onPressed, isNotNull);

    h.cloudSync.emit(const SyncStatus(SyncPhase.syncing));
    await settle(tester);
    expect(statusText(tester), 'Syncing…');
    // Disabled while syncing.
    expect(tester.widget<TextButton>(syncNow).onPressed, isNull);

    h.cloudSync.emit(
      SyncStatus(
        SyncPhase.offline,
        lastSynced: now.subtract(const Duration(hours: 2)),
      ),
    );
    await settle(tester);
    expect(statusText(tester), 'Waiting for internet');
    expect(find.text('Last synced 2 h ago'), findsOneWidget);

    h.cloudSync.emit(const SyncStatus(SyncPhase.error));
    await settle(tester);
    expect(statusText(tester), "Couldn't sync. Will try again.");
    expect(find.textContaining('Last synced'), findsNothing);

    h.cloudSync.emit(const SyncStatus(SyncPhase.clockWrong));
    await settle(tester);
    expect(
      statusText(tester),
      "Can't sync: this device's date and time are wrong.",
    );

    h.cloudSync.emit(SyncStatus(SyncPhase.idle, lastSynced: now));
    await settle(tester);
    expect(statusText(tester), 'Synced');
    expect(find.text('Last synced just now'), findsOneWidget);
    await tester.tap(syncNow);
    await settle(tester);
    expect(h.cloudSync.syncNowCalls, 1);
  });

  uiTest('signed out shows no sync status', (tester) async {
    await pumpAccount(tester);
    expect(key('account.syncStatus'), findsNothing);
    expect(key('account.syncNow'), findsNothing);
  });

  uiTest('log out with unsent changes asks first; Cancel keeps you signed '
      'in', (tester) async {
    await signedIn();
    h.cloudSync.unsent = true;
    await pumpAccount(tester);

    await tester.tap(key('account.logOut'));
    await settle(tester);
    // It tried to upload first; still unsent (offline), so it asks.
    expect(h.cloudSync.syncNowCalls, 1);
    expect(
      find.text(
        "Some changes on this device haven't been uploaded yet. Log out "
        'anyway?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.accounts.state, isA<SignedIn>());
    expect(h.accountBackend.calls, isNot(contains('logOut')));

    await tester.tap(key('account.logOut'));
    await settle(tester);
    await tester.tap(key('account.confirmLogOut'));
    await settle(tester);
    expect(h.accounts.state, isA<SignedOut>());
    expect(find.text('Signed out'), findsOneWidget);
  });

  uiTest('log out once everything is uploaded does not ask', (tester) async {
    await signedIn();
    h.cloudSync.unsent = true;
    // The upload before logging out gets everything up.
    h.cloudSync.onSyncNow = () => h.cloudSync.unsent = false;
    await pumpAccount(tester);

    await tester.tap(key('account.logOut'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.accounts.state, isA<SignedOut>());
  });

  uiTest('logging in as a different account asks Merge / Start empty', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    const question =
        'This device has a library from another account. Merge it into '
        'this account, or start empty?';

    // Asked before the app is up: waits for it, then asks.
    bool? answer;
    unawaited(askMergeOrStartEmpty(navigator).then((v) => answer = v));
    await tester.pump();
    expect(answer, isNull);

    await pumpAccount(tester, navigatorKey: navigator);
    expect(find.text(question), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    // Not dismissed by tapping outside or Back: it needs an answer.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.text(question), findsOneWidget);
    expect(answer, isNull);

    await tester.tap(find.text('Start empty'));
    await settle(tester);
    expect(find.text(question), findsNothing);
    expect(answer, isFalse);

    unawaited(askMergeOrStartEmpty(navigator).then((v) => answer = v));
    await settle(tester);
    await tester.tap(find.text('Merge'));
    await settle(tester);
    expect(answer, isTrue);
  });
}
