import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/change_feed.dart';

import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = testDb());
  tearDown(() => db.close());

  test('since pages across all tables in seq order', () async {
    await seedOneOfEach(db); // seqs 1..8
    await db.into(db.tracks).insert(trackRow(id: 'x', localSeq: 9));
    await db.into(db.tracks).insert(trackRow(id: 'y', localSeq: 10));
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
    expect(seen, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(await feed.highSeq(), 10);
  });

  test('since excludes rows at or below seq', () async {
    await seedOneOfEach(db);
    final page = await ChangeFeed(db).since(5);
    expect(page.rows.map((r) => r.localSeq), [6, 7, 8]);
    expect(page.next, isNull);
    expect((await ChangeFeed(db).since(8)).rows, isEmpty);
  });

  test('highSeq is 0 for an empty database', () async {
    expect(await ChangeFeed(db).highSeq(), 0);
  });

  test('snapshot maps wire/id to content hash', () async {
    await seedOneOfEach(db);
    final snap = await snapshot(db);
    expect(snap.length, 8);
    expect(snap.keys.first, startsWith('tracks/'));
  });
}
