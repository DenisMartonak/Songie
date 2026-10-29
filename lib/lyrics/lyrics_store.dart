import 'package:drift/drift.dart';

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import 'lyrics.dart';

/// Lyrics read back from the store, with when they were fetched.
class StoredLyrics {
  const StoredLyrics(this.lyrics, this.fetchedAt);

  final TrackLyrics lyrics;
  final DateTime fetchedAt;
}

/// One stamped `lyrics` row per track (the row id is the track id).
class LyricsStore {
  LyricsStore(this._db, this._stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;

  /// The stored lyrics for [trackId], or null if there is no row or it is
  /// deleted.
  Future<StoredLyrics?> read(String trackId) async {
    final row =
        await (_db.select(_db.lyrics)
              ..where((t) => t.id.equals(trackId) & t.deleted.equals(false)))
            .getSingleOrNull();
    if (row == null) return null;
    return StoredLyrics(
      TrackLyrics.fromStored(row.kind, row.body, row.source),
      row.fetchedAt,
    );
  }

  /// Upserts the row for [trackId] (clearing a tombstone). Lyrics read from a
  /// file are never stored. Never throws.
  Future<void> write(String trackId, TrackLyrics l, DateTime fetchedAt) async {
    if (l.source == LyricsSource.file) return;
    try {
      final stored = l.toStored();
      final r = await guardDb<void>(_db, () async {
        final st = await _stamp.next(id: trackId);
        await _db
            .into(_db.lyrics)
            .insertOnConflictUpdate(
              LyricsCompanion.insert(
                id: trackId,
                clock: st.clock,
                originDevice: st.originDevice,
                localSeq: st.localSeq,
                deleted: const Value(false),
                kind: stored.kind,
                body: stored.body,
                source: Value(l.source?.name),
                fetchedAt: fetchedAt,
              ),
            );
        return const Ok(null);
      });
      if (r is Err<void>) AppLog.w('Lyrics write failed: ${r.failure.message}');
    } catch (e, s) {
      AppLog.w('Lyrics write failed unexpectedly', e, s);
    }
  }
}
