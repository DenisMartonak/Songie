import 'package:drift/drift.dart';

import '../core/fractional_index.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';

/// The built-in Favorites playlist's id: the same on every device, so two
/// devices' Favorites are one playlist after a sync.
const kFavoritesPlaylistId = 'favorites';

/// Its name; it can't be renamed.
const kFavoritesName = 'Favorites';

/// A favorite's entry id: one per song, the same on every device, so a star
/// and an un-star on two devices settle by last writer.
String favoriteEntryId(String trackId) => 'fav-$trackId';

/// Stars and un-stars songs: entries of the Favorites playlist, newest
/// first. Every write is stamped like the library's own.
class FavoritesRepository {
  FavoritesRepository(this._db, this._stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;

  /// Creates Favorites if it's missing; brings it back (live, named
  /// Favorites) if a sync deleted or renamed it.
  Future<Result<void>> ensureFavorites() => guardDb(_db, () async {
    final p = await _playlist();
    if (p != null && !p.deleted && p.name == kFavoritesName) {
      return const Ok(null);
    }
    final st = await _stamp.next(id: kFavoritesPlaylistId);
    await _db
        .into(_db.playlists)
        .insertOnConflictUpdate(
          PlaylistsCompanion(
            id: const Value(kFavoritesPlaylistId),
            clock: Value(st.clock),
            originDevice: Value(st.originDevice),
            localSeq: Value(st.localSeq),
            deleted: const Value(false),
            name: const Value(kFavoritesName),
            source: const Value('local'),
            coverRef: Value(p?.coverRef),
          ),
        );
    return const Ok(null);
  });

  /// Adds [trackId] to the top of Favorites; nothing when it's there.
  Future<Result<void>> star(String trackId) => guardDb(_db, () async {
    final id = favoriteEntryId(trackId);
    final entry = await (_db.select(
      _db.playlistEntries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (entry != null && !entry.deleted) return const Ok(null);
    final first =
        await (_db.select(_db.playlistEntries)
              ..where(
                (e) =>
                    e.playlistId.equals(kFavoritesPlaylistId) &
                    e.deleted.equals(false),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.position)])
              ..limit(1))
            .getSingleOrNull();
    final st = await _stamp.next(id: id);
    await _db
        .into(_db.playlistEntries)
        .insertOnConflictUpdate(
          PlaylistEntriesCompanion(
            id: Value(id),
            clock: Value(st.clock),
            originDevice: Value(st.originDevice),
            localSeq: Value(st.localSeq),
            deleted: const Value(false),
            playlistId: const Value(kFavoritesPlaylistId),
            trackId: Value(trackId),
            position: Value(keyBetween(null, first?.position)),
            addedAt: Value(DateTime.now()),
          ),
        );
    return const Ok(null);
  });

  /// Removes [trackId] from Favorites; nothing when it isn't there.
  Future<Result<void>> unstar(String trackId) => guardDb(_db, () async {
    final id = favoriteEntryId(trackId);
    final entry = await (_db.select(
      _db.playlistEntries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (entry == null || entry.deleted) return const Ok(null);
    final st = await _stamp.next(id: id);
    await (_db.update(
      _db.playlistEntries,
    )..where((e) => e.id.equals(id))).write(
      PlaylistEntriesCompanion(
        deleted: const Value(true),
        clock: Value(st.clock),
        originDevice: Value(st.originDevice),
        localSeq: Value(st.localSeq),
      ),
    );
    return const Ok(null);
  });

  /// Stars or un-stars [trackId]; Ok(true) when it is now a favorite.
  Future<Result<bool>> toggle(String trackId) async {
    final ids = await watchIds().first;
    final starring = !ids.contains(trackId);
    final r = starring ? await star(trackId) : await unstar(trackId);
    return switch (r) {
      Ok() => Ok(starring),
      Err(:final failure) => Err(failure),
    };
  }

  /// The ids of the songs in Favorites.
  Stream<Set<String>> watchIds() =>
      (_db.selectOnly(_db.playlistEntries)
            ..addColumns([_db.playlistEntries.trackId])
            ..where(
              _db.playlistEntries.playlistId.equals(kFavoritesPlaylistId) &
                  _db.playlistEntries.deleted.equals(false),
            ))
          .map((r) => r.read(_db.playlistEntries.trackId)!)
          .watch()
          .map((ids) => ids.toSet());

  Future<Playlist?> _playlist() => (_db.select(
    _db.playlists,
  )..where((p) => p.id.equals(kFavoritesPlaylistId))).getSingleOrNull();
}
