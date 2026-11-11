import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';
import 'secure_session_storage.dart';
import 'supabase_config.dart';
import 'timeout_client.dart';

/// What can go wrong with an account action, with the copy to show.
enum AccountError {
  wrongCredentials('Wrong email or password.'),
  emailTaken(
    'That email already has an account. Log in, or reset your password.',
  ),
  invalidEmail("That email address doesn't look right."),
  emailNotAllowed("The server can't send email to that address yet."),
  usernameTaken('That username is taken.'),
  usernameJustTaken('That username was just taken.'),
  badCode('That code is wrong or has expired.'),
  emailNotConfirmed('Enter the code we emailed you to confirm your email.'),
  samePassword('Choose a password different from your old one.'),
  weakPassword('That password is too weak.'),
  tooManyRequests('Too many tries. Wait a while and try again.'),
  offline("Couldn't reach the server. Check your connection."),
  unknown('Something went wrong. Try again.');

  const AccountError(this.message);

  /// The text shown to the user.
  final String message;
}

/// An account action failed with [error].
class AccountException implements Exception {
  const AccountException(this.error);
  final AccountError error;

  @override
  String toString() => 'AccountException(${error.name})';
}

/// The signed-in user's public profile, plus their own email.
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.email,
    this.avatarPath,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String email;

  /// The picture's path in the `avatars` bucket; null without a picture.
  final String? avatarPath;

  /// The picture's public URL; null without a picture.
  final String? avatarUrl;

  @override
  String toString() => 'Profile($id)';
}

/// The account server, behind an interface so the logic can be tested with
/// a fake. Every method throws [AccountException] on failure.
abstract class AccountBackend {
  /// The signed-in user's id on every auth change; null when signed out.
  Stream<String?> get userIdChanges;

  /// Creates the account. Returns the user id when it is signed in right
  /// away, null when the emailed code must be entered first.
  Future<String?> signUp(String email, String password, String username);

  /// Confirms the email with the sign-up code; returns the user id.
  Future<String> verifySignup(String email, String code);

  /// Emails a new sign-up code.
  Future<void> resendSignup(String email);

  /// Returns the user id.
  Future<String> logIn(String email, String password);

  /// Sets the signed-in user's password. An unchanged one is refused with
  /// [AccountError.samePassword].
  Future<void> setPassword(String password);

  /// Emails a password reset code.
  Future<void> sendReset(String email);

  /// Signs in with the reset code and sets [newPassword]; returns the id.
  /// If the new password is refused, the recovery session is dropped and
  /// [userIdChanges] never reports it.
  Future<String> resetPassword(String email, String code, String newPassword);

  /// Forgets the session on this device; never throws.
  Future<void> logOut();

  Future<bool> usernameAvailable(String name);

  /// Null when the user has no profile.
  Future<Profile?> loadProfile(String id);

  Future<void> updateUsername(String id, String name);

  /// Stores a JPEG at [path] (`<id>/<millis>.jpg`) in the avatars bucket.
  Future<void> uploadAvatar(String id, String path, Uint8List bytes);

  Future<void> setAvatarPath(String id, String? path);

  /// Deletes the user's files in the avatars bucket, except [keep].
  Future<void> deleteAvatarFiles(String id, {String? keep});

  /// Deletes the signed-in user's account (`delete_my_account`).
  Future<void> deleteMyAccount();
}

/// Gateway errors from a paused or restarting project count as unreachable.
const _unreachableStatus = {'502', '503', '504', '540'};

/// Maps a Supabase, Postgrest, storage or network error to an
/// [AccountError]. Postgrest `23505` (a unique violation) only comes from a
/// rename, so it is [AccountError.usernameTaken]; the sign-up trigger's
/// violation arrives as an auth 500 and maps to [AccountError.unknown] (the
/// service tells a sign-up race apart by asking again).
AccountError accountErrorOf(Object e) {
  switch (e) {
    case AccountException(:final error):
      return error;
    case AuthRetryableFetchException(:final statusCode):
      return statusCode == null || _unreachableStatus.contains(statusCode)
          ? AccountError.offline
          : AccountError.unknown;
    case AuthException(:final code, :final statusCode):
      return switch (code) {
        'invalid_credentials' => AccountError.wrongCredentials,
        'email_not_confirmed' => AccountError.emailNotConfirmed,
        'otp_expired' => AccountError.badCode,
        'user_already_exists' || 'email_exists' => AccountError.emailTaken,
        'same_password' => AccountError.samePassword,
        'weak_password' => AccountError.weakPassword,
        'email_address_invalid' ||
        'validation_failed' => AccountError.invalidEmail,
        'email_address_not_authorized' => AccountError.emailNotAllowed,
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' => AccountError.tooManyRequests,
        _ when statusCode == '429' => AccountError.tooManyRequests,
        _ => AccountError.unknown,
      };
    case PostgrestException(:final code):
      if (code == '23505') return AccountError.usernameTaken;
      return _unreachableStatus.contains(code)
          ? AccountError.offline
          : AccountError.unknown;
    case StorageException(:final statusCode):
      // Network failures carry the exception's type name, not a status.
      final status = int.tryParse(statusCode ?? '');
      return status == null || _unreachableStatus.contains(statusCode)
          ? AccountError.offline
          : AccountError.unknown;
    case SocketException() ||
        http.ClientException() ||
        TimeoutException() ||
        TlsException():
      return AccountError.offline;
  }
  return AccountError.unknown;
}

/// Logs [e] without its message (which can carry an email address) and
/// throws it as an [AccountException].
Never _fail(String what, Object e) {
  final error = accountErrorOf(e);
  final code = switch (e) {
    AuthException(:final code, :final statusCode) => ' $statusCode/$code',
    PostgrestException(:final code) => ' $code',
    StorageException(:final statusCode) => ' $statusCode',
    _ => '',
  };
  AppLog.w('Account: $what failed: ${error.name} (${e.runtimeType}$code)');
  throw AccountException(error);
}

/// Supabase.initialize with the keyring session storage; [marker] says
/// whether a session was stored, so a signed-out start never touches the
/// keyring. Codes, not links, so the implicit flow (no PKCE verifier to
/// keep), no deep links, and no Supabase logs in debug builds. Requests
/// give up after [kAccountHttpTimeout], so a dead network can't hold the
/// account screens for minutes.
Future<AccountBackend> connectSupabase(
  SessionMarker marker, {
  LocalStorage? localStorage,
}) async {
  final s = await Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabasePublishableKey,
    httpClient: TimeoutClient(http.Client()),
    debug: false,
    authOptions: FlutterAuthClientOptions(
      localStorage: localStorage ?? SecureSessionStorage(marker: marker),
      pkceAsyncStorage: _NoAsyncStorage(),
      authFlowType: AuthFlowType.implicit,
      detectSessionInUri: false,
    ),
  );
  return SupabaseAccountBackend(s.client);
}

/// Keeps nothing: the implicit flow never needs a PKCE verifier, and this
/// avoids Supabase's default shared_preferences store.
class _NoAsyncStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

/// [AccountBackend] on a Supabase client.
class SupabaseAccountBackend implements AccountBackend {
  SupabaseAccountBackend(this._c);

  final SupabaseClient _c;

  GoTrueClient get _auth => _c.auth;

  Future<T> _guard<T>(String what, Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      _fail(what, e);
    }
  }

  @override
  Stream<String?> get userIdChanges => _auth.onAuthStateChange
      // A reset code's session counts only once the new password is set
      // (the userUpdated event that follows).
      .where((s) => s.event != AuthChangeEvent.passwordRecovery)
      .map((s) => s.session?.user.id)
      .handleError((Object e) {
        // A failed token refresh while offline; the session stays.
        AppLog.w('Account: auth event error (${e.runtimeType})');
      });

  @override
  Future<String?> signUp(String email, String password, String username) =>
      _guard('sign up', () async {
        final r = await _auth.signUp(
          email: email,
          password: password,
          data: {'username': username},
        );
        final user = r.user;
        // An existing email answers without an error but with no identities.
        if (user != null && (user.identities?.isEmpty ?? false)) {
          throw const AccountException(AccountError.emailTaken);
        }
        return r.session?.user.id;
      });

  @override
  Future<String> verifySignup(String email, String code) =>
      _guard('verify sign-up', () async {
        final r = await _auth.verifyOTP(
          email: email,
          token: code,
          type: OtpType.signup,
        );
        return _idOf(r);
      });

  @override
  Future<void> resendSignup(String email) => _guard(
    'resend code',
    () => _auth.resend(email: email, type: OtpType.signup),
  );

  @override
  Future<String> logIn(String email, String password) =>
      _guard('log in', () async {
        final r = await _auth.signInWithPassword(
          email: email,
          password: password,
        );
        return _idOf(r);
      });

  @override
  Future<void> setPassword(String password) => _guard(
    'set password',
    () => _auth.updateUser(UserAttributes(password: password)),
  );

  @override
  Future<void> sendReset(String email) =>
      _guard('send reset', () => _auth.resetPasswordForEmail(email));

  @override
  Future<String> resetPassword(String email, String code, String newPassword) =>
      _guard('reset password', () async {
        final r = await _auth.verifyOTP(
          email: email,
          token: code,
          type: OtpType.recovery,
        );
        final id = _idOf(r);
        try {
          await _auth.updateUser(UserAttributes(password: newPassword));
        } catch (_) {
          // The code is used up; don't stay signed in with the old password.
          await logOut();
          rethrow;
        }
        return id;
      });

  String _idOf(AuthResponse r) {
    final id = r.session?.user.id;
    if (id == null) throw const AccountException(AccountError.unknown);
    return id;
  }

  @override
  Future<void> logOut() async {
    // The local session goes first; a failed server call doesn't matter.
    try {
      await _auth.signOut();
    } catch (e) {
      AppLog.w('Account: log out on the server failed (${e.runtimeType})');
    }
  }

  @override
  Future<bool> usernameAvailable(String name) =>
      _guard('username check', () async {
        final r = await _c.rpc<dynamic>(
          'username_available',
          params: {'name': name},
        );
        return r == true;
      });

  @override
  Future<Profile?> loadProfile(String id) => _guard('load profile', () async {
    final row = await _c
        .from('profiles')
        .select('id, username, avatar_path')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final path = row['avatar_path'] as String?;
    return Profile(
      id: id,
      username: row['username'] as String,
      email: _auth.currentUser?.email ?? '',
      avatarPath: path,
      avatarUrl: path == null
          ? null
          : _c.storage.from(kAvatarBucket).getPublicUrl(path),
    );
  });

  @override
  Future<void> updateUsername(String id, String name) => _guard(
    'change username',
    () => _c.from('profiles').update({'username': name}).eq('id', id),
  );

  @override
  Future<void> uploadAvatar(String id, String path, Uint8List bytes) => _guard(
    'upload picture',
    () => _c.storage
        .from(kAvatarBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        ),
  );

  @override
  Future<void> setAvatarPath(String id, String? path) => _guard(
    'set picture',
    () => _c.from('profiles').update({'avatar_path': path}).eq('id', id),
  );

  @override
  Future<void> deleteAvatarFiles(String id, {String? keep}) =>
      _guard('delete pictures', () async {
        final bucket = _c.storage.from(kAvatarBucket);
        final files = await bucket.list(path: id);
        final paths = [
          for (final f in files)
            if ('$id/${f.name}' != keep) '$id/${f.name}',
        ];
        if (paths.isNotEmpty) await bucket.remove(paths);
      });

  @override
  Future<void> deleteMyAccount() =>
      _guard('delete account', () => _c.rpc<dynamic>('delete_my_account'));
}

/// An [AccountBackend] whose real backend is still starting, so startup
/// never waits for Supabase. If starting fails, a warning is logged, no user
/// is ever signed in and every action fails as [AccountError.offline].
class PendingAccountBackend implements AccountBackend {
  PendingAccountBackend(Future<AccountBackend> starting) {
    _ready = starting.then<AccountBackend?>(
      (b) => b,
      onError: (Object e, StackTrace s) {
        AppLog.w('Accounts unavailable: Supabase did not start', e, s);
        return null;
      },
    );
  }

  late final Future<AccountBackend?> _ready;

  /// How long an action waits for the backend to start.
  static const _wait = Duration(seconds: 20);

  Future<AccountBackend> get _b async {
    AccountBackend? b;
    try {
      b = await _ready.timeout(_wait);
    } on TimeoutException {
      b = null;
    }
    if (b == null) throw const AccountException(AccountError.offline);
    return b;
  }

  @override
  Stream<String?> get userIdChanges => Stream.fromFuture(_ready)
      .asyncExpand((b) => b?.userIdChanges ?? const Stream<String?>.empty());

  @override
  Future<String?> signUp(
    String email,
    String password,
    String username,
  ) async => (await _b).signUp(email, password, username);

  @override
  Future<String> verifySignup(String email, String code) async =>
      (await _b).verifySignup(email, code);

  @override
  Future<void> resendSignup(String email) async =>
      (await _b).resendSignup(email);

  @override
  Future<String> logIn(String email, String password) async =>
      (await _b).logIn(email, password);

  @override
  Future<void> setPassword(String password) async =>
      (await _b).setPassword(password);

  @override
  Future<void> sendReset(String email) async => (await _b).sendReset(email);

  @override
  Future<String> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async => (await _b).resetPassword(email, code, newPassword);

  @override
  Future<void> logOut() async {
    final b = await _ready;
    await b?.logOut();
  }

  @override
  Future<bool> usernameAvailable(String name) async =>
      (await _b).usernameAvailable(name);

  @override
  Future<Profile?> loadProfile(String id) async => (await _b).loadProfile(id);

  @override
  Future<void> updateUsername(String id, String name) async =>
      (await _b).updateUsername(id, name);

  @override
  Future<void> uploadAvatar(String id, String path, Uint8List bytes) async =>
      (await _b).uploadAvatar(id, path, bytes);

  @override
  Future<void> setAvatarPath(String id, String? path) async =>
      (await _b).setAvatarPath(id, path);

  @override
  Future<void> deleteAvatarFiles(String id, {String? keep}) async =>
      (await _b).deleteAvatarFiles(id, keep: keep);

  @override
  Future<void> deleteMyAccount() async => (await _b).deleteMyAccount();
}
