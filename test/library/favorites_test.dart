import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/library/library_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late FavoritesRepository favs;
  late LibraryRepository repo;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    favs = FavoritesRepository(db, stamp);
    repo = LibraryRepository(db, stamp);
    for (final id in ['a', 'b']) {
      await db.into(db.tracks).insert(trackRow(id: id));
    }
  });
  tearDown(() => db.close());

  Future<Playlist> playlist() => (db.select(
    db.playlists,
  )..where((p) => p.id.equals(kFavoritesPlaylistId))).getSingle();

  Future<List<PlaylistEntry>> live() =>
      (db.select(db.playlistEntries)
            ..where(
              (e) =>
                  e.playlistId.equals(kFavoritesPlaylistId) &
                  e.deleted.equals(false),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.position)]))
          .get();

  group('ensureFavorites', () {
    test('creates a live Favorites once', () async {
      await favs.ensureFavorites();
      final p = await playlist();
      expect(p.name, 'Favorites');
      expect(p.deleted, isFalse);
      expect(p.source, 'local');
      await favs.ensureFavorites();
      expect((await playlist()).clock, p.clock);
    });

    test('brings back a deleted or renamed Favorites', () async {
      await favs.ensureFavorites();
      for (final broken in [
        const PlaylistsCompanion(deleted: Value(true)),
        const PlaylistsCompanion(name: Value('Faves')),
      ]) {
        await (db.update(
          db.playlists,
        )..where((p) => p.id.equals(kFavoritesPlaylistId))).write(broken);
        final before = await playlist();
        await favs.ensureFavorites();
        final after = await playlist();
        expect(after.deleted, isFalse);
        expect(after.name, 'Favorites');
        expect(after.clock, isNot(before.clock));
      }
    });
  });

  group('star', () {
    setUp(() => favs.ensureFavorites());

    test('the newest star is first', () async {
      await favs.star('a');
      await favs.star('b');
      expect((await live()).map((e) => e.id), [
        favoriteEntryId('b'),
        favoriteEntryId('a'),
      ]);
    });

    test('starring twice is one entry, unchanged', () async {
      await favs.star('a');
      final first = (await live()).single;
      await favs.star('a');
      final again = (await live()).single;
      expect(again.clock, first.clock);
    });

    test('star, unstar, star is one live entry at the top', () async {
      await favs.star('b');
      await favs.star('a');
      await favs.unstar('a');
      expect((await live()).map((e) => e.trackId), ['b']);
      await favs.star('a');
      expect((await live()).map((e) => e.id), [
        favoriteEntryId('a'),
        favoriteEntryId('b'),
      ]);
      final all = await (db.select(
        db.playlistEntries,
      )..where((e) => e.trackId.equals('a'))).get();
      expect(all, hasLength(1));
    });

    test('toggle answers the new state', () async {
      expect(
        await favs.toggle('a'),
        isA<Ok<bool>>().having((r) => r.value, 'v', true),
      );
      expect(
        await favs.toggle('a'),
        isA<Ok<bool>>().having((r) => r.value, 'v', false),
      );
    });

    test('watchIds follows the stars', () async {
      final seen = <Set<String>>[];
      final sub = favs.watchIds().listen(seen.add);
      await pumpEventQueue();
      await favs.star('a');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, <String>{});
      expect(seen.last, {'a'});
    });
  });

  group('the library', () {
    setUp(() => favs.ensureFavorites());

    test('Favorites cannot be renamed or deleted', () async {
      final rename = await repo.renamePlaylist(kFavoritesPlaylistId, 'x');
      final delete = await repo.deletePlaylist(kFavoritesPlaylistId);
      expect((rename as Err).failure.kind, FailureKind.invalidInput);
      expect((delete as Err).failure.kind, FailureKind.invalidInput);
      final p = await playlist();
      expect(p.name, 'Favorites');
      expect(p.deleted, isFalse);
    });

    test('Favorites is listed first', () async {
      await repo.createPlaylist('Aaa');
      final list = await repo.watchPlaylists().first;
      expect(list.first.id, kFavoritesPlaylistId);
      expect(list.map((p) => p.name), ['Favorites', 'Aaa']);
    });
  });
}
