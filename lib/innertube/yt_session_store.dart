import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/settings_repository.dart';
import '../providers.dart';
import 'yt_session.dart';

const kYtSessionKey = 'yt_session';

abstract class YtSessionStore {
  Future<bool> available();
  Future<YtSession?> read();
  Future<void> write(YtSession s);
  Future<void> clear();
}

/// Android Keystore / Windows Credential Manager / Linux libsecret.
class SecureYtSessionStore implements YtSessionStore {
  SecureYtSessionStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<bool> available() async {
    try {
      const k = 'yt_probe';
      await _s.write(key: k, value: '1');
      final v = await _s.read(key: k);
      await _s.delete(key: k);
      return v == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<YtSession?> read() async {
    try {
      final raw = await _s.read(key: kYtSessionKey);
      if (raw == null) return null;
      return YtSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(YtSession s) =>
      _s.write(key: kYtSessionKey, value: jsonEncode(s.toJson()));

  @override
  Future<void> clear() => _s.delete(key: kYtSessionKey);
}

sealed class YtAuthState {
  const YtAuthState();
}

class YtSignedOut extends YtAuthState {
  const YtSignedOut();
  @override
  String toString() => 'YtSignedOut';
}

class YtSignedIn extends YtAuthState {
  const YtSignedIn(this.name);
  final String? name;
  @override
  String toString() => 'YtSignedIn';
}

class YtExpired extends YtAuthState {
  const YtExpired(this.name);
  final String? name;
  @override
  String toString() => 'YtExpired';
}

class YtAuthUnavailable extends YtAuthState {
  const YtAuthUnavailable();
  @override
  String toString() => 'YtAuthUnavailable';
}

class YtAuth extends Notifier<YtAuthState> {
  YtSession? _session;
  bool _sessionLoaded = false;
  int _gen = 0;

  @override
  YtAuthState build() => const YtSignedOut();

  /// The cached session; null until [ensureSession] has run, and null unless
  /// signed in. Callers that need the session should use [ensureSession].
  YtSession? get session => state is YtSignedIn ? _session : null;

  /// Startup: reads only device-local settings (never the keyring, never the
  /// network).
  Future<void> load() async {
    final gen = ++_gen;
    final settings = ref.read(settingsRepositoryProvider);
    try {
      final marked = await settings.getBool(kYtSignedIn, fallback: false);
      final name = await settings.getString(kYtAccountName);
      if (gen != _gen) return;
      _sessionLoaded = false;
      _session = null;
      state = marked ? YtSignedIn(name) : const YtSignedOut();
    } catch (_) {
      if (gen != _gen) return;
      state = const YtSignedOut();
    }
  }

  /// Reads secure storage on first use and caches the result. Empty store
  /// while marked signed in means signed out (marker cleared); a failing
  /// store means [YtAuthUnavailable].
  Future<YtSession?> ensureSession() async {
    if (state is! YtSignedIn) return null;
    if (_sessionLoaded) return _session;
    final gen = _gen;
    final name = (state as YtSignedIn).name;
    YtSession? s;
    try {
      s = await ref.read(ytSessionStoreProvider).read();
    } catch (_) {
      if (gen == _gen) state = const YtAuthUnavailable();
      return null;
    }
    if (gen != _gen) return null;
    if (s == null) {
      // Distinguish "store unreadable" from "store empty".
      final ok = await ref.read(ytSessionStoreProvider).available();
      if (gen != _gen) return null;
      if (!ok) {
        state = const YtAuthUnavailable();
        return null;
      }
      await ref.read(settingsRepositoryProvider).setBool(kYtSignedIn, false);
      await ref.read(settingsRepositoryProvider).setString(kYtAccountName, null);
      if (gen != _gen) return null;
      state = const YtSignedOut();
      return null;
    }
    _session = s;
    _sessionLoaded = true;
    state = YtSignedIn(name);
    return s;
  }

  /// Lazy keyring probe, for the Settings row and the sign-in start.
  Future<void> checkAvailable() async {
    final gen = _gen;
    bool ok;
    try {
      ok = await ref.read(ytSessionStoreProvider).available();
    } catch (_) {
      ok = false;
    }
    if (gen != _gen) return;
    if (!ok) {
      state = const YtAuthUnavailable();
    } else if (state is YtAuthUnavailable) {
      state = const YtSignedOut();
    }
  }

  Future<void> signIn(YtSession s, {String? name}) async {
    final gen = ++_gen;
    await ref.read(ytSessionStoreProvider).write(s);
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setString(kYtAccountName, name);
    await settings.setBool(kYtSignedIn, true);
    if (gen != _gen) return;
    _session = s;
    _sessionLoaded = true;
    state = YtSignedIn(name);
  }

  Future<void> signOut() async {
    final gen = ++_gen;
    _session = null;
    _sessionLoaded = false;
    state = const YtSignedOut();
    final settings = ref.read(settingsRepositoryProvider);
    try {
      await ref.read(ytSessionStoreProvider).clear();
    } finally {
      await settings.setString(kYtAccountName, null);
      await settings.setBool(kYtSignedIn, false);
      if (gen == _gen) state = const YtSignedOut();
    }
  }

  void markExpired() {
    final cur = state;
    if (cur is YtSignedIn) state = YtExpired(cur.name);
  }
}
