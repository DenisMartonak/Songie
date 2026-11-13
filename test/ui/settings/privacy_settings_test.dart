import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:songies/ui/settings/privacy_settings.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> signedIn() async {
    await h.accounts.signUp('me@x.com', 'password1', 'me');
    await h.accounts.verifySignup('me@x.com', h.accountBackend.goodCode);
    h.activityBackend.me = (h.accounts.state as SignedIn).profile.id;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [PrivacySettingsSection()]),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  bool on(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

  uiTest('both switches start on and save to the server', (tester) async {
    await signedIn();
    await pump(tester);
    expect(find.text('Privacy'), findsOneWidget);
    expect(on(tester, 'privacy.listening'), isTrue);
    expect(on(tester, 'privacy.top'), isTrue);
    await tester.tap(find.byKey(const Key('privacy.listening')));
    await settle(tester);
    expect(on(tester, 'privacy.listening'), isFalse);
    expect(
      await h.activityBackend.mySharing(),
      const Sharing(listening: false, top: true),
    );
    // Opened again, it shows what the server holds.
    await pump(tester);
    expect(on(tester, 'privacy.listening'), isFalse);
  });

  uiTest('a failed save flips the switch back and says so', (tester) async {
    await signedIn();
    await pump(tester);
    h.activityBackend.error = const FriendsException(FriendsError.offline);
    await tester.tap(find.byKey(const Key('privacy.top')));
    await settle(tester);
    expect(on(tester, 'privacy.top'), isTrue);
    expect(find.text("You're offline"), findsOneWidget);
  });

  uiTest('signed out it asks to log in', (tester) async {
    await pump(tester);
    expect(find.text('Log in to share with friends'), findsOneWidget);
    expect(find.byKey(const Key('privacy.listening')), findsNothing);
  });
}
