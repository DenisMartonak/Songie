import 'package:drift/drift.dart';

import '../data/database.dart';

/// Device-local record of what started playing, for Home's quick tiles and
/// "Recently played". Not synced.
class PlayHistoryRepository {
  PlayHistoryRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// How many rows are kept; older ones are pruned on every insert.
  static const int maxRows = 200;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// Notes that [trackId] started playing (from [playlistId], if any) and
  /// prunes the history to the newest [maxRows] rows.
  Future<void> record(String trackId, String? playlistId) {
    return _db.transaction(() async {
      await _db
          .into(_db.playHistory)
          .insert(
            PlayHistoryCompanion.insert(
              trackId: trackId,
              playlistId: Value(playlistId),
              playedAt: _now(),
            ),
          );
      await _db.customUpdate(
        'DELETE FROM play_history WHERE id NOT IN '
        '(SELECT id FROM play_history ORDER BY id DESC LIMIT ?)',
        variables: [Variable<int>(maxRows)],
        updates: {_db.playHistory},
      );
    });
  }

  /// The last [n] distinct live tracks played, newest first.
  Stream<List<Track>> recentTracks(int n) {
    final query = _db.customSelect(
      'SELECT t.* FROM tracks t JOIN '
      '(SELECT track_id, MAX(id) AS last FROM play_history GROUP BY track_id) h '
      'ON h.track_id = t.id WHERE t.deleted = 0 '
      'ORDER BY h.last DESC LIMIT ?',
      variables: [Variable<int>(n)],
      readsFrom: {_db.playHistory, _db.tracks},
    );
    return query.watch().map(
      (rows) => [for (final r in rows) _db.tracks.map(r.data)],
    );
  }

  /// The last [n] distinct live playlists a track was played from, newest
  /// first.
  Stream<List<String>> recentPlaylistIds(int n) {
    final query = _db.customSelect(
      'SELECT h.playlist_id FROM '
      '(SELECT playlist_id, MAX(id) AS last FROM play_history '
      'WHERE playlist_id IS NOT NULL GROUP BY playlist_id) h '
      'JOIN playlists p ON p.id = h.playlist_id WHERE p.deleted = 0 '
      'ORDER BY h.last DESC LIMIT ?',
      variables: [Variable<int>(n)],
      readsFrom: {_db.playHistory, _db.playlists},
    );
    return query.watch().map(
      (rows) => [for (final r in rows) r.read<String>('playlist_id')],
    );
  }
}
