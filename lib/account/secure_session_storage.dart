import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import '../core/log.dart';
import '../data/settings_repository.dart';

const kSupabaseSessionKey = 'supabase_session';

/// A non-secret yes/no: is an account session stored in the keyring?
abstract class SessionMarker {
  Future<bool> read();
  Future<void> write(bool stored);
}

/// [SessionMarker] in the device-local setting `account_signed_in`.
class SettingsSessionMarker implements SessionMarker {
  SettingsSessionMarker(this._settings);
  final SettingsRepository _settings;

  @override
  Future<bool> read() => _settings.getBool(kAccountSignedIn, fallback: false);

  @override
  Future<void> write(bool stored) =>
      _settings.setBool(kAccountSignedIn, stored);
}

/// Keeps the Supabase session in the system keyring (Android Keystore,
/// Windows Credential Manager, Linux libsecret), like the YouTube sign-in.
/// The keyring is read only when [SessionMarker] says a session is there,
/// so a signed-out start never touches it. Without a working keyring the
/// session lives in memory for this run only, and a warning is logged.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this._marker, FlutterSecureStorage? storage})
    : _s = storage ?? const FlutterSecureStorage();

  final SessionMarker _marker;
  final FlutterSecureStorage _s;

  /// Whether the keyring may hold a session (from the marker, then kept up
  /// to date here).
  bool _stored = false;
  bool _inMemory = false;
  bool _loaded = false;
  String? _memory;

  /// Switches to memory for the rest of the run.
  void _fallBack(Object e) {
    if (_inMemory) return;
    _inMemory = true;
    AppLog.w(
      'Account session: no keyring, keeping it in memory (${e.runtimeType})',
    );
  }

  /// Reads the marker only; never the keyring.
  @override
  Future<void> initialize() async {
    try {
      _stored = await _marker.read();
    } catch (e) {
      AppLog.w('Account session: marker unreadable (${e.runtimeType})');
      _stored = false;
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  /// The memory copy once there is one; else the keyring, read once and
  /// only when the marker is set.
  @override
  Future<String?> accessToken() async {
    if (_loaded || _inMemory || !_stored) return _memory;
    try {
      _memory = await _s.read(key: kSupabaseSessionKey);
      _loaded = true;
    } catch (e) {
      _fallBack(e);
    }
    return _memory;
  }

  /// Clears the marker, then deletes the keyring copy, even after a
  /// fallback to memory, so a logged-out session can't come back.
  @override
  Future<void> removePersistedSession() async {
    _memory = null;
    _loaded = true;
    _stored = false;
    try {
      await _marker.write(false);
    } catch (e) {
      AppLog.w('Account session: marker not cleared (${e.runtimeType})');
    }
    try {
      await _s.delete(key: kSupabaseSessionKey);
    } catch (e) {
      _fallBack(e);
    }
  }

  /// Writes the keyring, then sets the marker.
  @override
  Future<void> persistSession(String persistSessionString) async {
    _memory = persistSessionString;
    _loaded = true;
    if (_inMemory) return;
    try {
      await _s.write(key: kSupabaseSessionKey, value: persistSessionString);
    } catch (e) {
      // Memory only from now on; the keyring's older copy shouldn't be
      // restored next time.
      _fallBack(e);
      if (_stored) {
        _stored = false;
        try {
          await _marker.write(false);
        } catch (_) {}
      }
      return;
    }
    if (_stored) return;
    try {
      await _marker.write(true);
      _stored = true;
    } catch (e) {
      AppLog.w('Account session: marker not set (${e.runtimeType})');
    }
  }
}
