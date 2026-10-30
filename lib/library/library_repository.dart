import 'package:drift/drift.dart';

import '../core/fractional_index.dart';
import '../core/result.dart';
import '../core/text_normalize.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';

/// The longest playlist name, in UTF-16 code units.
const maxPlaylistNameLength = 100;

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

/// Live playlists with their entry count, total duration and cover, ordered
/// by name (case-insensitive). Shared by the playlist list and playlist search.
Stream<List<PlaylistSummary>> watchPlaylistSummaries(AppDatabase db) {
  const liveEntries =
      'FROM playlist_entries e JOIN tracks t ON t.id = e.track_id '
      'WHERE e.playlist_id = p.id AND e.deleted = 0 AND t.deleted = 0';
  final query = db.customSelect(
    'SELECT p.id, p.name, p.source, p.cover_ref, '
    '(SELECT COUNT(*) $liveEntries) AS track_count, '
    '(SELECT COALESCE(SUM(t.duration_ms), 0) $liveEntries) AS duration_ms, '
    '(SELECT t.artwork_ref $liveEntries '
    'ORDER BY e.position, e.id LIMIT 1) AS first_artwork '
    'FROM playlists p WHERE p.deleted = 0',
    readsFrom: {db.playlists, db.playlistEntries, db.tracks},
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

/// The only writer of playlist data. Every write stamps sync metadata
/// (`clock`, `originDevice`, `localSeq`) with one [SyncStamp.next] per row and
/// runs in a single transaction.
class LibraryRepository {
  LibraryRepository(this._db, this._stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;

  Stream<List<PlaylistSummary>> watchPlaylists() => watchPlaylistSummaries(_db);

  /// The scanned music folders, by path.
  Stream<List<LibraryFolder>> watchFolders() => (_db.select(
    _db.libraryFolders,
  )..orderBy([(f) => OrderingTerm.asc(f.path)])).watch();

  /// Forgets a music folder. Its tracks stay in the library. The table is
  /// device-local (not synced), so the row is deleted outright.
  Future<void> removeFolder(String path) =>
      (_db.delete(_db.libraryFolders)..where((f) => f.path.equals(path))).go();

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
            // Only local-library tracks can be "missing"; a YouTube track
            // without a finished download simply streams.
            fileMissing:
                r.readTable(_db.tracks).source != 'yt' &&
                r.readTableOrNull(_db.localFiles)?.state == 'missing',
          ),
      ];
    });
  }

  Future<Result<String>> createPlaylist(String name) async {
    final clean = _cleanName(name);
    if (clean == null) return _badName<String>();
    return guardDb(_db, () async {
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
    return guardDb(_db, () async {
      if (await _livePlaylist(id) == null) return _notFound('playlist $id');
      final stamp = await _stamp.next(id: id);
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
    return guardDb(_db, () async {
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
      final stamp = await _stamp.next(id: id);
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
    return guardDb(_db, () async {
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
    return guardDb(_db, () async {
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

      final stamp = await _stamp.next(id: entryId);
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
    return guardDb(_db, () async {
      if (await _liveEntry(entryId) == null) return _notFound('entry $entryId');
      await _tombstoneEntry(entryId);
      return const Ok(null);
    });
  }

  /// Marks a (possibly `removed_on_yt`) entry as kept: sync will never flag
  /// it again. Sets `status='active'` and `kept=true`.
  Future<Result<void>> keepEntry(String entryId) {
    return guardDb(_db, () async {
      if (await _liveEntry(entryId) == null) return _notFound('entry $entryId');
      final stamp = await _stamp.next(id: entryId);
      await (_db.update(
        _db.playlistEntries,
      )..where((e) => e.id.equals(entryId))).write(
        PlaylistEntriesCompanion(
          status: const Value('active'),
          kept: const Value(true),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// The live playlist [id] and its later changes (null once deleted).
  Stream<Playlist?> watchPlaylist(String id) {
    return (_db.select(_db.playlists)
          ..where((p) => p.id.equals(id) & p.deleted.equals(false)))
        .watchSingleOrNull();
  }

  /// The live YouTube playlist imported from [canonicalUrl], if any.
  Future<Playlist?> findPlaylistByYtUrl(String canonicalUrl) {
    return (_db.select(_db.playlists)
          ..where(
            (p) =>
                p.ytPlaylistUrl.equals(canonicalUrl) &
                p.source.equals('yt') &
                p.deleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Points [entryId] at a different track (e.g. after the user located a
  /// moved file). Err(notFound) for an unknown or deleted entry or track.
  Future<Result<void>> replaceEntryTrack(String entryId, String trackId) {
    return guardDb(_db, () async {
      if (await _liveEntry(entryId) == null) return _notFound('entry $entryId');
      if (await trackById(trackId) == null) return _notFound('track $trackId');
      final stamp = await _stamp.next(id: entryId);
      await (_db.update(
        _db.playlistEntries,
      )..where((e) => e.id.equals(entryId))).write(
        PlaylistEntriesCompanion(
          trackId: Value(trackId),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// Updates rough metadata of a track (e.g. from a resolved stream). Only
  /// non-null fields that differ from the stored value are written, stamped;
  /// nothing is written (and no stamp issued) when nothing changed.
  Future<Result<void>> updateTrackMetadata(
    String trackId, {
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    return guardDb(_db, () async {
      final t = await trackById(trackId);
      if (t == null) return _notFound('track $trackId');
      final newTitle = title != null && title != t.title ? title : null;
      final newArtist = artist != null && artist != t.artist ? artist : null;
      final newAlbum = album != null && album != t.album ? album : null;
      final newDuration = durationMs != null && durationMs != t.durationMs
          ? durationMs
          : null;
      if (newTitle == null &&
          newArtist == null &&
          newAlbum == null &&
          newDuration == null) {
        return const Ok(null);
      }
      final stamp = await _stamp.next(id: trackId);
      await (_db.update(_db.tracks)..where((r) => r.id.equals(trackId))).write(
        TracksCompanion(
          title: Value.absentIfNull(newTitle),
          artist: Value.absentIfNull(newArtist),
          album: Value.absentIfNull(newAlbum),
          durationMs: Value.absentIfNull(newDuration),
          searchText: newTitle != null || newArtist != null
              ? Value(
                  normalizeForSearch(
                    '${newTitle ?? t.title} ${newArtist ?? t.artist}',
                  ),
                )
              : const Value.absent(),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// Flags a track as unplayable (e.g. a YouTube video that is gone). Stamped;
  /// a no-op when it is already flagged.
  Future<Result<void>> markUnavailable(String trackId) {
    return guardDb(_db, () async {
      final t = await trackById(trackId);
      if (t == null) return _notFound('track $trackId');
      if (t.unavailable) return const Ok(null);
      final stamp = await _stamp.next(id: trackId);
      await (_db.update(_db.tracks)..where((r) => r.id.equals(trackId))).write(
        TracksCompanion(
          unavailable: const Value(true),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return const Ok(null);
    });
  }

  /// The ids of the tracks [playlistId] holds now (removed entries left out).
  Future<Set<String>> trackIdsIn(String playlistId) async {
    final rows =
        await (_db.selectOnly(_db.playlistEntries)
              ..addColumns([_db.playlistEntries.trackId])
              ..where(
                _db.playlistEntries.playlistId.equals(playlistId) &
                    _db.playlistEntries.deleted.equals(false),
              ))
            .map((r) => r.read(_db.playlistEntries.trackId)!)
            .get();
    return rows.toSet();
  }

  Future<Track?> trackById(String id) {
    return (_db.select(_db.tracks)
          ..where((t) => t.id.equals(id) & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  // --- helpers -------------------------------------------------------------

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
    final stamp = await _stamp.next(id: entryId);
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
    if (trimmed.isEmpty || trimmed.length > maxPlaylistNameLength) return null;
    return trimmed;
  }

  Err<T> _badName<T>() => Err(
    const Failure(
      FailureKind.invalidInput,
      'Playlist name must be 1-$maxPlaylistNameLength characters',
    ),
  );

  Err<T> _notFound<T>(String what) =>
      Err(Failure(FailureKind.notFound, 'No such $what'));
}
