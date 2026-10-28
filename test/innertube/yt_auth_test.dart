import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/providers.dart';

import '../helpers/test_db.dart';

class _Mem implements YtSessionStore {
  _Mem({this.isAvailable = true, this.readThrows = false});
  YtSession? stored;
  bool isAvailable;
  bool readThrows;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<YtSession?> read() async {
    if (readThrows) throw StateError('keyring locked');
    return stored;
  }

  @override
  Future<void> write(YtSession s) async => stored = s;
  @override
  Future<void> clear() async => stored = null;
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

  test('load after restart restores YtSignedIn', () async {
    final store = _Mem();
    await make(store).read(ytAuthProvider.notifier).signIn(sess, name: 'N');
    final c2 = make(store);
    await c2.read(ytAuthProvider.notifier).load();
    expect(c2.read(ytAuthProvider), isA<YtSignedIn>());
    expect((c2.read(ytAuthProvider) as YtSignedIn).name, 'N');
    expect(c2.read(ytAuthProvider.notifier).session, isNotNull);
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

  test('unavailable store gives YtAuthUnavailable', () async {
    final c = make(_Mem(isAvailable: false));
    await c.read(ytAuthProvider.notifier).load();
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());
  });

  test('a read that throws gives YtAuthUnavailable', () async {
    final c = make(_Mem(readThrows: true));
    await c.read(ytAuthProvider.notifier).load();
    expect(c.read(ytAuthProvider), isA<YtAuthUnavailable>());
  });
}
