import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/change_feed.dart';
import 'package:songies/sync/sync_row.dart';

import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = testDb());
  tearDown(() => db.close());

  test('wire names and clash flags', () {
    expect(SyncTable.values.map((t) => t.wire), [
      'tracks',
      'playlists',
      'playlist_entries',
      'yt_seen',
      'themes',
      'fonts',
      'lyrics',
      'listens',
    ]);
    expect(SyncTable.values.where((t) => t.clashes), [
      SyncTable.playlists,
      SyncTable.playlistEntries,
    ]);
  });

  test('round-trips every table through the wire', () async {
    await seedOneOfEach(db);
    final rows = (await ChangeFeed(db).since(0)).rows;
    expect(rows.map((r) => r.table).toSet(), SyncTable.values.toSet());
    for (final r in rows) {
      final wire = jsonDecode(jsonEncode(r.toWire())) as Map<String, Object?>;
      final back = SyncRow.fromWire(wire);
      expect(back.table, r.table);
      expect(back.data, r.data, reason: r.table.wire);
      expect(back.contentHash, r.contentHash);
    }
  });

  test('toInsertable restores the row with the given seq', () async {
    await seedOneOfEach(db);
    final r = (await ChangeFeed(db).since(0)).rows.first;
    await db.delete(db.tracks).go();
    await db.into(db.tracks).insert(r.toInsertable(99) as Insertable<Track>);
    final back = (await ChangeFeed(db).since(0)).rows.last;
    expect(back.table, SyncTable.tracks);
    expect(back.localSeq, 99);
    expect(back.contentHash, r.contentHash);
  });

  test('an upsert from toInsertable sets a column back to null', () async {
    await db
        .into(db.tracks)
        .insert(trackRow(id: 't', ytVideoId: 'v', album: 'Album'));
    final r = (await ChangeFeed(db).since(0)).rows.single;
    final cleared = SyncRow(SyncTable.tracks, {
      ...r.data,
      'ytVideoId': null,
      'album': null,
    });
    await db
        .into(db.tracks)
        .insertOnConflictUpdate(cleared.toInsertable(2) as Insertable<Track>);
    final t = await db.select(db.tracks).getSingle();
    expect(t.ytVideoId, isNull);
    expect(t.album, isNull);
    expect(t.localSeq, 2);
  });

  test('content hash ignores stamps but not data or deleted', () async {
    await seedOneOfEach(db);
    final r = (await ChangeFeed(db).since(0)).rows.first;
    final restamped = r.withStamp(clock: '9-00000-other', originDevice: 'o');
    expect(restamped.clock, '9-00000-other');
    expect(restamped.originDevice, 'o');
    expect(restamped.contentHash, r.contentHash);
    expect(
      SyncRow(r.table, {...r.data, 'localSeq': 42}).contentHash,
      r.contentHash,
    );
    expect(r.contentHash, hasLength(16));
    expect(
      SyncRow(r.table, {...r.data, 'title': 'Other'}).contentHash,
      isNot(r.contentHash),
    );
    final del = SyncRow(r.table, {...r.data, 'deleted': true});
    expect(del.deleted, isTrue);
    expect(del.contentHash, isNot(r.contentHash));
  });
}
