import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}
