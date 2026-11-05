import 'dart:async';
import 'dart:typed_data';

import 'package:songies/account/account_backend.dart';

/// An in-memory [AccountBackend] that records calls. Set the `*Error` fields
/// to make the next matching call throw that [AccountError].
class FakeAccountBackend implements AccountBackend {
  final _ids = StreamController<String?>.broadcast();
  final calls = <String>[];

  /// email -> (password, user id, confirmed)
  final users = <String, ({String password, String id, bool confirmed})>{};
  final profiles = <String, ({String username, String? avatarPath})>{};
  final emails = <String, String>{};
  final files = <String>{};
  final takenUsernames = <String>{};

  String goodCode = '123456';
  AccountError? signUpError;
  AccountError? uploadError;
  AccountError? resendError;
  AccountError? everythingError;

  /// Only profile loads fail with this.
  AccountError? profileError;

  /// The new password is refused after the code was accepted; like the real
  /// backend, the recovery session is dropped and never reported.
  AccountError? updatePasswordError;

  /// The signed-in user's password can't be set (offline and the like).
  AccountError? setPasswordError;

  /// How long setting the password takes.
  Duration setPasswordDelay = Duration.zero;

  /// The user id last reported on [userIdChanges].
  String? currentUser;

  /// Set just before signUp runs: another device takes this name.
  String? raceTakes;
  int _next = 1;

  void _check() {
    final e = everythingError;
    if (e != null) throw AccountException(e);
  }

  void emitUser(String? id) {
    currentUser = id;
    _ids.add(id);
  }

  @override
  Stream<String?> get userIdChanges => _ids.stream;

  @override
  Future<String?> signUp(String email, String password, String username) async {
    calls.add('signUp');
    _check();
    if (signUpError != null) throw AccountException(signUpError!);
    if (raceTakes != null) {
      takenUsernames.add(raceTakes!);
      // The trigger's unique violation, as the backend maps it.
      if (raceTakes == username) {
        throw const AccountException(AccountError.unknown);
      }
    }
    final existing = users[email];
    if (existing != null) {
      if (existing.confirmed) {
        throw const AccountException(AccountError.emailTaken);
      }
      // Like gotrue: an unconfirmed email only gets a new code; the first
      // sign-up's password and username stay.
      return null;
    }
    final id = 'u${_next++}';
    users[email] = (password: password, id: id, confirmed: false);
    profiles[id] = (username: username, avatarPath: null);
    emails[id] = email;
    takenUsernames.add(username);
    return null;
  }

  @override
  Future<String> verifySignup(String email, String code) async {
    calls.add('verifySignup');
    _check();
    final u = users[email];
    if (u == null || code != goodCode) {
      throw const AccountException(AccountError.badCode);
    }
    users[email] = (password: u.password, id: u.id, confirmed: true);
    emitUser(u.id);
    return u.id;
  }

  @override
  Future<void> resendSignup(String email) async {
    calls.add('resendSignup');
    _check();
    if (resendError != null) throw AccountException(resendError!);
  }

  @override
  Future<String> logIn(String email, String password) async {
    calls.add('logIn');
    _check();
    final u = users[email];
    if (u == null || u.password != password) {
      throw const AccountException(AccountError.wrongCredentials);
    }
    if (!u.confirmed) {
      throw const AccountException(AccountError.emailNotConfirmed);
    }
    emitUser(u.id);
    return u.id;
  }

  @override
  Future<void> setPassword(String password) async {
    calls.add('setPassword');
    await Future<void>.delayed(setPasswordDelay);
    _check();
    if (setPasswordError != null) throw AccountException(setPasswordError!);
    final email = emails[currentUser];
    if (email == null) throw const AccountException(AccountError.unknown);
    final u = users[email]!;
    // Like gotrue, which refuses an unchanged password.
    if (u.password == password) {
      throw const AccountException(AccountError.samePassword);
    }
    users[email] = (password: password, id: u.id, confirmed: u.confirmed);
  }

  @override
  Future<void> sendReset(String email) async {
    calls.add('sendReset');
    _check();
  }

  @override
  Future<String> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    calls.add('resetPassword');
    _check();
    final u = users[email];
    if (u == null || code != goodCode) {
      throw const AccountException(AccountError.badCode);
    }
    if (updatePasswordError != null) {
      throw AccountException(updatePasswordError!);
    }
    users[email] = (password: newPassword, id: u.id, confirmed: true);
    emitUser(u.id);
    return u.id;
  }

  @override
  Future<void> logOut() async {
    calls.add('logOut');
    emitUser(null);
  }

  @override
  Future<bool> usernameAvailable(String name) async {
    calls.add('usernameAvailable');
    _check();
    return !takenUsernames.contains(name);
  }

  @override
  Future<Profile?> loadProfile(String id) async {
    calls.add('loadProfile');
    _check();
    if (profileError != null) throw AccountException(profileError!);
    final p = profiles[id];
    if (p == null) return null;
    return Profile(
      id: id,
      username: p.username,
      email: emails[id]!,
      avatarPath: p.avatarPath,
      avatarUrl: p.avatarPath == null ? null : 'https://x/${p.avatarPath}',
    );
  }

  @override
  Future<void> updateUsername(String id, String name) async {
    calls.add('updateUsername');
    _check();
    if (takenUsernames.contains(name)) {
      throw const AccountException(AccountError.usernameTaken);
    }
    final p = profiles[id]!;
    takenUsernames.remove(p.username);
    takenUsernames.add(name);
    profiles[id] = (username: name, avatarPath: p.avatarPath);
  }

  @override
  Future<void> uploadAvatar(String id, String path, Uint8List bytes) async {
    calls.add('uploadAvatar');
    _check();
    if (uploadError != null) throw AccountException(uploadError!);
    files.add(path);
  }

  @override
  Future<void> setAvatarPath(String id, String? path) async {
    calls.add('setAvatarPath');
    _check();
    final p = profiles[id]!;
    profiles[id] = (username: p.username, avatarPath: path);
  }

  @override
  Future<void> deleteAvatarFiles(String id, {String? keep}) async {
    calls.add('deleteAvatarFiles');
    _check();
    files.removeWhere((f) => f.startsWith('$id/') && f != keep);
  }

  @override
  Future<void> deleteMyAccount() async {
    calls.add('deleteMyAccount');
    _check();
  }
}
