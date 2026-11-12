import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/sync/change_feed.dart';

import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = testDb());
  tearDown(() => db.close());

  test('since pages across all tables in seq order', () async {
    await seedOneOfEach(db); // seqs 1..9
    await db.into(db.tracks).insert(trackRow(id: 'x', localSeq: 10));
    await db.into(db.tracks).insert(trackRow(id: 'y', localSeq: 11));
    final feed = ChangeFeed(db);
    final seen = <int>[];
    var cursor = 0;
    while (true) {
      final page = await feed.since(cursor, limit: 3);
      expect(page.rows.length, lessThanOrEqualTo(3));
      seen.addAll(page.rows.map((r) => r.localSeq));
      if (page.next == null) break;
      expect(page.next, page.rows.last.localSeq);
      cursor = page.next!;
    }
    expect(seen, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    expect(await feed.highSeq(), 11);
  });

  test('since excludes rows at or below seq', () async {
    await seedOneOfEach(db);
    final page = await ChangeFeed(db).since(5);
    expect(page.rows.map((r) => r.localSeq), [6, 7, 8, 9]);
    expect(page.next, isNull);
    expect((await ChangeFeed(db).since(9)).rows, isEmpty);
  });

  test('highSeq is 0 for an empty database', () async {
    expect(await ChangeFeed(db).highSeq(), 0);
  });

  test('snapshot maps wire/id to content hash', () async {
    await seedOneOfEach(db);
    final snap = await snapshot(db);
    expect(snap.length, 9);
    expect(snap.keys.first, startsWith('tracks/'));
  });

  group('safeHigh', () {
    var nowMs = 1700000000000;
    late SyncStamp stamp;
    late ChangeFeed feed;
    setUp(() async {
      nowMs = 1700000000000;
      stamp = await SyncStamp.load(db, nowMs: () => nowMs);
      feed = ChangeFeed(db, stamp: stamp);
    });

    Future<void> write(Stamp st) =>
        db.into(db.tracks).insert(trackRow(id: st.id, localSeq: st.localSeq));

    test('is highSeq when every issued seq has its row', () async {
      await write(await stamp.next());
      await write(await stamp.next());
      expect(await feed.safeHigh(), 2);
      expect(await ChangeFeed(db).safeHigh(), 2); // no stamp: highSeq
    });

    test('a stamped row not yet written holds it below that seq', () async {
      await write(await stamp.next()); // 1
      final pending = await stamp.next(); // 2, written later
      await write(await stamp.next()); // 3, lands first
      expect(await feed.highSeq(), 3);
      expect(await feed.safeHigh(), 1);

      await write(pending);
      expect(await feed.safeHigh(), 3);
    });

    test('an issued seq never written stops holding it after 60 s', () async {
      await stamp.next(); // 1, never written (a rolled-back write)
      await write(await stamp.next()); // 2
      expect(await feed.safeHigh(), 0);

      nowMs += const Duration(seconds: 59).inMilliseconds;
      expect(await feed.safeHigh(), 0);
      nowMs += const Duration(seconds: 2).inMilliseconds;
      expect(await feed.safeHigh(), 2);
    });

    test('a row written, then overwritten, does not hold it', () async {
      final created = await stamp.next(); // 1
      await write(created);
      final renamed = await stamp.next(); // 2, rewrites the same row
      await (db.update(db.tracks)..where((t) => t.id.equals(created.id))).write(
        TracksCompanion(localSeq: Value(renamed.localSeq)),
      );
      await write(await stamp.next()); // 3
      expect(await feed.safeHigh(), 3);
    });

    test('an overwritten seq still waits for an earlier pending one', () async {
      final pending = await stamp.next(); // 1, written later
      final created = await stamp.next(); // 2
      await write(created);
      final renamed = await stamp.next(); // 3
      await (db.update(db.tracks)..where((t) => t.id.equals(created.id))).write(
        TracksCompanion(localSeq: Value(renamed.localSeq)),
      );
      expect(await feed.safeHigh(), 0);
      await write(pending);
      expect(await feed.safeHigh(), 3);
    });

    test('seqs reserved for applied rows do not hold it', () async {
      await stamp.reserve(1); // 1, the applier writes it in its transaction
      await write(await stamp.next()); // 2
      expect(await feed.safeHigh(), 2);
    });

    test('seqs above highSeq do not hold it', () async {
      await write(await stamp.next()); // 1
      await stamp.nextMany(3); // 2..4, not written yet
      expect(await feed.safeHigh(), 1);
    });
  });
}
