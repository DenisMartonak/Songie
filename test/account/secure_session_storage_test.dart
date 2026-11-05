import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/secure_session_storage.dart';

/// A fake keyring: a map, or always throwing. Never the real keyring.
class _Keyring extends Fake implements FlutterSecureStorage {
  _Keyring({this.broken = false});
  final bool broken;
  final values = <String, String>{};

  void _maybeThrow() {
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

void main() {
  test('SecureSessionStorage keeps the session in the keyring', () async {
    final keyring = _Keyring();
    final s = SecureSessionStorage(keyring);
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);
    await s.persistSession('{"a":1}');
    expect(keyring.values[kSupabaseSessionKey], '{"a":1}');
    expect(await s.hasAccessToken(), isTrue);
    expect(await s.accessToken(), '{"a":1}');
    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
    expect(keyring.values, isEmpty);
  });

  test(
    'SecureSessionStorage falls back to memory when the keyring throws',
    () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = original);

      final s = SecureSessionStorage(_Keyring(broken: true));
      await s.initialize();
      expect(logs.where((l) => l.contains(' W ')), isNotEmpty);
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('{"a":1}');
      expect(await s.accessToken(), '{"a":1}');
      await s.removePersistedSession();
      expect(await s.accessToken(), isNull);
    },
  );
}
