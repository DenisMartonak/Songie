import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:image/image.dart' as img;
import 'package:songies/core/connectivity.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/sync/cloud/cloud_remote.dart';

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
    expect(
      AccountError.samePassword.message,
      'Choose a password different from your old one.',
    );
    expect(AccountError.weakPassword.message, 'That password is too weak.');
    expect(
      AccountError.tooManyRequests.message,
      'Too many tries. Wait a while and try again.',
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
    await signedInAs('a@b.c', 'first');
    await service.logOut();
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

  group('confirming a sign-up sets what was typed at sign-up', () {
    /// Someone else signed up with this email first and never confirmed:
    /// gotrue keeps their password and username on the owner's re-sign-up.
    void squatted(String email) {
      backend.users[email] = (
        password: 'squatter1',
        id: 'u9',
        confirmed: false,
      );
      backend.profiles['u9'] = (username: 'squatter', avatarPath: null);
      backend.emails['u9'] = email;
      backend.takenUsernames.add('squatter');
    }

    test('a squatted sign-up gets the typed password and username', () async {
      squatted('a@b.c');
      expect(
        await service.signUp('a@b.c', 'owner-pass1', ' Owner '),
        AuthStep.needsCode,
      );
      final kept = await service.verifySignup(
        'a@b.c',
        backend.goodCode,
        password: 'owner-pass1',
        username: ' Owner ',
      );
      expect(kept, isNull);
      expect(
        backend.calls.where((c) => c == 'setPassword' || c == 'updateUsername'),
        ['setPassword', 'updateUsername'],
      );
      expect(backend.users['a@b.c']!.password, 'owner-pass1');
      final s = service.state;
      expect(s, isA<SignedIn>());
      expect((s as SignedIn).profile.username, 'owner');

      await service.logOut();
      await expectLater(
        service.logIn('a@b.c', 'squatter1'),
        _throwsAccount(AccountError.wrongCredentials),
      );
      expect(await service.logIn('a@b.c', 'owner-pass1'), AuthStep.done);
    });

    test('a typed username taken meanwhile keeps the existing one', () async {
      squatted('a@b.c');
      await service.signUp('a@b.c', 'owner-pass1', 'owner');
      backend.takenUsernames.add('owner');
      final kept = await service.verifySignup(
        'a@b.c',
        backend.goodCode,
        password: 'owner-pass1',
        username: 'owner',
      );
      expect(kept, 'squatter');
      final s = service.state;
      expect(s, isA<SignedIn>());
      expect((s as SignedIn).profile.username, 'squatter');
    });

    test('an unchanged password (same_password) counts as set', () async {
      await service.signUp('a@b.c', 'password1', 'den');
      final kept = await service.verifySignup(
        'a@b.c',
        backend.goodCode,
        password: 'password1',
        username: 'den',
      );
      expect(kept, isNull);
      expect(backend.calls, contains('setPassword'));
      expect(backend.calls, isNot(contains('updateUsername')));
      expect(backend.calls, isNot(contains('logOut')));
      expect(service.state, isA<SignedIn>());
    });

    test('a password that cannot be set logs out and throws', () async {
      squatted('a@b.c');
      await service.signUp('a@b.c', 'owner-pass1', 'owner');
      backend.setPasswordError = AccountError.offline;
      await expectLater(
        service.verifySignup(
          'a@b.c',
          backend.goodCode,
          password: 'owner-pass1',
          username: 'owner',
        ),
        _throwsAccount(AccountError.offline),
      );
      expect(backend.calls, contains('logOut'));
      expect(backend.calls, isNot(contains('updateUsername')));
      await pumpEventQueue();
      expect(service.state, isA<SignedOut>());
      expect(backend.currentUser, isNull);
    });

    test(
      'while the password is being set, nothing counts as signed in',
      () async {
        squatted('a@b.c');
        await service.signUp('a@b.c', 'owner-pass1', 'owner');
        final seen = <AccountState>[];
        final sub = service.states.listen(seen.add);
        backend.setPasswordDelay = const Duration(milliseconds: 50);
        backend.setPasswordError = AccountError.offline;
        await expectLater(
          service.verifySignup(
            'a@b.c',
            backend.goodCode,
            password: 'owner-pass1',
            username: 'owner',
          ),
          _throwsAccount(AccountError.offline),
        );
        await pumpEventQueue();
        await sub.cancel();
        expect(seen.whereType<SignedIn>(), isEmpty);
      },
    );

    test('confirming after a log-in sets nothing', () async {
      await service.signUp('a@b.c', 'password1', 'den');
      await service.logIn('a@b.c', 'password1');
      await service.verifySignup('a@b.c', backend.goodCode);
      expect(backend.calls, isNot(contains('setPassword')));
      expect(service.state, isA<SignedIn>());
    });
  });

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

  test('deleteAccount clears the picture, deletes files, calls '
      'delete_my_account, ends SignedOut', () async {
    await signedInAs('a@b.c', 'den');
    await service.changeAvatar(_png());
    final id = (service.state as SignedIn).profile.id;
    backend.calls.clear();
    await service.deleteAccount();
    expect(backend.calls, [
      'setAvatarPath',
      'deleteAvatarFiles',
      'deleteMyAccount',
      'logOut',
    ]);
    expect(backend.profiles[id]!.avatarPath, isNull);
    expect(backend.files, isEmpty);
    expect(service.state, isA<SignedOut>());
  });

  test('deleteAccount deletes the synced files before the account', () async {
    await service.dispose();
    service = AccountService(
      backend,
      deleteSyncFiles: (uid) async => backend.calls.add('deleteSyncFiles $uid'),
    );
    await signedInAs('a@b.c', 'den');
    final id = (service.state as SignedIn).profile.id;
    backend.calls.clear();
    await service.deleteAccount();
    expect(backend.calls, [
      'setAvatarPath',
      'deleteAvatarFiles',
      'deleteSyncFiles $id',
      'deleteMyAccount',
      'logOut',
    ]);
  });

  test('synced files that cannot be deleted keep the account', () async {
    await service.dispose();
    service = AccountService(
      backend,
      deleteSyncFiles: (_) async => throw const CloudOffline(),
    );
    await signedInAs('a@b.c', 'den');
    backend.calls.clear();
    await expectLater(
      service.deleteAccount(),
      _throwsAccount(AccountError.offline),
    );
    expect(backend.calls, isNot(contains('deleteMyAccount')));
    expect(service.state, isA<SignedIn>());
  });

  test('profile actions while signed out throw', () async {
    await expectLater(service.changeUsername('abc'), throwsStateError);
    await expectLater(service.deleteAccount(), throwsStateError);
  });

  test(
    'a refused new password stays signed out, without a SignedIn flash',
    () async {
      await signedInAs('a@b.c', 'den');
      await service.logOut();
      final seen = <AccountState>[];
      final sub = service.states.listen(seen.add);
      backend.updatePasswordError = AccountError.samePassword;
      await expectLater(
        service.resetPassword('a@b.c', backend.goodCode, 'password1'),
        _throwsAccount(AccountError.samePassword),
      );
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.whereType<SignedIn>(), isEmpty);
      expect(service.state, isA<SignedOut>());
    },
  );

  test('log in, verify or reset whose profile load fails logs out and throws offline', () async {
    await service.signUp('a@b.c', 'password1', 'den');
    backend.profileError = AccountError.offline;
    await expectLater(
      service.verifySignup('a@b.c', backend.goodCode),
      _throwsAccount(AccountError.offline),
    );
    expect(backend.calls.last, 'logOut');
    expect(service.state, isA<SignedOut>());

    backend.calls.clear();
    await expectLater(
      service.logIn('a@b.c', 'password1'),
      _throwsAccount(AccountError.offline),
    );
    expect(backend.calls, contains('logOut'));

    backend.calls.clear();
    await expectLater(
      service.resetPassword('a@b.c', backend.goodCode, 'newpassword'),
      _throwsAccount(AccountError.offline),
    );
    expect(backend.calls, contains('logOut'));
    await pumpEventQueue();
    expect(service.state, isA<SignedOut>());

    backend.profileError = null;
    await service.logIn('a@b.c', 'newpassword');
    expect(service.state, isA<SignedIn>());
  });

  test(
    'a restored session loads its profile when the network comes back',
    () async {
      final net = StreamController<NetworkKind>.broadcast();
      final s2 = AccountService(backend, network: net.stream);
      addTearDown(s2.dispose);
      await service.signUp('a@b.c', 'password1', 'den');
      final id = backend.users['a@b.c']!.id;

      backend.profileError = AccountError.offline;
      backend.emitUser(id);
      await pumpEventQueue();
      expect(s2.state, isA<SignedOut>());

      net.add(NetworkKind.offline);
      await pumpEventQueue();
      expect(s2.state, isA<SignedOut>());

      backend.profileError = null;
      net.add(NetworkKind.wifi);
      await pumpEventQueue();
      expect(s2.state, isA<SignedIn>());
      await net.close();
    },
  );

  test('refresh loads a restored session that could not load before', () async {
    await service.signUp('a@b.c', 'password1', 'den');
    final id = backend.users['a@b.c']!.id;
    backend.profileError = AccountError.offline;
    backend.emitUser(id);
    await pumpEventQueue();
    await expectLater(service.refresh(), _throwsAccount(AccountError.offline));
    backend.profileError = null;
    await service.refresh();
    expect(service.state, isA<SignedIn>());
    // Signed out: nothing to refresh.
    await service.logOut();
    await service.refresh();
    expect(service.state, isA<SignedOut>());
  });
}
