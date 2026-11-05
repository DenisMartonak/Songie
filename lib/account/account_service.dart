import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/connectivity.dart';
import '../core/log.dart';
import 'account_backend.dart';
import 'avatar_image.dart';
import 'username.dart';

export 'account_backend.dart' show AccountError, AccountException, Profile;

sealed class AccountState {
  const AccountState();
}

class SignedOut extends AccountState {
  const SignedOut();
  @override
  String toString() => 'SignedOut';
}

class SignedIn extends AccountState {
  const SignedIn(this.profile);
  final Profile profile;
  @override
  String toString() => 'SignedIn';
}

/// Where a sign-up or log-in got to.
enum AuthStep {
  /// Signed in.
  done,

  /// The email must be confirmed with the emailed code first.
  needsCode,
}

/// Accounts for the app: the signed-in state and every account action, on
/// an [AccountBackend]. Signed in means the profile has loaded; while it
/// can't load (offline), the app counts as signed out.
class AccountService {
  /// [network] (connection changes) retries a restored session whose
  /// profile couldn't load when the device comes back online.
  AccountService(this._b, {Stream<NetworkKind>? network}) {
    _sub = _b.userIdChanges.listen(
      (id) => unawaited(_follow(id).catchError((_) {})),
      onError: (Object _) {},
    );
    _netSub = network?.listen((kind) {
      if (kind == NetworkKind.offline) return;
      if (_userId != null && _state is SignedOut) {
        unawaited(refresh().catchError((_) {}));
      }
    }, onError: (Object _) {});
  }

  StreamSubscription<NetworkKind>? _netSub;

  final AccountBackend _b;
  late final StreamSubscription<String?> _sub;
  final _changes = StreamController<AccountState>.broadcast();
  AccountState _state = const SignedOut();

  /// Bumped on every change of user, so a slow profile load for an earlier
  /// user can't land.
  int _gen = 0;
  String? _userId;

  AccountState get state => _state;

  /// The current state first, then every change.
  Stream<AccountState> get states => Stream<AccountState>.multi((c) {
    c.addSync(_state);
    final sub = _changes.stream.listen(c.addSync, onDone: c.closeSync);
    c.onCancel = sub.cancel;
  });

  SignedIn get _signedIn {
    final s = _state;
    if (s is! SignedIn) throw StateError('Not signed in');
    return s;
  }

  void _set(AccountState s) {
    if (_changes.isClosed) return;
    _state = s;
    _changes.add(s);
  }

  /// Loads [id]'s profile and signs in, or signs out on null. A repeated id
  /// that is already signed in is ignored; a failed load stays signed out
  /// and is rethrown.
  Future<void> _follow(String? id) async {
    if (id == null) {
      _gen++;
      _userId = null;
      _loading = null;
      if (_state is! SignedOut) _set(const SignedOut());
      return;
    }
    final s = _state;
    if (s is SignedIn && s.profile.id == id) return;
    if (id != _userId) {
      _gen++;
      _loading = null;
    }
    _userId = id;
    // The auth event and the action that caused it share one load.
    final pending = _loading;
    if (pending != null) return pending;
    late final Future<void> load;
    load = _load(id, _gen).whenComplete(() {
      if (identical(_loading, load)) _loading = null;
    });
    _loading = load;
    return load;
  }

  Future<void>? _loading;

  Future<void> _load(String id, int gen) async {
    final profile = await _b.loadProfile(id);
    if (gen != _gen) return;
    if (profile == null) {
      AppLog.w('Account: signed in without a profile');
      throw const AccountException(AccountError.unknown);
    }
    _set(SignedIn(profile));
  }

  /// Loads the profile again: for a session restored while offline (still
  /// signed out), or to pick up changes. Does nothing when no session.
  Future<void> refresh() async {
    final id = _userId;
    if (id == null) return;
    if (_state is SignedIn) {
      await _reload(id);
    } else {
      await _follow(id);
    }
  }

  /// Signs in as [id] after a user action. If the profile can't load, the
  /// session is dropped again (so the stored session and the app agree) and
  /// the load's error is thrown.
  Future<void> _signInAfterAuth(String id) async {
    try {
      await _follow(id);
    } on AccountException {
      await logOut();
      rethrow;
    } catch (_) {
      await logOut();
      throw const AccountException(AccountError.unknown);
    }
  }

  /// [AuthStep.needsCode] until the emailed code is entered. A username
  /// someone took since it was checked gives
  /// [AccountError.usernameJustTaken].
  Future<AuthStep> signUp(
    String email,
    String password,
    String username,
  ) async {
    final name = normalizeUsername(username);
    final mail = email.trim();
    String? id;
    try {
      id = await _b.signUp(mail, password, name);
    } on AccountException catch (e) {
      // The trigger's unique violation is a bare server error; ask again.
      if (e.error != AccountError.unknown) rethrow;
      if (!await _b.usernameAvailable(name)) {
        throw const AccountException(AccountError.usernameJustTaken);
      }
      rethrow;
    }
    if (id == null) return AuthStep.needsCode;
    await _signInAfterAuth(id);
    return AuthStep.done;
  }

  Future<void> verifySignup(String email, String code) async =>
      _signInAfterAuth(await _b.verifySignup(email.trim(), code.trim()));

  Future<void> resendSignup(String email) => _b.resendSignup(email.trim());

  /// [AuthStep.needsCode] when the email isn't confirmed yet.
  Future<AuthStep> logIn(String email, String password) async {
    final String id;
    try {
      id = await _b.logIn(email.trim(), password);
    } on AccountException catch (e) {
      if (e.error == AccountError.emailNotConfirmed) return AuthStep.needsCode;
      rethrow;
    }
    await _signInAfterAuth(id);
    return AuthStep.done;
  }

  Future<void> sendReset(String email) => _b.sendReset(email.trim());

  /// Signs in with the reset code and sets the new password.
  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async => _signInAfterAuth(
    await _b.resetPassword(email.trim(), code.trim(), newPassword),
  );

  Future<void> logOut() async {
    await _b.logOut();
    await _follow(null);
  }

  Future<bool> usernameAvailable(String name) =>
      _b.usernameAvailable(normalizeUsername(name));

  Future<void> changeUsername(String name) async {
    final p = _signedIn.profile;
    final n = normalizeUsername(name);
    await _b.updateUsername(p.id, n);
    _set(
      SignedIn(
        Profile(
          id: p.id,
          username: n,
          email: p.email,
          avatarPath: p.avatarPath,
          avatarUrl: p.avatarUrl,
        ),
      ),
    );
  }

  /// Saves [imageBytes] as the new picture: upload under a new name, point
  /// the profile at it, then delete the older files. A failure before the
  /// profile update leaves the old picture in place. Throws
  /// [FormatException] when the bytes aren't an image.
  Future<void> changeAvatar(Uint8List imageBytes) async {
    final id = _signedIn.profile.id;
    final jpeg = await Isolate.run(() => avatarJpeg(imageBytes));
    final path = '$id/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _b.uploadAvatar(id, path, jpeg);
    await _b.setAvatarPath(id, path);
    try {
      await _b.deleteAvatarFiles(id, keep: path);
    } on AccountException {
      // Only leftovers; the profile already points at the new file.
    }
    await _reload(id);
  }

  /// Clears the picture, then deletes its files (best effort).
  Future<void> removeAvatar() async {
    final id = _signedIn.profile.id;
    await _b.setAvatarPath(id, null);
    try {
      await _b.deleteAvatarFiles(id);
    } on AccountException {
      // Only leftovers.
    }
    await _reload(id);
  }

  Future<void> _reload(String id) async {
    final p = await _b.loadProfile(id);
    if (p != null && _userId == id) _set(SignedIn(p));
  }

  /// Clears the picture, deletes its files, then the account, then signs
  /// out. If the account can't be deleted, the profile never points at a
  /// deleted file.
  Future<void> deleteAccount() async {
    final id = _signedIn.profile.id;
    await _b.setAvatarPath(id, null);
    await _b.deleteAvatarFiles(id);
    await _b.deleteMyAccount();
    await logOut();
  }

  Future<void> dispose() async {
    await _netSub?.cancel();
    await _sub.cancel();
    await _changes.close();
  }
}
