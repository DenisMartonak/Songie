import 'package:drift/drift.dart';

import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import '../innertube/ytm_models.dart';

/// The row id of a saved artist.
String savedArtistId(String browseId) => 'artist:$browseId';

/// Artists the user saved from YouTube Music, synced between devices.
class SavedArtistsRepository {
  SavedArtistsRepository(this._db, this._stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;

  /// Saved artists, newest first.
  Stream<List<SavedArtist>> watchAll() =>
      (_db.select(_db.savedArtists)
            ..where((a) => a.deleted.equals(false))
            ..orderBy([(a) => OrderingTerm.desc(a.savedAt)]))
          .watch();

  Stream<bool> watchIsSaved(String browseId) =>
      (_db.select(_db.savedArtists)..where(
            (a) =>
                a.id.equals(savedArtistId(browseId)) & a.deleted.equals(false),
          ))
          .watch()
          .map((rows) => rows.isNotEmpty);

  Future<Result<void>> save(YtmArtist artist) => guardDb(_db, () async {
    final id = savedArtistId(artist.browseId);
    final stamp = await _stamp.next(id: id);
    await _db
        .into(_db.savedArtists)
        .insertOnConflictUpdate(
          SavedArtistsCompanion.insert(
            id: id,
            clock: stamp.clock,
            originDevice: stamp.originDevice,
            localSeq: stamp.localSeq,
            browseId: artist.browseId,
            name: artist.name,
            thumbnailUrl: Value(artist.thumbnailUrl),
            savedAt: DateTime.now().toUtc(),
            // Explicit: a re-save must clear the tombstone.
            deleted: const Value(false),
          ),
        );
    return const Ok(null);
  });

  Future<Result<void>> unsave(String browseId) => guardDb(_db, () async {
    final id = savedArtistId(browseId);
    final stamp = await _stamp.next(id: id);
    await (_db.update(_db.savedArtists)..where((a) => a.id.equals(id))).write(
      SavedArtistsCompanion(
        deleted: const Value(true),
        clock: Value(stamp.clock),
        originDevice: Value(stamp.originDevice),
        localSeq: Value(stamp.localSeq),
      ),
    );
    return const Ok(null);
  });

  /// Updates the name and thumbnail of a saved artist when either changed.
  Future<void> refresh(YtmArtist artist) async {
    await guardDb(_db, () async {
      final id = savedArtistId(artist.browseId);
      final row =
          await (_db.select(_db.savedArtists)
                ..where((a) => a.id.equals(id) & a.deleted.equals(false)))
              .getSingleOrNull();
      if (row == null ||
          (row.name == artist.name &&
              row.thumbnailUrl == artist.thumbnailUrl)) {
        return const Ok(null);
      }
      final stamp = await _stamp.next(id: id);
      await (_db.update(_db.savedArtists)..where((a) => a.id.equals(id))).write(
        SavedArtistsCompanion(
          name: Value(artist.name),
          thumbnailUrl: Value(artist.thumbnailUrl),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }
}
