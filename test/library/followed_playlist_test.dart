import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/sync/cloud/cloud_remote.dart' show kRowFormat;

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late LibraryRepository repo;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    repo = LibraryRepository(db, stamp);
    for (final id in ['a', 'b', 'c']) {
      await db.insertTrack(trackRow(id: id, durationMs: 1000));
    }
  });
  tearDown(() => db.close());

  T ok<T>(Result<T> r) => (r as Ok<T>).value;
  bool readOnly(Result<Object?> r) =>
      r is Err<Object?> && r.failure.kind == FailureKind.readOnly;

  Future<List<String>> trackIdsOf(String id) async => [
    for (final e in await repo.watchPlaylistTracks(id).first) e.track.id,
  ];

  Future<Playlist> row(String id) =>
      (db.select(db.playlists)..where((p) => p.id.equals(id))).getSingle();

  Future<String> followed() async {
    final id = ok(
      await repo.createFollowedPlaylist(
        code: 'ABCDEFGH2345',
        name: 'Gym',
        owner: 'den',
      ),
    );
    ok(
      await repo.applySnapshot(
        id,
        name: 'Gym',
        trackIds: const ['a', 'b'],
        updatedAt: DateTime.utc(2026, 11, 13),
      ),
    );
    return id;
  }

  test('a followed playlist refuses edits', () async {
    final id = await followed();
    final p = await row(id);
    expect(p.isFollowed, isTrue);
    expect(p.followOwner, 'den');
    final entries = await repo.watchPlaylistTracks(id).first;
    final first = entries.first.entryId;
    final second = entries.last.entryId;
    expect(readOnly(await repo.renamePlaylist(id, 'X')), isTrue);
    expect(readOnly(await repo.setPlaylistCover(id, 'art')), isTrue);
    expect(readOnly(await repo.addTracks(id, const ['c'])), isTrue);
    expect(readOnly(await repo.moveEntry(second, afterEntryId: null)), isTrue);
    expect(readOnly(await repo.removeEntry(first)), isTrue);
    expect(readOnly(await repo.keepEntry(first)), isTrue);
    expect(readOnly(await repo.replaceEntryTrack(first, 'c')), isTrue);
    expect(await trackIdsOf(id), ['a', 'b']);
    expect((await row(id)).name, 'Gym');
  });

  test(
    'applySnapshot replaces entries in order and keeps the playlist id',
    () async {
      final id = await followed();
      ok(
        await repo.applySnapshot(
          id,
          name: 'Gym 2',
          trackIds: const ['c', 'a'],
          updatedAt: DateTime.utc(2026, 11, 14),
        ),
      );
      expect(await trackIdsOf(id), ['c', 'a']);
      final p = await row(id);
      expect(p.name, 'Gym 2');
      expect(p.followUpdatedAt!.toUtc(), DateTime.utc(2026, 11, 14));
    },
  );

  test('endFollow keeps the songs and makes it editable', () async {
    final id = await followed();
    ok(await repo.endFollow(id));
    final p = await row(id);
    expect(p.isFollowed, isFalse);
    expect(p.followEnded, isTrue);
    expect(p.followOwner, 'den');
    expect(await trackIdsOf(id), ['a', 'b']);
    ok(await repo.addTracks(id, const ['c']));
    expect(await trackIdsOf(id), ['a', 'b', 'c']);
  });

  test('setShareCode marks your own playlist as shared', () async {
    final id = ok(await repo.createPlaylist('Mine'));
    ok(await repo.setShareCode(id, 'ABCDEFGH2345'));
    expect((await row(id)).shareCode, 'ABCDEFGH2345');
    ok(await repo.setShareCode(id, null));
    expect((await row(id)).shareCode, isNull);
    // Shared playlists stay editable for their owner.
    ok(await repo.renamePlaylist(id, 'Mine 2'));
  });

  test('kRowFormat goes up with the schema version', () {
    expect(kRowFormat, db.schemaVersion);
  });
}
