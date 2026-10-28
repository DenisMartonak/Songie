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

  @override
  YtAuthState build() => const YtSignedOut();

  /// The in-memory session; null unless signed in.
  YtSession? get session => state is YtSignedIn ? _session : null;

  /// Reads storage only; never touches the network.
  Future<void> load() async {
    final store = ref.read(ytSessionStoreProvider);
    try {
      if (!await store.available()) {
        state = const YtAuthUnavailable();
        return;
      }
      final s = await store.read();
      if (s == null) {
        _session = null;
        state = const YtSignedOut();
        return;
      }
      _session = s;
      final name = await ref
          .read(settingsRepositoryProvider)
          .getString(kYtAccountName);
      state = YtSignedIn(name);
    } catch (_) {
      state = const YtAuthUnavailable();
    }
  }

  Future<void> signIn(YtSession s, {String? name}) async {
    await ref.read(ytSessionStoreProvider).write(s);
    await ref.read(settingsRepositoryProvider).setString(kYtAccountName, name);
    _session = s;
    state = YtSignedIn(name);
  }

  Future<void> signOut() async {
    _session = null;
    state = const YtSignedOut();
    await ref.read(ytSessionStoreProvider).clear();
    await ref.read(settingsRepositoryProvider).setString(kYtAccountName, null);
  }

  void markExpired() {
    final cur = state;
    if (cur is YtSignedIn) state = YtExpired(cur.name);
  }
}
