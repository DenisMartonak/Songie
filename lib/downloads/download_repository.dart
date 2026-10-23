import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';

/// A database failure inside [DownloadRepository].
class DownloadDbException implements Exception {
  const DownloadDbException(this.failure);
  final Failure failure;

  @override
  String toString() => 'DownloadDbException(${failure.message})';
}

/// How far a playlist's downloads on this device have come.
class PlaylistDownloadStatus {
  const PlaylistDownloadStatus({
    required this.enabled,
    required this.total,
    required this.done,
    required this.queued,
    required this.downloading,
    required this.failed,
    required this.bytes,
  });

  final bool enabled;

  /// Active, available YouTube entries of the playlist.
  final int total;
  final int done;
  final int queued;
  final int downloading;
  final int failed;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is PlaylistDownloadStatus &&
      other.enabled == enabled &&
      other.total == total &&
      other.done == done &&
      other.queued == queued &&
      other.downloading == downloading &&
      other.failed == failed &&
      other.bytes == bytes;

  @override
  int get hashCode =>
      Object.hash(enabled, total, done, queued, downloading, failed, bytes);

  @override
  String toString() =>
      'PlaylistDownloadStatus(enabled: $enabled, total: $total, done: $done, '
      'queued: $queued, downloading: $downloading, failed: $failed, '
      'bytes: $bytes)';
}

/// Device-local YouTube download state: which playlists are downloaded here
/// and the queue of files, kept in `local_files` rows of YouTube tracks.
///
/// A track is *wanted* when the user asked for it (`manual`) or an active
/// entry of an enabled playlist contains it. Nothing here is synced, so no
/// SyncStamp is taken.
class DownloadRepository {
  DownloadRepository(this._db);

  final AppDatabase _db;
  int _lastRequestedAt = 0;

  static const _eq = DeepCollectionEquality();

  /// Strictly increasing, so FIFO order holds within one millisecond too.
  int _nextRequestedAt() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastRequestedAt = now > _lastRequestedAt ? now : _lastRequestedAt + 1;
    return _lastRequestedAt;
  }

  Future<T> _tx<T>(Future<T> Function() body) async {
    final r = await guardDb<T>(_db, () async => Ok(await body()));
    return switch (r) {
      Ok(:final value) => value,
      Err(:final failure) => throw DownloadDbException(failure),
    };
  }

  // --- helpers -------------------------------------------------------------

  Future<Set<String>> _enabledPlaylistIds() async {
    final prefs = await (_db.select(
      _db.playlistDevicePrefs,
    )..where((x) => x.downloadEnabled.equals(true))).get();
    final ids = {for (final x in prefs) x.playlistId};
    if (ids.isEmpty) return ids;
    final gone = await (_db.select(
      _db.playlists,
    )..where((x) => x.id.isIn(ids) & x.deleted.equals(true))).get();
    return ids.difference({for (final x in gone) x.id});
  }

  Future<Set<String>> _activeTrackIds(Iterable<String> playlistIds) async {
    if (playlistIds.isEmpty) return {};
    final rows =
        await (_db.select(_db.playlistEntries)..where(
              (e) =>
                  e.playlistId.isIn(playlistIds) &
                  e.deleted.equals(false) &
                  e.status.equals('active'),
            ))
            .get();
    return {for (final e in rows) e.trackId};
  }

  /// Live YouTube tracks among [ids], by id.
  Future<Map<String, Track>> _ytTracks(Iterable<String> ids) async {
    if (ids.isEmpty) return {};
    final rows =
        await (_db.select(_db.tracks)..where(
              (t) =>
                  t.id.isIn(ids) &
                  t.source.equals('yt') &
                  t.deleted.equals(false),
            ))
            .get();
    return {for (final t in rows) t.id: t};
  }

  Future<Set<String>> _manualIds() async {
    final rows = await (_db.select(
      _db.localFiles,
    )..where((f) => f.manual.equals(true))).get();
    return {for (final f in rows) f.trackId};
  }

  Future<Set<String>> _wantedIds() async {
    return {
      ...await _manualIds(),
      ...await _activeTrackIds(await _enabledPlaylistIds()),
    };
  }

  Future<LocalFile?> _row(String trackId) => (_db.select(
    _db.localFiles,
  )..where((f) => f.trackId.equals(trackId))).getSingleOrNull();

  Future<List<LocalFile>> _rows(Iterable<String> ids) async {
    if (ids.isEmpty) return [];
    return (_db.select(
      _db.localFiles,
    )..where((f) => f.trackId.isIn(ids))).get();
  }

  /// Queues [trackIds] (YouTube, available) that are not queued, downloading
  /// or done. Returns how many were newly queued. Call inside a transaction.
  Future<int> _queue(Iterable<String> trackIds, {bool manual = false}) async {
    final tracks = await _ytTracks(trackIds);
    final existing = {for (final f in await _rows(tracks.keys)) f.trackId: f};
    var n = 0;
    for (final t in tracks.values) {
      if (t.unavailable) continue;
      final row = existing[t.id];
      if (row == null) {
        await _db
            .into(_db.localFiles)
            .insert(
              LocalFilesCompanion.insert(
                trackId: t.id,
                path: '',
                state: 'queued',
                bytes: 0,
                mtimeMs: 0,
                requestedAt: Value(_nextRequestedAt()),
                manual: Value(manual),
              ),
            );
        n++;
      } else if (row.state == 'failed') {
        await (_db.update(
          _db.localFiles,
        )..where((f) => f.trackId.equals(t.id))).write(
          LocalFilesCompanion(
            state: const Value('queued'),
            error: const Value(null),
            requestedAt: Value(_nextRequestedAt()),
            manual: manual ? const Value(true) : const Value.absent(),
          ),
        );
        n++;
      } else if (manual && !row.manual) {
        await (_db.update(_db.localFiles)..where((f) => f.trackId.equals(t.id)))
            .write(const LocalFilesCompanion(manual: Value(true)));
      }
    }
    return n;
  }

  Future<void> _deleteFiles(List<LocalFile> rows, Directory ytDir) async {
    for (final r in rows) {
      if (r.path.isEmpty || !p.isWithin(ytDir.path, r.path)) continue;
      try {
        final f = File(r.path);
        if (await f.exists()) await f.delete();
      } on FileSystemException catch (e, s) {
        AppLog.w('Could not delete ${r.path}', e, s);
      }
    }
  }

  // --- playlist switch -----------------------------------------------------

  /// Turns downloading on or off for [playlistId] on this device. Enabling
  /// queues its tracks and returns how many were newly queued; disabling only
  /// clears the preference (files stay until removed).
  Future<int> setPlaylistDownload(String playlistId, bool enabled) {
    return _tx(() async {
      await _db
          .into(_db.playlistDevicePrefs)
          .insertOnConflictUpdate(
            PlaylistDevicePrefsCompanion.insert(
              playlistId: playlistId,
              downloadEnabled: Value(enabled),
            ),
          );
      if (!enabled) return 0;
      return _queue(await _activeTrackIds([playlistId]));
    });
  }

  /// Tracks added to [playlistId]; queued only when the playlist is enabled.
  Future<int> queueAdded(String playlistId, List<String> trackIds) {
    return _tx(() async {
      if (!(await _enabledPlaylistIds()).contains(playlistId)) return 0;
      return _queue(trackIds);
    });
  }

  /// Done files of [playlistId] that no other enabled playlist and no manual
  /// request needs.
  Future<List<String>> exclusiveFiles(String playlistId) async {
    final mine = await _activeTrackIds([playlistId]);
    final others = await _activeTrackIds(
      (await _enabledPlaylistIds()).where((id) => id != playlistId),
    );
    final yt = await _ytTracks(mine);
    final rows = await _rows(yt.keys);
    return [
      for (final r in rows)
        if (r.state == 'done' && !r.manual && !others.contains(r.trackId))
          r.trackId,
    ];
  }

  /// Deletes the files and rows of [trackIds] (YouTube tracks only). Returns
  /// the bytes freed.
  Future<int> removeFiles(List<String> trackIds, Directory ytDir) async {
    final yt = await _ytTracks(trackIds);
    final rows = await _rows(yt.keys);
    await _deleteFiles(rows, ytDir);
    await _tx(() async {
      await (_db.delete(
        _db.localFiles,
      )..where((f) => f.trackId.isIn(rows.map((r) => r.trackId)))).go();
    });
    return rows
        .where((r) => r.state == 'done')
        .fold<int>(0, (a, r) => a + r.bytes);
  }

  /// Deletes queued, downloading and failed rows nothing wants any more. A
  /// running download whose row goes is then cancelled by the queue.
  Future<void> dropUnwanted() {
    return _tx(() async {
      final wanted = await _wantedIds();
      final rows =
          await (_db.select(_db.localFiles)..where(
                (f) =>
                    f.state.isIn(const ['queued', 'downloading', 'failed']) &
                    f.manual.equals(false),
              ))
              .get();
      final yt = await _ytTracks(rows.map((r) => r.trackId));
      final drop = [
        for (final r in rows)
          if (yt.containsKey(r.trackId) && !wanted.contains(r.trackId))
            r.trackId,
      ];
      if (drop.isEmpty) return;
      await (_db.delete(
        _db.localFiles,
      )..where((f) => f.trackId.isIn(drop))).go();
    });
  }

  // --- single tracks -------------------------------------------------------

  /// Marks [trackId] as a manual download and queues it unless done. False
  /// for a non-YouTube or unavailable track.
  Future<bool> downloadTrack(String trackId) {
    return _tx(() async {
      final t = (await _ytTracks([trackId]))[trackId];
      if (t == null || t.unavailable) return false;
      await _queue([trackId], manual: true);
      return true;
    });
  }

  /// Clears the manual request and deletes the file unless an enabled
  /// playlist still contains the track.
  Future<void> removeTrackDownload(String trackId, Directory ytDir) async {
    final row = await _row(trackId);
    if (row == null) return;
    final inEnabled = (await _activeTrackIds(await _enabledPlaylistIds()))
        .contains(trackId);
    if (inEnabled) {
      await _tx(() async {
        await (_db.update(_db.localFiles)
              ..where((f) => f.trackId.equals(trackId)))
            .write(const LocalFilesCompanion(manual: Value(false)));
      });
      return;
    }
    await removeFiles([trackId], ytDir);
  }

  Future<void> retryFailed({String? playlistId}) {
    return _tx(() async {
      final failed = await (_db.select(
        _db.localFiles,
      )..where((f) => f.state.equals('failed'))).get();
      final scope = playlistId == null
          ? null
          : await _activeTrackIds([playlistId]);
      for (final f in failed) {
        if (scope != null && !scope.contains(f.trackId)) continue;
        await (_db.update(
          _db.localFiles,
        )..where((x) => x.trackId.equals(f.trackId))).write(
          LocalFilesCompanion(
            state: const Value('queued'),
            error: const Value(null),
            requestedAt: Value(_nextRequestedAt()),
          ),
        );
      }
    });
  }

  // --- queue ---------------------------------------------------------------

  /// Those of [trackIds] that have a download row.
  Future<Set<String>> rowIds(Iterable<String> trackIds) async => {
    for (final r in await _rows(trackIds)) r.trackId,
  };

  /// The live YouTube track [trackId], or null.
  Future<Track?> ytTrack(String trackId) async =>
      (await _ytTracks([trackId]))[trackId];

  Future<List<LocalFile>> nextQueued(int limit) =>
      (_db.select(_db.localFiles)
            ..where((f) => f.state.equals('queued'))
            ..orderBy([
              (f) => OrderingTerm.asc(f.requestedAt),
              (f) => OrderingTerm.asc(f.trackId),
            ])
            ..limit(limit))
          .get();

  Future<bool> _write(String id, LocalFilesCompanion c) async =>
      await (_db.update(
        _db.localFiles,
      )..where((f) => f.trackId.equals(id))).write(c) >
      0;

  /// Returns false when the row no longer exists (e.g. removed while the
  /// download ran).
  Future<bool> markDownloading(String id) =>
      _write(id, const LocalFilesCompanion(state: Value('downloading')));

  /// Returns false when the row no longer exists; the caller then owns the
  /// finished file at [path] and should delete it, as nothing tracks it.
  Future<bool> markDone(String id, String path, int bytes) => _write(
    id,
    LocalFilesCompanion(
      state: const Value('done'),
      path: Value(path),
      bytes: Value(bytes),
      mtimeMs: const Value(0),
      error: const Value(null),
    ),
  );

  /// Returns false when the row no longer exists.
  Future<bool> markFailed(String id, String message) => _write(
    id,
    LocalFilesCompanion(state: const Value('failed'), error: Value(message)),
  );

  /// Back to the queue (e.g. after a pause); keeps its place in line.
  /// Returns false when the row no longer exists.
  Future<bool> requeue(String id) => _write(
    id,
    const LocalFilesCompanion(state: Value('queued'), error: Value(null)),
  );

  /// After a crash: downloads that were running go back to the queue.
  Future<void> resetInterrupted() =>
      (_db.update(_db.localFiles)..where((f) => f.state.equals('downloading')))
          .write(const LocalFilesCompanion(state: Value('queued')));

  /// A done YouTube row whose file is gone is queued again if still wanted,
  /// else deleted.
  Future<void> reconcileMissing() async {
    final done = await (_db.select(
      _db.localFiles,
    )..where((f) => f.state.equals('done'))).get();
    final yt = await _ytTracks(done.map((r) => r.trackId));
    final gone = <String>[];
    for (final r in done) {
      if (!yt.containsKey(r.trackId)) continue;
      if (r.path.isEmpty || !await File(r.path).exists()) gone.add(r.trackId);
    }
    if (gone.isEmpty) return;
    await _tx(() async {
      final wanted = await _wantedIds();
      for (final id in gone) {
        if (wanted.contains(id)) {
          await _write(
            id,
            LocalFilesCompanion(
              state: const Value('queued'),
              path: const Value(''),
              bytes: const Value(0),
              error: const Value(null),
              requestedAt: Value(_nextRequestedAt()),
            ),
          );
        } else {
          await (_db.delete(
            _db.localFiles,
          )..where((f) => f.trackId.equals(id))).go();
        }
      }
    });
  }

  // --- watchers ------------------------------------------------------------

  /// Re-reads with [read] on every change of [tables]; emits only changes.
  Stream<T> _watch<T>(List<TableInfo> tables, Future<T> Function() read) {
    late final StreamController<T> c;
    StreamSubscription<void>? sub;
    var busy = false, dirty = false;
    Future<void> run() async {
      if (busy) {
        dirty = true;
        return;
      }
      busy = true;
      try {
        do {
          dirty = false;
          final v = await read();
          if (!c.isClosed && c.hasListener) c.add(v);
        } while (dirty);
      } catch (e, s) {
        if (!c.isClosed && c.hasListener) c.addError(e, s);
      } finally {
        busy = false;
      }
    }

    c = StreamController<T>(
      onListen: () {
        sub = _db
            .tableUpdates(TableUpdateQuery.onAllTables(tables))
            .listen((_) => unawaited(run()));
        unawaited(run());
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream.distinct(_eq.equals);
  }

  Stream<Set<String>> watchEnabledPlaylists() =>
      _watch([_db.playlistDevicePrefs, _db.playlists], _enabledPlaylistIds);

  /// Every download row that belongs to a YouTube track.
  Stream<List<LocalFile>> watchYtRows() =>
      _watch([_db.localFiles, _db.tracks], () async {
        final rows = await _db.select(_db.localFiles).get();
        final yt = await _ytTracks(rows.map((r) => r.trackId));
        return [
          for (final r in rows)
            if (yt.containsKey(r.trackId)) r,
        ];
      });

  Stream<PlaylistDownloadStatus> watchPlaylist(String playlistId) => _watch(
    [
      _db.playlistDevicePrefs,
      _db.playlistEntries,
      _db.tracks,
      _db.localFiles,
      _db.playlists,
    ],
    () async {
      final enabled = (await _enabledPlaylistIds()).contains(playlistId);
      final tracks = await _ytTracks(await _activeTrackIds([playlistId]));
      final rows = await _rows([
        for (final t in tracks.values)
          if (!t.unavailable) t.id,
      ]);
      int count(String s) => rows.where((r) => r.state == s).length;
      return PlaylistDownloadStatus(
        enabled: enabled,
        total: tracks.values.where((t) => !t.unavailable).length,
        done: count('done'),
        queued: count('queued'),
        downloading: count('downloading'),
        failed: count('failed'),
        bytes: rows
            .where((r) => r.state == 'done')
            .fold(0, (a, r) => a + r.bytes),
      );
    },
  );

  /// Download state per YouTube track id (only tracks that have a row).
  Stream<Map<String, String>> watchTrackStates(Iterable<String> trackIds) {
    final ids = trackIds.toList();
    return _watch([_db.localFiles, _db.tracks], () async {
      final yt = await _ytTracks(ids);
      final rows = await _rows(yt.keys);
      return {for (final r in rows) r.trackId: r.state};
    });
  }

  /// Bytes of all finished YouTube downloads.
  Stream<int> watchTotalBytes() =>
      _watch([_db.localFiles, _db.tracks], () async {
        final rows = await (_db.select(
          _db.localFiles,
        )..where((f) => f.state.equals('done'))).get();
        final yt = await _ytTracks(rows.map((r) => r.trackId));
        return rows
            .where((r) => yt.containsKey(r.trackId))
            .fold<int>(0, (a, r) => a + r.bytes);
      });

  /// Finished-download bytes of each playlist that has any.
  Stream<List<(String playlistId, int bytes)>> watchBytesPerPlaylist() =>
      _watch(
        [_db.localFiles, _db.tracks, _db.playlistEntries, _db.playlists],
        () async {
          final done = await (_db.select(
            _db.localFiles,
          )..where((f) => f.state.equals('done'))).get();
          final yt = await _ytTracks(done.map((r) => r.trackId));
          final bytes = {
            for (final r in done)
              if (yt.containsKey(r.trackId)) r.trackId: r.bytes,
          };
          if (bytes.isEmpty) return <(String, int)>[];
          final entries =
              await (_db.select(_db.playlistEntries)..where(
                    (e) =>
                        e.trackId.isIn(bytes.keys) &
                        e.deleted.equals(false) &
                        e.status.equals('active'),
                  ))
                  .get();
          final live = {
            for (final pl in await (_db.select(
              _db.playlists,
            )..where((x) => x.deleted.equals(false))).get())
              pl.id,
          };
          final perPlaylist = <String, Set<String>>{};
          for (final e in entries) {
            if (live.contains(e.playlistId)) {
              (perPlaylist[e.playlistId] ??= {}).add(e.trackId);
            }
          }
          return [
            for (final e in perPlaylist.entries)
              (e.key, e.value.fold<int>(0, (a, id) => a + bytes[id]!)),
          ]..sort((a, b) => a.$1.compareTo(b.$1));
        },
      );
}
