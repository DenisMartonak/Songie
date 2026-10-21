import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/sync_stamp.dart';

import '../helpers/test_db.dart';

void main() {
  test('creates and persists a device id once', () async {
    final db = testDb();
    addTearDown(db.close);
    final s1 = await SyncStamp.load(db);
    final s2 = await SyncStamp.load(db);
    expect(s1.deviceId, isNotEmpty);
    expect(s2.deviceId, s1.deviceId);
  });

  test('next() increments local_seq and clock, survives reload', () async {
    final db = testDb();
    addTearDown(db.close);
    var s = await SyncStamp.load(db, nowMs: () => 1000);
    final a = await s.next();
    final b = await s.next();
    expect(b.localSeq, a.localSeq + 1);
    expect(b.clock.compareTo(a.clock) > 0, isTrue);
    expect(a.originDevice, s.deviceId);
    s = await SyncStamp.load(db, nowMs: () => 1000);
    final c = await s.next();
    expect(c.localSeq, b.localSeq + 1);
    expect(c.clock.compareTo(b.clock) > 0, isTrue);
  });

  test('next() uses the given id or generates one', () async {
    final db = testDb();
    addTearDown(db.close);
    final s = await SyncStamp.load(db);
    expect((await s.next(id: 'fixed')).id, 'fixed');
    expect((await s.next()).id, isNotEmpty);
  });

  test(
    'next() works inside a caller transaction and persists on commit',
    () async {
      final db = testDb();
      addTearDown(db.close);
      final s = await SyncStamp.load(db, nowMs: () => 1000);
      late Stamp inner;
      await db.transaction(() async {
        await s.next();
        inner = await s.next();
      });
      final reloaded = await SyncStamp.load(db, nowMs: () => 1000);
      final after = await reloaded.next();
      expect(after.localSeq, inner.localSeq + 1);
      expect(after.clock.compareTo(inner.clock) > 0, isTrue);
    },
  );
}
