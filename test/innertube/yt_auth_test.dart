import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/providers.dart';

import '../helpers/test_db.dart';

class _Mem implements YtSessionStore {
  _Mem({this.isAvailable = true});
  YtSession? stored;
  bool clearThrows = false;
  int touched = 0;
  Completer<YtSession?>? gate;
  bool isAvailable;
  bool readThrows = false;
  @override
  Future<bool> available() async {
    touched++;
    return isAvailable;
  }

  @override
  Future<YtSession?> read() async {
    touched++;
    if (gate != null) return gate!.future;
    if (readThrows) throw StateError('keyring locked');
    return stored;
  }

  @override
  Future<void> write(YtSession s) async => stored = s;
  @override
  Future<void> clear() async {
    touched++;
    if (clearThrows) throw StateError('locked');
    stored = null;
  }
}

/// A platform keyring whose reads fail (locked, D-Bus hiccup); writes and
/// deletes work. Never the real keyring.
class _FlakyKeyring extends Fake implements FlutterSecureStorage {
  final values = <String, String>{};
  bool readThrows = false;
  int reads = 0;

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
    reads++;
    // A one-off hiccup on the session read; the availability probe that
    // follows works.
    if (readThrows && key == kYtSessionKey) {
      throw PlatformException(code: 'locked');
    }
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
  }) async => values.remove(key);
}

/// Settings whose writes fail (disk full) after the keyring write worked.
class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.db);
  @override
  Future<void> setString(String key, String? v) async =>
      throw StateError('disk full');
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  ProviderContainer make(_Mem store) {
    final c = ProviderContainer(
      overrides: [
        ytSessionStoreProvider.overrideWithValue(store),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  final sess = YtSession({'SAPISID': 'SECRETVAL'});

  test('signIn writes store and name, gives YtSignedIn', () async {
    final store = _Mem();
    final c = make(store);
    await c.read(ytAuthProvider.notifier).signIn(sess, name: 'Name');
    final st = c.read(ytAuthProvider);
    expect(st, isA<YtSignedIn>());
    expect((st as YtSignedIn).name, 'Name');
    expect(store.stored, sess);
    expect(await settings.getString(kYtAccountName), 'Name');
    expect(c.read(ytAuthProvider.notifier).session, sess);
    expect('$st', isNot(contains('SECRETVAL')));
  });

  test('load restores from the marker without touching the store', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    store.touched = 0;
    final c2 = make(store);
    await c2.read(ytAuthProvider.notifier).load();
    expect((c2.read(ytAuthProvider) as YtSignedIn).name, 'N');
    expect(store.touched, 0);
    expect(c2.read(ytAuthProvider.notifier).session, isNull);
    expect(await c2.read(ytAuthProvider.notifier).ensureSession(), sess);
    expect(c2.read(ytAuthProvider.notifier).session, sess);
    expect(store.touched, 1);
    await c2.read(ytAuthProvider.notifier).ensureSession();
    expect(store.touched, 1);
  });

  test('load with nothing stored is signed out', () async {
    final c = make(_Mem());
    await c.read(ytAuthProvider.notifier).load();
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());
  });

  test('signOut clears store and name', () async {
    final store = _Mem();
    final c = make(store);
    final n = c.read(ytAuthProvider.notifier);
    await n.signIn(sess, name: 'N');
    await n.signOut();
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());
    expect(store.stored, isNull);
    expect(await settings.getString(kYtAccountName), isNull);
    expect(n.session, isNull);
  });

  test('markExpired keeps the stored session', () async {
    final store = _Mem();
    final c = make(store);
    final n = c.read(ytAuthProvider.notifier);
    await n.signIn(sess, name: 'N');
    n.markExpired();
    expect(c.read(ytAuthProvider), isA<YtExpired>());
    expect(store.stored, sess);
    expect(n.session, isNull);
  });

  test('checkAvailable false gives YtAuthUnavailable', () async {
    final c = make(_Mem(isAvailable: false));
    await c.read(ytAuthProvider.notifier).checkAvailable();
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());
  });

  test('ensureSession: throwing read gives YtAuthUnavailable', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    store.readThrows = true;
    final c = make(store);
    await c.read(ytAuthProvider.notifier).load();
    expect(await c.read(ytAuthProvider.notifier).ensureSession(), isNull);
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());
  });

  test('ensureSession: empty store clears the marker, signed out', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    store.stored = null;
    final c = make(store);
    await c.read(ytAuthProvider.notifier).load();
    expect(await c.read(ytAuthProvider.notifier).ensureSession(), isNull);
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());
    expect(await settings.getBool(kYtSignedIn, fallback: true), isFalse);
  });

  test('signOut with a throwing clear still signs out and rethrows', () async {
    final store = _Mem();
    final c = make(store);
    final n = c.read(ytAuthProvider.notifier);
    await n.signIn(sess, name: 'N');
    store.clearThrows = true;
    await expectLater(n.signOut(), throwsStateError);
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());
    expect(await settings.getString(kYtAccountName), isNull);
    expect(await settings.getBool(kYtSignedIn, fallback: true), isFalse);
  });

  test('a late ensureSession cannot overwrite a newer signOut', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    final c = make(store);
    final n = c.read(ytAuthProvider.notifier);
    await n.load();
    store.gate = Completer();
    final pending = n.ensureSession();
    await n.signOut();
    store.gate!.complete(sess);
    expect(await pending, isNull);
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());
    expect(n.session, isNull);
  });

  group('SecureYtSessionStore.read', () {
    test('absent key is null; bad JSON is null', () async {
      final k = _FlakyKeyring();
      final store = SecureYtSessionStore(k);
      expect(await store.read(), isNull);
      k.values[kYtSessionKey] = '{not json';
      expect(await store.read(), isNull);
      k.values[kYtSessionKey] = '{"cookies": 3}';
      expect(await store.read(), isNull);
    });

    test('a platform error is rethrown, not read as "signed out"', () async {
      final k = _FlakyKeyring()..readThrows = true;
      await expectLater(
        SecureYtSessionStore(k).read(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  test('a keyring read that throws gives YtAuthUnavailable and keeps the '
      'markers', () async {
    final k = _FlakyKeyring();
    final store = SecureYtSessionStore(k);
    await make(_Mem()).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    await store.write(sess);
    k.readThrows = true;
    final c = ProviderContainer(
      overrides: [
        ytSessionStoreProvider.overrideWithValue(store),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(ytAuthProvider.notifier);
    await n.load();
    expect(await n.ensureSession(), isNull);
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());
    expect(await settings.getBool(kYtSignedIn, fallback: false), isTrue);
    expect(await settings.getString(kYtAccountName), 'N');
    expect(k.values.containsKey(kYtSessionKey), isTrue);
  });

  test('checkAvailable recovering from YtAuthUnavailable restores the '
      'signed-in state and reads the keyring again', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    store.readThrows = true;
    final c = make(store);
    final n = c.read(ytAuthProvider.notifier);
    await n.load();
    expect(await n.ensureSession(), isNull);
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());

    store.readThrows = false;
    await n.checkAvailable();
    final st = c.read(ytAuthProvider);
    expect(st, isA<YtSignedIn>());
    expect((st as YtSignedIn).name, 'N');
    expect(await n.ensureSession(), sess);
  });

  test(
    'the keyring probe runs once per process until sign-in or sign-out',
    () async {
      final store = _Mem();
      final c = make(store);
      final n = c.read(ytAuthProvider.notifier);
      await n.checkAvailable();
      await n.checkAvailable();
      await n.checkAvailable();
      expect(store.touched, 1);
      await n.signIn(sess, name: 'N');
      store.touched = 0;
      await n.checkAvailable();
      expect(store.touched, 1);
    },
  );

  test('a failed marker write after the store write clears the store and '
      'rethrows', () async {
    final store = _Mem();
    final c = ProviderContainer(
      overrides: [
        ytSessionStoreProvider.overrideWithValue(store),
        settingsRepositoryProvider.overrideWithValue(_FailingSettings(db)),
      ],
    );
    addTearDown(c.dispose);
    await expectLater(
      c.read(ytAuthProvider.notifier).signIn(sess, name: 'N'),
      throwsStateError,
    );
    expect(store.stored, isNull);
    expect(c.read(ytAuthProvider), isNot(isA<YtSignedIn>()));
  });
}
