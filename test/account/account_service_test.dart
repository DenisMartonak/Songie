import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:songies/account/account_service.dart';

import 'fake_account_backend.dart';

Matcher _throwsAccount(AccountError e) =>
    throwsA(isA<AccountException>().having((x) => x.error, 'error', e));

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 30)));

void main() {
  late FakeAccountBackend backend;
  late AccountService service;

  setUp(() {
    backend = FakeAccountBackend();
    service = AccountService(backend);
  });

  tearDown(() => service.dispose());

  Future<void> signedInAs(String email, String username) async {
    await service.signUp(email, 'password1', username);
    await service.verifySignup(email, backend.goodCode);
  }

  test('error messages are the exact copy', () {
    expect(AccountError.wrongCredentials.message, 'Wrong email or password.');
    expect(
      AccountError.emailTaken.message,
      'That email already has an account. Log in, or reset your password.',
    );
    expect(AccountError.usernameTaken.message, 'That username is taken.');
    expect(
      AccountError.usernameJustTaken.message,
      'That username was just taken.',
    );
    expect(AccountError.badCode.message, 'That code is wrong or has expired.');
    expect(
      AccountError.offline.message,
      "Couldn't reach the server. Check your connection.",
    );
    for (final e in AccountError.values) {
      expect(e.message, isNotEmpty);
    }
  });

  test('sign up returns needsCode and lowercases the username', () async {
    final step = await service.signUp('a@b.c', 'password1', ' Den_Cho ');
    expect(step, AuthStep.needsCode);
    expect(backend.takenUsernames, contains('den_cho'));
    expect(service.state, isA<SignedOut>());
  });

  test('sign up with a taken email gives emailTaken; a race gives usernameJustTaken', () async {
    await service.signUp('a@b.c', 'password1', 'first');
    await expectLater(
      service.signUp('a@b.c', 'password1', 'second'),
      _throwsAccount(AccountError.emailTaken),
    );

    // Free when typed, taken by someone else at submit.
    backend.raceTakes = 'racer';
    await expectLater(
      service.signUp('x@y.z', 'password1', 'racer'),
      _throwsAccount(AccountError.usernameJustTaken),
    );
    // Nothing half-created.
    expect(backend.users.containsKey('x@y.z'), isFalse);
    expect(service.state, isA<SignedOut>());

    // A server error with the name still free stays unknown.
    backend.raceTakes = null;
    backend.signUpError = AccountError.unknown;
    await expectLater(
      service.signUp('q@y.z', 'password1', 'freename'),
      _throwsAccount(AccountError.unknown),
    );
  });

  test(
    'log in with an unconfirmed email asks for the code; a good code signs in',
    () async {
      await service.signUp('a@b.c', 'password1', 'den');
      expect(await service.logIn('a@b.c', 'password1'), AuthStep.needsCode);
      expect(service.state, isA<SignedOut>());

      await service.resendSignup('a@b.c');
      expect(backend.calls, contains('resendSignup'));

      await service.verifySignup('a@b.c', backend.goodCode);
      final s = service.state;
      expect(s, isA<SignedIn>());
      expect((s as SignedIn).profile.username, 'den');
      expect(s.profile.email, 'a@b.c');

      await service.logOut();
      expect(await service.logIn('a@b.c', 'password1'), AuthStep.done);
      expect(service.state, isA<SignedIn>());
    },
  );

  test('wrong password gives wrongCredentials', () async {
    await signedInAs('a@b.c', 'den');
    await service.logOut();
    await expectLater(
      service.logIn('a@b.c', 'nope-nope'),
      _throwsAccount(AccountError.wrongCredentials),
    );
  });

  test('wrong code gives badCode; offline gives offline', () async {
    await service.signUp('a@b.c', 'password1', 'den');
    await expectLater(
      service.verifySignup('a@b.c', '000000'),
      _throwsAccount(AccountError.badCode),
    );
    backend.everythingError = AccountError.offline;
    await expectLater(
      service.verifySignup('a@b.c', backend.goodCode),
      _throwsAccount(AccountError.offline),
    );
    await expectLater(
      service.logIn('a@b.c', 'password1'),
      _throwsAccount(AccountError.offline),
    );
    expect(service.state, isA<SignedOut>());
  });

  test('forgotten password: a code and a new password sign in', () async {
    await signedInAs('a@b.c', 'den');
    await service.logOut();
    await service.sendReset('a@b.c');
    await expectLater(
      service.resetPassword('a@b.c', '000000', 'newpassword'),
      _throwsAccount(AccountError.badCode),
    );
    await service.resetPassword('a@b.c', backend.goodCode, 'newpassword');
    expect(service.state, isA<SignedIn>());
  });

  test(
    'states go SignedOut -> SignedIn(profile) -> SignedOut on log out',
    () async {
      final seen = <AccountState>[];
      final sub = service.states.listen(seen.add);
      await pumpEventQueue();
      await signedInAs('a@b.c', 'den');
      await service.logOut();
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.map((s) => s.runtimeType), [SignedOut, SignedIn, SignedOut]);
      expect((seen[1] as SignedIn).profile.username, 'den');
    },
  );

  test('a session restored by the backend signs in; offline profile load stays signed out', () async {
    await service.signUp('a@b.c', 'password1', 'den');
    final id = backend.users['a@b.c']!.id;

    backend.everythingError = AccountError.offline;
    backend.emitUser(id);
    await pumpEventQueue();
    expect(service.state, isA<SignedOut>());

    // Back online: the next auth event (a token refresh) loads the profile.
    backend.everythingError = null;
    backend.emitUser(id);
    await pumpEventQueue();
    expect(service.state, isA<SignedIn>());
  });

  test('changeUsername: taken name gives usernameTaken; a free one updates the profile', () async {
    await service.signUp('o@b.c', 'password1', 'other');
    await signedInAs('a@b.c', 'den');
    await expectLater(
      service.changeUsername('Other'),
      _throwsAccount(AccountError.usernameTaken),
    );
    await service.changeUsername('New.Name');
    expect((service.state as SignedIn).profile.username, 'new.name');
  });

  test('changeAvatar uploads, then updates the path, then deletes the old file; an upload failure leaves the old path', () async {
    await signedInAs('a@b.c', 'den');
    final id = (service.state as SignedIn).profile.id;

    await service.changeAvatar(_png());
    final first = (service.state as SignedIn).profile.avatarPath!;
    expect(first, matches(RegExp('^$id/\\d+\\.jpg\$')));
    expect(backend.files, {first});
    expect((service.state as SignedIn).profile.avatarUrl, isNotNull);

    backend.calls.clear();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await service.changeAvatar(_png());
    final second = (service.state as SignedIn).profile.avatarPath!;
    expect(second, isNot(first));
    expect(backend.calls.where((c) => c != 'loadProfile'), [
      'uploadAvatar',
      'setAvatarPath',
      'deleteAvatarFiles',
    ]);
    expect(backend.files, {second});

    backend.uploadError = AccountError.offline;
    await expectLater(
      service.changeAvatar(_png()),
      _throwsAccount(AccountError.offline),
    );
    expect(backend.profiles[id]!.avatarPath, second);
    expect((service.state as SignedIn).profile.avatarPath, second);
    expect(backend.files, {second});
  });

  test(
    'changeAvatar with bytes that are not an image throws FormatException',
    () async {
      await signedInAs('a@b.c', 'den');
      await expectLater(
        service.changeAvatar(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(backend.calls, isNot(contains('uploadAvatar')));
    },
  );

  test('removeAvatar clears the path, then deletes the files', () async {
    await signedInAs('a@b.c', 'den');
    final id = (service.state as SignedIn).profile.id;
    await service.changeAvatar(_png());
    await service.removeAvatar();
    expect(backend.profiles[id]!.avatarPath, isNull);
    expect((service.state as SignedIn).profile.avatarUrl, isNull);
    expect(backend.files, isEmpty);
  });

  test(
    'deleteAccount deletes files, calls delete_my_account, ends SignedOut',
    () async {
      await signedInAs('a@b.c', 'den');
      await service.changeAvatar(_png());
      backend.calls.clear();
      await service.deleteAccount();
      expect(backend.calls, ['deleteAvatarFiles', 'deleteMyAccount', 'logOut']);
      expect(backend.files, isEmpty);
      expect(service.state, isA<SignedOut>());
    },
  );

  test('profile actions while signed out throw', () async {
    await expectLater(service.changeUsername('abc'), throwsStateError);
    await expectLater(service.deleteAccount(), throwsStateError);
  });
}
