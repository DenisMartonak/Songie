import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import '../core/log.dart';

const kSupabaseSessionKey = 'supabase_session';

/// Keeps the Supabase session in the system keyring (Android Keystore,
/// Windows Credential Manager, Linux libsecret), like the YouTube sign-in.
/// Without a working keyring the session lives in memory for this run only,
/// and a warning is logged.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  bool _inMemory = false;
  String? _memory;

  /// Switches to memory for the rest of the run.
  void _fallBack(Object e) {
    if (_inMemory) return;
    _inMemory = true;
    AppLog.w(
      'Account session: no keyring, keeping it in memory (${e.runtimeType})',
    );
  }

  /// Probes the keyring with a throwaway value.
  @override
  Future<void> initialize() async {
    try {
      const k = 'supabase_probe';
      await _s.write(key: k, value: '1');
      final v = await _s.read(key: k);
      await _s.delete(key: k);
      if (v != '1') _fallBack(StateError('probe read back $v'));
    } catch (e) {
      _fallBack(e);
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    if (_inMemory) return _memory;
    try {
      return await _s.read(key: kSupabaseSessionKey);
    } catch (e) {
      _fallBack(e);
      return _memory;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    _memory = null;
    if (_inMemory) return;
    try {
      await _s.delete(key: kSupabaseSessionKey);
    } catch (e) {
      _fallBack(e);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _memory = persistSessionString;
    if (_inMemory) return;
    try {
      await _s.write(key: kSupabaseSessionKey, value: persistSessionString);
    } catch (e) {
      _fallBack(e);
    }
  }
}
