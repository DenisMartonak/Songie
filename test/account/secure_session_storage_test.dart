import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/secure_session_storage.dart';

/// A fake keyring: a map, or always throwing. Never the real keyring.
class _Keyring extends Fake implements FlutterSecureStorage {
  _Keyring({this.broken = false});
  bool broken;
  final values = <String, String>{};
  int calls = 0;

  void _maybeThrow() {
    calls++;
    if (broken) throw PlatformException(code: 'no keyring');
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeThrow();
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeThrow();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeThrow();
    values.remove(key);
  }
}

class _Marker implements SessionMarker {
  _Marker([this.value = false]);
  bool value;
  @override
  Future<bool> read() async => value;
  @override
  Future<void> write(bool v) async => value = v;
}

void main() {
  test(
    'SecureSessionStorage keeps the session in the keyring, with a marker',
    () async {
      final keyring = _Keyring();
      final marker = _Marker();
      final s = SecureSessionStorage(marker: marker, storage: keyring);
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('{"a":1}');
      expect(keyring.values[kSupabaseSessionKey], '{"a":1}');
      expect(marker.value, isTrue);

      // The next start reads it back.
      final next = SecureSessionStorage(marker: marker, storage: keyring);
      await next.initialize();
      expect(await next.hasAccessToken(), isTrue);
      expect(await next.accessToken(), '{"a":1}');
      await next.removePersistedSession();
      expect(await next.hasAccessToken(), isFalse);
      expect(keyring.values, isEmpty);
      expect(marker.value, isFalse);
    },
  );

  test('a cold start with no marker never touches the keyring', () async {
    final keyring = _Keyring(broken: true);
    final s = SecureSessionStorage(marker: _Marker(), storage: keyring);
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);
    expect(await s.accessToken(), isNull);
    expect(keyring.calls, 0);
  });

  test(
    'SecureSessionStorage falls back to memory when the keyring throws',
    () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = original);

      final s = SecureSessionStorage(
        marker: _Marker(true),
        storage: _Keyring(broken: true),
      );
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);
      expect(logs.where((l) => l.contains(' W ')), isNotEmpty);
      await s.persistSession('{"a":1}');
      expect(await s.accessToken(), '{"a":1}');
      await s.removePersistedSession();
      expect(await s.accessToken(), isNull);
    },
  );

  test(
    'after a mid-run fallback, log out still deletes the keyring copy',
    () async {
      final keyring = _Keyring();
      final marker = _Marker();
      final s = SecureSessionStorage(marker: marker, storage: keyring);
      await s.initialize();
      await s.persistSession('{"a":1}');
      // The keyring hiccups once: the refreshed session goes to memory.
      keyring.broken = true;
      await s.persistSession('{"a":2}');
      keyring.broken = false;
      await s.removePersistedSession();
      expect(keyring.values, isEmpty);
      expect(marker.value, isFalse);
      expect(await s.accessToken(), isNull);
    },
  );
}
