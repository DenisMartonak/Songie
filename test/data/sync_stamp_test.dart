import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/hlc.dart';
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

  test('reserve advances seq and observes the clock', () async {
    final db = testDb();
    addTearDown(db.close);
    var s = await SyncStamp.load(db, nowMs: () => 1000);
    final start = (await s.next()).localSeq;
    final observed = const Hlc(
      wallMs: 1000 + 3600000,
      counter: 7,
      deviceId: 'other',
    ).pack();
    final seqs = await s.reserve(3, observedClock: observed);
    expect(seqs, [start + 1, start + 2, start + 3]);
    final after = await s.next();
    expect(after.clock.compareTo(observed) > 0, isTrue);
    expect(after.localSeq, start + 4);

    s = await SyncStamp.load(db, nowMs: () => 1000);
    final reloaded = await s.next();
    expect(reloaded.localSeq, start + 5);
    expect(reloaded.clock.compareTo(after.clock) > 0, isTrue);
  });

  test(
    'nextMany() gives distinct increasing stamps and persists once',
    () async {
      final db = testDb();
      addTearDown(db.close);
      var s = await SyncStamp.load(db, nowMs: () => 1000);
      final first = await s.next();
      final many = await s.nextMany(3, ids: ['x', null, 'z']);
      expect(many.map((e) => e.id).first, 'x');
      expect(many[2].id, 'z');
      expect(many[1].id, isNotEmpty);
      for (var i = 0; i < 3; i++) {
        final prev = i == 0 ? first : many[i - 1];
        expect(many[i].localSeq, prev.localSeq + 1);
        expect(many[i].clock.compareTo(prev.clock) > 0, isTrue);
      }
      expect(await s.nextMany(0), isEmpty);
      s = await SyncStamp.load(db, nowMs: () => 1000);
      final after = await s.next();
      expect(after.localSeq, many.last.localSeq + 1);
      expect(after.clock.compareTo(many.last.clock) > 0, isTrue);
      expect(() => s.nextMany(2, ids: ['a']), throwsArgumentError);
    },
  );

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
