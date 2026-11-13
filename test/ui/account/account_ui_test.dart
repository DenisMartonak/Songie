import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:songies/account/account_service.dart';
import 'package:songies/account/username.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/ui/account/account_section.dart';
import 'package:songies/ui/account/avatar.dart';
import 'package:songies/ui/account/profile_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../../account/fake_account_backend.dart';
import '../../account/image_fixtures.dart';
import '../../helpers/ui_harness.dart';

/// Holds log-ins until [gate] completes.
class _SlowBackend extends FakeAccountBackend {
  Completer<void>? gate;

  @override
  Future<String> logIn(String email, String password) async {
    await gate?.future;
    return super.logIn(email, password);
  }
}

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 30)));

void main() {
  late UiHarness h;
  late Directory tmp;
  AvatarPick? pick;

  setUp(() async {
    h = await UiHarness.create();
    tmp = Directory.systemTemp.createTempSync('songies_account_');
    h.paths = AppPaths.at(tmp);
    await h.paths!.ensureCreated();
    pick = null;
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// The profile page with a top-bar avatar above it, as the shell shows it.
  Future<void> pumpAccount(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/profile',
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          avatarPickerProvider.overrideWithValue(() async => pick),
        ],
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(
              body: Column(
                children: [
                  AccountAvatar(size: 28, key: Key('top.avatar')),
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

  /// A confirmed account, signed in before the app is pumped.
  Future<void> signedIn(String email, String username) async {
    await h.accounts.signUp(email, 'password1', username);
    await h.accounts.verifySignup(email, h.accountBackend.goodCode);
  }

  Finder key(String k) => find.byKey(Key(k));
  Finder inTop(Finder f) => find.descendant(of: key('top.avatar'), matching: f);
  Finder inSection(Finder f) =>
      find.descendant(of: find.byType(ProfilePage), matching: f);

  /// Types into a field and rebuilds (enterText alone doesn't).
  Future<void> type(WidgetTester tester, Finder f, String text) async {
    await tester.enterText(f, text);
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
  }

  uiTest('sign up -> code screen -> signed in shows username, email and '
      'picture', (tester) async {
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.signUp'));
    expect(find.byType(Dialog), findsOneWidget);

    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.username'), 'den');
    await type(tester, key('auth.password'), 'password1');
    await tester.pump(const Duration(milliseconds: 500));
    await tapAndSettle(tester, key('auth.submit'));

    // The code screen.
    expect(find.textContaining('den@x.com'), findsOneWidget);
    expect(key('auth.code'), findsOneWidget);
    await type(tester, key('auth.code'), '000000');
    await tapAndSettle(tester, key('auth.submit'));
    expect(find.text(AccountError.badCode.message), findsOneWidget);

    await type(tester, key('auth.code'), h.accountBackend.goodCode);
    await tapAndSettle(tester, key('auth.submit'));

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Signed in'), findsOneWidget);
    expect(inSection(find.text('den')), findsOneWidget);
    expect(inSection(find.text('den@x.com')), findsOneWidget);
    // No picture yet: the first letter.
    expect(inSection(find.text('D')), findsOneWidget);
    expect(inTop(find.text('D')), findsOneWidget);
    expect(inSection(find.text('Change username')), findsOneWidget);
    expect(key('profile.avatar'), findsOneWidget);
    expect(inSection(find.text('Log out')), findsOneWidget);
    expect(inSection(find.text('Delete account')), findsOneWidget);
    expect(key('account.signUp'), findsNothing);

    await tapAndSettle(tester, key('account.logOut'));
    expect(find.text('Signed out'), findsOneWidget);
    expect(key('account.signUp'), findsOneWidget);
    expect(inTop(find.byIcon(Icons.person_outline_rounded)), findsOneWidget);
  });

  /// Someone else signed up with [email] first and never confirmed.
  void squatted(String email) {
    final b = h.accountBackend;
    b.users[email] = (password: 'squatter1', id: 'u9', confirmed: false);
    b.profiles['u9'] = (username: 'squatter', avatarPath: null);
    b.emails['u9'] = email;
    b.takenUsernames.add('squatter');
  }

  Future<void> signUpTo(WidgetTester tester, String username) async {
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.signUp'));
    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.username'), username);
    await type(tester, key('auth.password'), 'owner-pass1');
    await tester.pump(const Duration(milliseconds: 500));
    await tapAndSettle(tester, key('auth.submit'));
    expect(key('auth.code'), findsOneWidget);
    await type(tester, key('auth.code'), h.accountBackend.goodCode);
  }

  uiTest('re-signing up an unconfirmed email ends with the typed password and '
      'username', (tester) async {
    squatted('den@x.com');
    await signUpTo(tester, 'owner');
    await tapAndSettle(tester, key('auth.submit'));
    expect(find.text('Signed in'), findsOneWidget);
    expect(inSection(find.text('owner')), findsOneWidget);
    expect(h.accountBackend.users['den@x.com']!.password, 'owner-pass1');
  });

  uiTest('a typed username taken meanwhile keeps the existing one and says '
      'so', (tester) async {
    squatted('den@x.com');
    await signUpTo(tester, 'owner');
    h.accountBackend.takenUsernames.add('owner');
    await tapAndSettle(tester, key('auth.submit'));
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.text(
        'Your account uses the username @squatter. You can change it in '
        'Settings.',
      ),
      findsOneWidget,
    );
    expect(inSection(find.text('squatter')), findsOneWidget);
    expect(h.accountBackend.users['den@x.com']!.password, 'owner-pass1');
  });

  uiTest('a password that cannot be set after the code signs out and opens '
      'log-in with the error', (tester) async {
    squatted('den@x.com');
    await signUpTo(tester, 'owner');
    h.accountBackend.setPasswordError = AccountError.offline;
    await tapAndSettle(tester, key('auth.submit'));
    expect(key('auth.code'), findsNothing);
    expect(key('auth.forgot'), findsOneWidget);
    expect(
      tester.widget<Text>(key('auth.error')).data,
      AccountError.offline.message,
    );
    expect(h.accounts.state, isA<SignedOut>());
    expect(h.accountBackend.calls, contains('logOut'));
    // The email kept for logging in again.
    expect(
      tester.widget<TextField>(key('auth.email')).controller!.text,
      'den@x.com',
    );
  });

  uiTest('the username field lowercases, shows the rule hint and "That '
      'username is taken." while typing', (tester) async {
    h.accountBackend.takenUsernames.add('taken');
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.signUp'));

    await type(tester, key('auth.username'), 'DeN');
    await tester.pump();
    expect(
      tester.widget<TextField>(key('auth.username')).controller!.text,
      'den',
    );
    expect(find.text(kUsernameHint), findsOneWidget);
    expect(find.text(kPasswordHint), findsOneWidget);

    await type(tester, key('auth.username'), 'Taken');
    await tester.pump(const Duration(milliseconds: 200));
    await flush(tester);
    // Not asked yet: still typing.
    expect(find.text('That username is taken.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    expect(find.text('That username is taken.'), findsOneWidget);

    await type(tester, key('auth.username'), 'free');
    await tester.pump(const Duration(milliseconds: 500));
    await flush(tester);
    expect(find.text('That username is taken.'), findsNothing);
    expect(find.text(kUsernameHint), findsOneWidget);
  });

  uiTest('each AccountError shows its exact message', (tester) async {
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.logIn'));
    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.password'), 'password1');
    await tester.pump();

    for (final e in AccountError.values) {
      if (e == AccountError.emailNotConfirmed) continue;
      h.accountBackend.everythingError = e;
      await tapAndSettle(tester, key('auth.submit'));
      expect(
        tester.widget<Text>(key('auth.error')).data,
        e.message,
        reason: e.name,
      );
    }

    // Not confirmed yet: the code screen, saying why.
    h.accountBackend.everythingError = null;
    await h.accounts.signUp('den@x.com', 'password1', 'den');
    await tapAndSettle(tester, key('auth.submit'));
    expect(find.text(AccountError.emailNotConfirmed.message), findsOneWidget);
    expect(key('auth.code'), findsOneWidget);
  });

  uiTest('forgot password -> code + new password -> signed in', (tester) async {
    await signedIn('den@x.com', 'den');
    await h.accounts.logOut();
    await pumpAccount(tester);

    await tapAndSettle(tester, key('account.logIn'));
    await tapAndSettle(tester, key('auth.forgot'));
    await type(tester, key('auth.email'), 'den@x.com');
    await tapAndSettle(tester, key('auth.submit'));
    expect(h.accountBackend.calls.last, 'sendReset');

    await type(tester, key('auth.code'), h.accountBackend.goodCode);
    await type(tester, key('auth.password'), 'short');
    await tester.pump();
    // Too short: Continue stays off.
    expect(tester.widget<FilledButton>(key('auth.submit')).onPressed, isNull);
    await type(tester, key('auth.password'), 'newpassword');
    await tapAndSettle(tester, key('auth.submit'));

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Signed in'), findsOneWidget);
    expect(inSection(find.text('den')), findsOneWidget);
    expect(h.accountBackend.users['den@x.com']!.password, 'newpassword');
  });

  uiTest('the code step can go back to sign-up with the fields kept, and '
      '"Send a new code" resends', (tester) async {
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.signUp'));
    await type(tester, key('auth.email'), 'den@x.con');
    await type(tester, key('auth.username'), 'den');
    await type(tester, key('auth.password'), 'password1');
    await tester.pump(const Duration(milliseconds: 500));
    await tapAndSettle(tester, key('auth.submit'));
    expect(key('auth.code'), findsOneWidget);

    expect(find.text('Send a new code'), findsOneWidget);
    await tapAndSettle(tester, key('auth.resend'));
    expect(h.accountBackend.calls.last, 'resendSignup');
    expect(find.text('We sent a new code.'), findsOneWidget);

    await tapAndSettle(tester, key('auth.differentEmail'));
    expect(find.text('Use a different email'), findsNothing);
    expect(key('auth.code'), findsNothing);
    String text(String k) => tester.widget<TextField>(key(k)).controller!.text;
    expect(text('auth.email'), 'den@x.con');
    expect(text('auth.username'), 'den');
    expect(text('auth.password'), 'password1');
    // Why the same username may be refused for now.
    expect(
      find.text(
        'Your first sign-up holds that username for an hour. Pick another '
        'one, or try again later.',
      ),
      findsOneWidget,
    );
  });

  uiTest('logging in unconfirmed sends a new code and opens the code step; a '
      'refused resend shows inline', (tester) async {
    await h.accounts.signUp('den@x.com', 'password1', 'den');
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.logIn'));
    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.password'), 'password1');
    await tapAndSettle(tester, key('auth.submit'));
    expect(key('auth.code'), findsOneWidget);
    expect(h.accountBackend.calls.sublist(h.accountBackend.calls.length - 2), [
      'logIn',
      'resendSignup',
    ]);
    expect(key('auth.error'), findsNothing);

    // Again, with the resend refused: still the code step, with the error.
    await tapAndSettle(tester, key('auth.cancel'));
    await tapAndSettle(tester, key('account.logIn'));
    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.password'), 'password1');
    h.accountBackend.resendError = AccountError.tooManyRequests;
    await tapAndSettle(tester, key('auth.submit'));
    expect(key('auth.code'), findsOneWidget);
    expect(
      tester.widget<Text>(key('auth.error')).data,
      AccountError.tooManyRequests.message,
    );
  });

  uiTest('a refused new password clears the used-up code and offers "Send a '
      'new code"', (tester) async {
    await signedIn('den@x.com', 'den');
    await h.accounts.logOut();
    await pumpAccount(tester);
    await tapAndSettle(tester, key('account.logIn'));
    await tapAndSettle(tester, key('auth.forgot'));
    await type(tester, key('auth.email'), 'den@x.com');
    await tapAndSettle(tester, key('auth.submit'));

    h.accountBackend.updatePasswordError = AccountError.samePassword;
    await type(tester, key('auth.code'), h.accountBackend.goodCode);
    await type(tester, key('auth.password'), 'password1');
    await tapAndSettle(tester, key('auth.submit'));
    expect(
      tester.widget<Text>(key('auth.error')).data,
      AccountError.samePassword.message,
    );
    expect(
      find.text('Send a new code, then try another password.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(key('auth.code')).controller!.text, '');
    expect(tester.widget<FilledButton>(key('auth.submit')).onPressed, isNull);

    h.accountBackend.updatePasswordError = null;
    h.accountBackend.calls.clear();
    await tapAndSettle(tester, key('auth.resend'));
    expect(h.accountBackend.calls, ['sendReset']);
    expect(find.text('We sent a new code.'), findsOneWidget);

    await type(tester, key('auth.code'), h.accountBackend.goodCode);
    await type(tester, key('auth.password'), 'newpassword');
    await tapAndSettle(tester, key('auth.submit'));
    expect(find.text('Signed in'), findsOneWidget);
    expect(h.accountBackend.users['den@x.com']!.password, 'newpassword');
  });

  uiTest('forms autofill as a group, passwords can be shown, and Enter in the '
      'code field submits', (tester) async {
    await pumpAccount(tester);
    List<String>? hints(String k) =>
        tester.widget<TextField>(key(k)).autofillHints?.toList();
    // Log-in: password managers file the email as the username.
    await tapAndSettle(tester, key('account.logIn'));
    expect(hints('auth.email'), [AutofillHints.email, AutofillHints.username]);
    expect(hints('auth.password'), [AutofillHints.password]);
    await tapAndSettle(tester, key('auth.cancel'));

    await tapAndSettle(tester, key('account.signUp'));
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(hints('auth.email'), [AutofillHints.email]);
    expect(hints('auth.username'), [AutofillHints.newUsername]);
    expect(hints('auth.password'), [AutofillHints.newPassword]);

    bool hidden() => tester.widget<TextField>(key('auth.password')).obscureText;
    expect(hidden(), isTrue);
    await tapAndSettle(tester, key('auth.showPassword'));
    expect(hidden(), isFalse);
    await tapAndSettle(tester, key('auth.showPassword'));
    expect(hidden(), isTrue);

    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.username'), 'den');
    await type(tester, key('auth.password'), 'password1');
    await tester.pump(const Duration(milliseconds: 500));
    await tapAndSettle(tester, key('auth.submit'));
    expect(hints('auth.code'), [AutofillHints.oneTimeCode]);

    await tester.enterText(key('auth.code'), h.accountBackend.goodCode);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Signed in'), findsOneWidget);
  });

  uiTest('change username updates the section and the top-bar avatar', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    h.accountBackend.takenUsernames.add('taken');
    await pumpAccount(tester);
    expect(inTop(find.text('D')), findsOneWidget);

    // Change username: a taken one is refused inline.
    await tapAndSettle(tester, key('account.changeUsername'));
    await type(tester, key('account.newUsername'), 'Taken');
    await tester.pump();
    expect(
      tester.widget<TextField>(key('account.newUsername')).controller!.text,
      'taken',
    );
    await tapAndSettle(tester, key('account.saveUsername'));
    expect(find.text('That username is taken.'), findsWidgets);
    expect(find.byType(AlertDialog), findsOneWidget);

    await type(tester, key('account.newUsername'), 'neo');
    await tester.pump(const Duration(milliseconds: 500));
    await tapAndSettle(tester, key('account.saveUsername'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Username changed'), findsOneWidget);
    expect(inSection(find.text('neo')), findsOneWidget);
    expect(inTop(find.text('N')), findsOneWidget);
  });

  /// Opens the picture viewer from the profile's picture.
  Future<void> openViewer(WidgetTester tester) async {
    await tapAndSettle(tester, key('profile.avatar'));
    expect(key('profile.pictureViewer'), findsOneWidget);
  }

  /// Taps [f] and waits (on the real clock) until [done] holds.
  Future<void> tapUntil(
    WidgetTester tester,
    Finder f,
    bool Function() done,
  ) async {
    await tester.tap(f);
    await tester.pump();
    for (var i = 0; i < 20 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await settle(tester);
  }

  uiTest('tapping the picture opens it large with Change and Remove', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    await pumpAccount(tester);
    await openViewer(tester);
    // No picture yet: only Change.
    expect(key('profile.changePicture'), findsOneWidget);
    expect(key('profile.removePicture'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('profile.pictureLarge'))).width,
      240,
    );

    // Change picture: the viewer closes and every avatar shows it.
    pick = (size: 100, bytes: _png());
    await tapUntil(
      tester,
      key('profile.changePicture'),
      () => h.accountBackend.files.isNotEmpty,
    );
    expect(key('profile.pictureViewer'), findsNothing);
    expect(find.text('Picture updated'), findsOneWidget);
    expect(inSection(key('account.avatar.image')), findsOneWidget);
    expect(inTop(key('account.avatar.image')), findsOneWidget);
    final image = tester.widget<Image>(inTop(key('account.avatar.image')));
    final provider = image.image as ResizeImage;
    expect(provider.width, 28);
    expect(
      (provider.imageProvider as NetworkImage).url,
      startsWith('https://x/'),
    );

    // Remove picture: back to the initial.
    await openViewer(tester);
    expect(key('profile.removePicture'), findsOneWidget);
    await tapAndSettle(tester, key('profile.removePicture'));
    expect(key('profile.pictureViewer'), findsNothing);
    expect(find.text('Picture removed'), findsOneWidget);
    expect(inSection(key('account.avatar.image')), findsNothing);
    expect(inTop(key('account.avatar.image')), findsNothing);
    expect(inTop(find.text('D')), findsOneWidget);
  });

  uiTest('a picture too big shows the error and keeps the viewer open', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    await pumpAccount(tester);
    await openViewer(tester);

    // Too big a file is refused before it is read.
    expect(maxAvatarSourceBytes, 10 * 1024 * 1024);
    pick = (size: 11 * 1024 * 1024, bytes: null);
    await tapAndSettle(tester, key('profile.changePicture'));
    expect(
      tester.widget<Text>(key('profile.pictureError')).data,
      'That image is too big',
    );
    expect(key('profile.pictureViewer'), findsOneWidget);
    expect(h.accountBackend.calls, isNot(contains('uploadAvatar')));

    // So is a small file with too many pixels; the earlier message clears
    // while it is read.
    pick = (size: 100, bytes: hugePngHeader(8000, 6000));
    await tester.tap(key('profile.changePicture'));
    await tester.pump();
    expect(key('profile.pictureError'), findsNothing);
    for (
      var i = 0;
      i < 20 && key('profile.pictureError').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await settle(tester);
    expect(
      tester.widget<Text>(key('profile.pictureError')).data,
      'That image is too big',
    );
    expect(key('profile.pictureViewer'), findsOneWidget);
    expect(h.accountBackend.calls, isNot(contains('uploadAvatar')));
  });

  uiTest('delete account asks first, then returns to signed out', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    await pumpAccount(tester);

    await tapAndSettle(tester, key('account.delete'));
    expect(
      find.text(
        'Delete your account? Your username, picture and synced library in '
        'the cloud are removed, and your other devices stop syncing. Your '
        'music on this device stays.',
      ),
      findsOneWidget,
    );
    await tapAndSettle(tester, find.text('Cancel'));
    expect(h.accountBackend.calls, isNot(contains('deleteMyAccount')));
    expect(inSection(find.text('den')), findsOneWidget);

    await tapAndSettle(tester, key('account.delete'));
    await tapAndSettle(tester, key('account.confirmDelete'));
    expect(h.accountBackend.calls, contains('deleteMyAccount'));
    expect(find.text('Account deleted'), findsOneWidget);
    expect(key('account.signUp'), findsOneWidget);
    expect(inTop(find.byIcon(Icons.person_outline_rounded)), findsOneWidget);
  });

  uiTest('a picture change that fails offline says so in the viewer', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    await pumpAccount(tester);
    h.accountBackend.everythingError = AccountError.offline;
    pick = (size: 100, bytes: _png());
    await openViewer(tester);
    await tapUntil(
      tester,
      key('profile.changePicture'),
      () => key('profile.pictureError').evaluate().isNotEmpty,
    );
    expect(
      tester.widget<Text>(key('profile.pictureError')).data,
      AccountError.offline.message,
    );
    expect(key('profile.pictureViewer'), findsOneWidget);
    expect(inSection(find.text('den')), findsOneWidget);
  });

  uiTest('a delete that fails offline shows the error on the page', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    await pumpAccount(tester);
    h.accountBackend.everythingError = AccountError.offline;
    await tapAndSettle(tester, key('account.delete'));
    await tapAndSettle(tester, find.text('Delete'));
    expect(
      tester.widget<Text>(key('account.error')).data,
      AccountError.offline.message,
    );
  });

  uiTest('showing the section loads a session restored while offline', (
    tester,
  ) async {
    await signedIn('den@x.com', 'den');
    // A restart offline: the session is there, the profile isn't.
    h.accountBackend.profileError = AccountError.offline;
    h.accountBackend.emitUser(null);
    await tester.pump();
    h.accountBackend.emitUser('u1');
    await tester.pump();
    expect(h.accounts.state, isA<SignedOut>());
    h.accountBackend.profileError = null;

    await pumpAccount(tester);
    expect(inSection(find.text('den')), findsOneWidget);
  });

  uiTest('phone width opens auth screens as full pages, desktop as dialogs', (
    tester,
  ) async {
    await pumpAccount(tester, width: 400);
    await tapAndSettle(tester, key('account.logIn'));
    expect(find.byType(Dialog), findsNothing);
    final route = ModalRoute.of(tester.element(key('auth.email')))!;
    expect(route, isA<MaterialPageRoute<void>>());
    expect((route as MaterialPageRoute<void>).fullscreenDialog, isTrue);
    // On the root navigator.
    expect(
      Navigator.of(tester.element(key('auth.email'))),
      tester.state<NavigatorState>(
        find.byType(Navigator, skipOffstage: false).first,
      ),
    );
    await tapAndSettle(tester, key('auth.cancel'));
    expect(key('auth.email'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpAccount(tester, width: 1000);
    await tapAndSettle(tester, key('account.logIn'));
    expect(
      find.ancestor(of: key('auth.email'), matching: find.byType(Dialog)),
      findsOneWidget,
    );
  });

  uiTest('while logging in the screen cannot be closed and the buttons are '
      'off', (tester) async {
    final slow = _SlowBackend()..gate = Completer<void>();
    h.accountBackend = slow;
    await signedIn('den@x.com', 'den');
    await h.accounts.logOut();
    await pumpAccount(tester);

    await tapAndSettle(tester, key('account.logIn'));
    await type(tester, key('auth.email'), 'den@x.com');
    await type(tester, key('auth.password'), 'password1');
    await tester.tap(key('auth.submit'));
    await tester.pump();
    expect(tester.widget<FilledButton>(key('auth.submit')).onPressed, isNull);
    expect(tester.widget<TextButton>(key('auth.cancel')).onPressed, isNull);

    // Back and a tap outside do nothing.
    final navigator = Navigator.of(tester.element(key('auth.email')));
    await navigator.maybePop();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(key('auth.email'), findsOneWidget);

    slow.gate!.complete();
    await settle(tester);
    expect(key('auth.email'), findsNothing);
    expect(find.text('Signed in'), findsOneWidget);
  });
}
