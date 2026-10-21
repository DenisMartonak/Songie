import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/play_history_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late PlayHistoryRepository history;

  setUp(() async {
    db = testDb();
    history = PlayHistoryRepository(db);
    for (final id in ['a', 'b', 'c']) {
      await db.into(db.tracks).insert(trackRow(id: id, title: 'Song $id'));
    }
  });
  tearDown(() => db.close());

  Future<List<String>> recent(int n) async => [
    for (final t in await history.recentTracks(n).first) t.id,
  ];

  test('recentTracks lists distinct tracks, newest first', () async {
    await history.record('a', null);
    await history.record('b', null);
    await history.record('a', null);
    expect(await recent(10), ['a', 'b']);
    expect(await recent(1), ['a']);
  });

  test('recentTracks skips deleted tracks', () async {
    await history.record('a', null);
    await history.record('b', null);
    await (db.update(db.tracks)..where((t) => t.id.equals('b'))).write(
      const TracksCompanion(deleted: Value(true)),
    );
    expect(await recent(10), ['a']);
  });

  test('recentPlaylistIds are distinct, newest first, without nulls', () async {
    for (final id in ['p1', 'p2']) {
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: id,
              clock: 'c',
              originDevice: 'dev',
              localSeq: 1,
              name: id,
              source: 'local',
            ),
          );
    }
    await history.record('a', 'p1');
    await history.record('b', null);
    await history.record('c', 'p2');
    await history.record('a', 'p1');
    expect(await history.recentPlaylistIds(10).first, ['p1', 'p2']);
    expect(await history.recentPlaylistIds(1).first, ['p1']);

    // A deleted playlist drops out.
    await (db.update(db.playlists)..where((p) => p.id.equals('p1'))).write(
      const PlaylistsCompanion(deleted: Value(true)),
    );
    expect(await history.recentPlaylistIds(10).first, ['p2']);
  });

  test('keeps only the newest 200 rows', () async {
    for (var i = 0; i < 205; i++) {
      await history.record(i < 5 ? 'a' : 'b', i < 5 ? 'old' : null);
    }
    final rows = await db.select(db.playHistory).get();
    expect(rows, hasLength(PlayHistoryRepository.maxRows));
    expect(rows.every((r) => r.trackId == 'b'), isTrue);
    expect(await history.recentPlaylistIds(10).first, isEmpty);
  });

  test('streams update when something is recorded', () async {
    final seen = <List<String>>[];
    final sub = history
        .recentTracks(10)
        .listen((tracks) => seen.add([for (final t in tracks) t.id]));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await history.record('c', null);
    await pumpEventQueue();
    expect(seen.first, isEmpty);
    expect(seen.last, ['c']);
  });
}
