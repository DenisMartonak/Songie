import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../core/fractional_index.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';

const _maxNameLength = 100;

/// One row of the playlist list.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.source,
    required this.trackCount,
    required this.durationMs,
    required this.coverRef,
  });

  final String id;
  final String name;
  final String source;

  /// Live entries whose track is not deleted.
  final int trackCount;
  final int durationMs;

  /// The playlist's own cover, else the first track's artwork.
  final String? coverRef;
}

/// One entry of a playlist together with its track.
class PlaylistTrack {
  const PlaylistTrack({
    required this.entryId,
    required this.track,
    required this.position,
    required this.status,
    required this.fileMissing,
  });

  final String entryId;
  final Track track;
  final String position;
  final String status;

  /// True when this device's local file for the track is marked missing.
  final bool fileMissing;
}

/// The only writer of playlist data. Every write stamps sync metadata
/// (`clock`, `originDevice`, `localSeq`) with one [SyncStamp.next] per row and
/// runs in a single transaction.
class LibraryRepository {
  LibraryRepository(this._db, this._stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;

  Stream<List<PlaylistSummary>> watchPlaylists() {
    const liveEntries =
        'FROM playlist_entries e JOIN tracks t ON t.id = e.track_id '
        'WHERE e.playlist_id = p.id AND e.deleted = 0 AND t.deleted = 0';
    final query = _db.customSelect(
      'SELECT p.id, p.name, p.source, p.cover_ref, '
      '(SELECT COUNT(*) $liveEntries) AS track_count, '
      '(SELECT COALESCE(SUM(t.duration_ms), 0) $liveEntries) AS duration_ms, '
      '(SELECT t.artwork_ref $liveEntries '
      'ORDER BY e.position, e.id LIMIT 1) AS first_artwork '
      'FROM playlists p WHERE p.deleted = 0',
      readsFrom: {_db.playlists, _db.playlistEntries, _db.tracks},
    );
    return query.watch().map((rows) {
      final list = [
        for (final r in rows)
          PlaylistSummary(
            id: r.read<String>('id'),
            name: r.read<String>('name'),
            source: r.read<String>('source'),
            trackCount: r.read<int>('track_count'),
            durationMs: r.read<int>('duration_ms'),
            coverRef:
                r.readNullable<String>('cover_ref') ??
                r.readNullable<String>('first_artwork'),
          ),
      ];
      list.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
      return list;
    });
  }

  Stream<List<PlaylistTrack>> watchPlaylistTracks(String playlistId) {
    final query =
        _db.select(_db.playlistEntries).join([
            innerJoin(
              _db.tracks,
              _db.tracks.id.equalsExp(_db.playlistEntries.trackId),
            ),
            leftOuterJoin(
              _db.localFiles,
              _db.localFiles.trackId.equalsExp(_db.playlistEntries.trackId),
            ),
          ])
          ..where(
            _db.playlistEntries.playlistId.equals(playlistId) &
                _db.playlistEntries.deleted.equals(false) &
                _db.tracks.deleted.equals(false),
          )
          ..orderBy([
            OrderingTerm.asc(_db.playlistEntries.position),
            OrderingTerm.asc(_db.playlistEntries.id),
          ]);
    return query.watch().map((rows) {
      return [
        for (final r in rows)
          PlaylistTrack(
            entryId: r.readTable(_db.playlistEntries).id,
            track: r.readTable(_db.tracks),
            position: r.readTable(_db.playlistEntries).position,
            status: r.readTable(_db.playlistEntries).status,
            fileMissing: r.readTableOrNull(_db.localFiles)?.state == 'missing',
          ),
      ];
    });
  }

  Future<Result<String>> createPlaylist(String name) async {
    final clean = _cleanName(name);
    if (clean == null) return _badName<String>();
    return _guard(() async {
      final stamp = await _stamp.next();
      await _db
          .into(_db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: stamp.id,
              clock: stamp.clock,
              originDevice: stamp.originDevice,
              localSeq: stamp.localSeq,
              name: clean,
              source: 'local',
            ),
          );
      return Ok(stamp.id);
    });
  }

  Future<Result<void>> renamePlaylist(String id, String name) async {
    final clean = _cleanName(name);
    if (clean == null) return _badName<void>();
    return _guard(() async {
      if (await _livePlaylist(id) == null) return _notFound('playlist $id');
      final stamp = await _stamp.next();
      await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(
          name: Value(clean),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// Tombstones the playlist and all its live entries, each with its own stamp.
  Future<Result<void>> deletePlaylist(String id) {
    return _guard(() async {
      if (await _livePlaylist(id) == null) return _notFound('playlist $id');
      final entryIds =
          await (_db.selectOnly(_db.playlistEntries)
                ..addColumns([_db.playlistEntries.id])
                ..where(
                  _db.playlistEntries.playlistId.equals(id) &
                      _db.playlistEntries.deleted.equals(false),
                ))
              .map((r) => r.read(_db.playlistEntries.id)!)
              .get();
      for (final entryId in entryIds) {
        await _tombstoneEntry(entryId);
      }
      final stamp = await _stamp.next();
      await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(
          deleted: const Value(true),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// Appends [trackIds] (duplicates allowed) after the playlist's last entry.
  Future<Result<void>> addTracks(String playlistId, List<String> trackIds) {
    return _guard(() async {
      if (await _livePlaylist(playlistId) == null) {
        return _notFound('playlist $playlistId');
      }
      if (trackIds.isEmpty) return const Ok(null);

      final wanted = trackIds.toSet();
      final found =
          await (_db.selectOnly(_db.tracks)
                ..addColumns([_db.tracks.id])
                ..where(
                  _db.tracks.id.isIn(wanted) & _db.tracks.deleted.equals(false),
                ))
              .map((r) => r.read(_db.tracks.id)!)
              .get();
      final unknown = wanted.difference(found.toSet());
      if (unknown.isNotEmpty) {
        return _notFound('track ${unknown.first}');
      }

      final last =
          await (_db.select(_db.playlistEntries)
                ..where(
                  (e) =>
                      e.playlistId.equals(playlistId) & e.deleted.equals(false),
                )
                ..orderBy([
                  (e) => OrderingTerm.desc(e.position),
                  (e) => OrderingTerm.desc(e.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      final positions = nKeysBetween(last?.position, null, trackIds.length);
      final now = DateTime.now();
      for (var i = 0; i < trackIds.length; i++) {
        final stamp = await _stamp.next();
        await _db
            .into(_db.playlistEntries)
            .insert(
              PlaylistEntriesCompanion.insert(
                id: stamp.id,
                clock: stamp.clock,
                originDevice: stamp.originDevice,
                localSeq: stamp.localSeq,
                playlistId: playlistId,
                trackId: trackIds[i],
                position: positions[i],
                addedAt: now,
              ),
            );
      }
      return const Ok(null);
    });
  }

  /// Moves [entryId] between [afterEntryId] (null = start) and
  /// [beforeEntryId] (null = end). Only the moved row is written.
  Future<Result<void>> moveEntry(
    String entryId, {
    String? afterEntryId,
    String? beforeEntryId,
  }) {
    return _guard(() async {
      final entry = await _liveEntry(entryId);
      if (entry == null) return _notFound('entry $entryId');

      Future<Result<String?>> neighbourPosition(String? id) async {
        if (id == null) return const Ok(null);
        final n = id == entryId ? null : await _liveEntry(id);
        if (n == null || n.playlistId != entry.playlistId) {
          return Err(
            Failure(
              FailureKind.invalidInput,
              'Entry $id is not another live entry of the same playlist',
            ),
          );
        }
        return Ok(n.position);
      }

      final after = await neighbourPosition(afterEntryId);
      if (after case Err(:final failure)) return Err(failure);
      final before = await neighbourPosition(beforeEntryId);
      if (before case Err(:final failure)) return Err(failure);

      final String position;
      try {
        position = keyBetween(
          (after as Ok<String?>).value,
          (before as Ok<String?>).value,
        );
      } on ArgumentError {
        return const Err(
          Failure(
            FailureKind.invalidInput,
            'Neighbouring entries are not in ascending order',
          ),
        );
      }

      final stamp = await _stamp.next();
      await (_db.update(
        _db.playlistEntries,
      )..where((e) => e.id.equals(entryId))).write(
        PlaylistEntriesCompanion(
          position: Value(position),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  Future<Result<void>> removeEntry(String entryId) {
    return _guard(() async {
      if (await _liveEntry(entryId) == null) return _notFound('entry $entryId');
      await _tombstoneEntry(entryId);
      return const Ok(null);
    });
  }

  Future<Track?> trackById(String id) {
    return (_db.select(_db.tracks)
          ..where((t) => t.id.equals(id) & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  // --- helpers -------------------------------------------------------------

  /// Runs [body] in one transaction, turning database errors into [Err].
  Future<Result<T>> _guard<T>(Future<Result<T>> Function() body) async {
    try {
      return await _db.transaction(body);
    } on SqliteException catch (e) {
      return Err(
        Failure(FailureKind.io, 'Database error: ${e.message}', cause: e),
      );
    }
  }

  Future<Playlist?> _livePlaylist(String id) {
    return (_db.select(_db.playlists)
          ..where((p) => p.id.equals(id) & p.deleted.equals(false)))
        .getSingleOrNull();
  }

  Future<PlaylistEntry?> _liveEntry(String id) {
    return (_db.select(_db.playlistEntries)
          ..where((e) => e.id.equals(id) & e.deleted.equals(false)))
        .getSingleOrNull();
  }

  Future<void> _tombstoneEntry(String entryId) async {
    final stamp = await _stamp.next();
    await (_db.update(
      _db.playlistEntries,
    )..where((e) => e.id.equals(entryId))).write(
      PlaylistEntriesCompanion(
        deleted: const Value(true),
        clock: Value(stamp.clock),
        originDevice: Value(stamp.originDevice),
        localSeq: Value(stamp.localSeq),
      ),
    );
  }

  /// Trimmed name, or null when it is not 1-100 characters.
  String? _cleanName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > _maxNameLength) return null;
    return trimmed;
  }

  Err<T> _badName<T>() => Err(
    const Failure(
      FailureKind.invalidInput,
      'Playlist name must be 1-$_maxNameLength characters',
    ),
  );

  Err<T> _notFound<T>(String what) =>
      Err(Failure(FailureKind.notFound, 'No such $what'));
}
