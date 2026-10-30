import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/result.dart';
import '../core/text_normalize.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import 'art_cache.dart';
import 'file_hasher.dart';
import 'library_repository.dart';
import 'tag_reader.dart';

/// The artist stored for a file with no artist tag or filename hint.
const kUnknownArtist = 'Unknown artist';
const _progressEvery = 25;
const _filesInFlight = 2;

final _artistTitle = RegExp(r'^(.+?)\s+-\s+(.+)$');

/// Running totals of one folder scan. [found] counts every `.mp3` candidate
/// (including empty ones); [processed] is how many of them are handled so far.
class ScanProgress {
  const ScanProgress({
    required this.found,
    required this.processed,
    required this.added,
    required this.unchanged,
    required this.skipped,
    required this.done,
  });

  final int found;
  final int processed;

  /// New tracks created.
  final int added;

  /// Files that already had a track (same file as before, or same content as
  /// a known track).
  final int unchanged;

  /// Files that were empty, unreadable or failed in some other way.
  final int skipped;
  final bool done;
}

/// The outcome of handling one file: its track and whether it is new.
class _Handled {
  const _Handled(this.trackId, {required this.added});
  final String trackId;
  final bool added;
}

/// What a new track row will contain.
class _Draft {
  const _Draft({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.artworkRef,
  });

  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? artworkRef;
}

/// Turns music folders into `tracks` + `localFiles` rows, deduplicated by file
/// content (sha256). A bad file is skipped and counted, never fatal.
class LibraryScanner {
  LibraryScanner(
    this._db,
    this._stamp,
    this._tags,
    this._art,
    this._repo, {
    this._hasher = sha256File,
  });

  final AppDatabase _db;
  final SyncStamp _stamp;
  final TagReader _tags;
  final ArtCache _art;
  final LibraryRepository _repo;
  final Future<String> Function(File) _hasher;

  /// Scans [folderPath] recursively. Emits a [ScanProgress] every 25 files and
  /// a final one with `done: true`. Cancelling the subscription stops the scan
  /// once the files in flight are finished; rows already written stay and the
  /// folder's `lastScanAt` is not updated. A folder that does not exist ends
  /// the stream with a [FileSystemException].
  ///
  /// With [registerFolder] false the folder is only searched: it is not added
  /// to the library folders and files missing from it are not flagged. (Used
  /// to look for one moved song in a folder the user did not add.)
  Stream<ScanProgress> scanFolder(
    String folderPath, {
    String? createPlaylistNamed,
    bool registerFolder = true,
  }) {
    var cancelled = false;
    Future<void>? running;
    late final StreamController<ScanProgress> out;
    out = StreamController<ScanProgress>(
      onListen: () {
        running = _scan(
          p.normalize(p.absolute(folderPath)),
          createPlaylistNamed,
          registerFolder,
          out,
          () => cancelled,
        );
      },
      onCancel: () async {
        cancelled = true;
        await running;
      },
    );
    return out.stream;
  }

  /// Adds one file to the library (or finds its existing track) and returns
  /// the track id.
  Future<Result<String>> importFile(String path) async {
    final handled = await _handle(p.normalize(p.absolute(path)));
    return switch (handled) {
      Ok(:final value) => Ok(value.trackId),
      Err(:final failure) => Err(failure),
    };
  }

  /// Flags the track's local file as missing. No-op if it has none.
  Future<void> markMissing(String trackId) => _setState(trackId, 'missing');

  // --- scanning ------------------------------------------------------------

  /// Never throws: failures reach the listener as a stream error.
  Future<void> _scan(
    String folder,
    String? playlistName,
    bool registerFolder,
    StreamController<ScanProgress> out,
    bool Function() cancelled,
  ) async {
    try {
      if (!await Directory(folder).exists()) {
        throw FileSystemException('Folder not found', folder);
      }
      final paths = await _listMp3(Directory(folder));
      final index = await _localFileIndex();

      var processed = 0, added = 0, unchanged = 0, skipped = 0;
      final trackIds = List<String?>.filled(paths.length, null);
      ScanProgress snapshot({bool done = false}) => ScanProgress(
        found: paths.length,
        processed: processed,
        added: added,
        unchanged: unchanged,
        skipped: skipped,
        done: done,
      );

      var next = 0;
      Future<void> worker() async {
        while (!cancelled() && next < paths.length) {
          final i = next++;
          switch (await _handle(paths[i], index: index)) {
            case Ok(:final value):
              trackIds[i] = value.trackId;
              value.added ? added++ : unchanged++;
            case Err(:final failure):
              skipped++;
              AppLog.w('Skipped ${paths[i]}: ${failure.message}');
          }
          processed++;
          if (processed % _progressEvery == 0 &&
              processed < paths.length &&
              !cancelled()) {
            out.add(snapshot());
          }
        }
      }

      await Future.wait([for (var i = 0; i < _filesInFlight; i++) worker()]);
      if (cancelled()) return;

      if (registerFolder) {
        await _markVanished(folder, paths.toSet());
        await _db
            .into(_db.libraryFolders)
            .insertOnConflictUpdate(
              LibraryFoldersCompanion.insert(
                path: folder,
                lastScanAt: Value(DateTime.now()),
              ),
            );
      }
      if (playlistName != null) {
        await _createPlaylist(playlistName, trackIds.nonNulls.toSet());
      }
      out.add(snapshot(done: true));
    } catch (e, s) {
      if (!cancelled()) out.addError(e, s);
    } finally {
      out.close();
    }
  }

  /// Every `.mp3` below [dir], in code-unit order of the full path. A part of
  /// the tree that cannot be listed (permissions) is logged and skipped.
  Future<List<String>> _listMp3(Directory dir) {
    final done = Completer<List<String>>();
    final paths = <String>[];
    dir
        .list(recursive: true, followLinks: false)
        .listen(
          (entity) {
            if (entity is! Directory &&
                p.extension(entity.path).toLowerCase() == '.mp3') {
              paths.add(p.normalize(entity.path));
            }
          },
          onError: (Object e, StackTrace s) =>
              AppLog.w('Cannot list part of ${dir.path}', e, s),
          onDone: () => done.complete(paths..sort()),
        );
    return done.future;
  }

  /// Existing local files by path, so a scan does not query once per file.
  /// A 'done' row wins over a stale 'missing' one at the same path.
  Future<Map<String, LocalFile>> _localFileIndex() async {
    final rows =
        await (_db.select(_db.localFiles)
              ..where(_isLocalRow)
              ..orderBy([(f) => OrderingTerm.desc(f.state)]))
            .get();
    return {for (final r in rows) r.path: r};
  }

  Future<LocalFile?> _localFileAt(String path, Map<String, LocalFile>? index) {
    if (index != null) return Future.value(index[path]);
    return (_db.select(_db.localFiles)
          ..where((f) => f.path.equals(path) & _isLocalRow(f))
          ..orderBy([(f) => OrderingTerm.asc(f.state)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// After a complete scan: files of [folder] that are not on disk any more.
  Future<void> _markVanished(String folder, Set<String> seen) async {
    final rows = await (_db.select(
      _db.localFiles,
    )..where((f) => f.state.equals('done') & _isLocalRow(f))).get();
    for (final r in rows) {
      if (!p.isWithin(folder, r.path) || seen.contains(r.path)) continue;
      if (!await File(r.path).exists()) await _setState(r.trackId, 'missing');
    }
  }

  Future<void> _createPlaylist(String name, Set<String> trackIds) async {
    final created = await _repo.createPlaylist(name);
    if (created case Err(:final failure)) {
      AppLog.w('Playlist "$name" not created: ${failure.message}');
      return;
    }
    final id = (created as Ok<String>).value;
    final added = await _repo.addTracks(id, trackIds.toList());
    if (added case Err(:final failure)) {
      AppLog.w('Playlist "$name" not filled: ${failure.message}');
    }
  }

  // --- one file ------------------------------------------------------------

  /// The per-file logic shared by [scanFolder] and [importFile]. Never throws.
  Future<Result<_Handled>> _handle(
    String path, {
    Map<String, LocalFile>? index,
  }) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return Err(Failure(FailureKind.notFound, 'No such file: $path'));
      }
      if (stat.type != FileSystemEntityType.file) {
        return Err(Failure(FailureKind.invalidInput, 'Not a file: $path'));
      }
      if (stat.size == 0) {
        return Err(Failure(FailureKind.invalidInput, 'Empty file: $path'));
      }
      final bytes = stat.size;
      final mtimeMs = stat.modified.millisecondsSinceEpoch;

      final atPath = await _localFileAt(path, index);
      if (atPath != null &&
          atPath.bytes == bytes &&
          atPath.mtimeMs == mtimeMs &&
          // A deleted track must not be returned: fall through to revive it.
          await _liveTrackById(atPath.trackId) != null) {
        if (atPath.state != 'done') await _setState(atPath.trackId, 'done');
        return Ok(_Handled(atPath.trackId, added: false));
      }

      final String hash;
      try {
        hash = await _hasher(file);
      } on FileSystemException catch (e) {
        return Err(
          Failure(FailureKind.io, 'Cannot read $path: ${e.message}', cause: e),
        );
      }

      // Tags are read outside the transaction; only duplicates waste the work.
      var draft = await _liveTrackByHash(hash) == null
          ? await _draft(file)
          : null;

      return await guardDb(_db, () async {
        final known = await _liveTrackByHash(hash);
        if (known != null) {
          await _attach(known.id, path, bytes, mtimeMs);
          if (atPath != null && atPath.trackId != known.id) {
            await _setState(atPath.trackId, 'missing');
          }
          return Ok(_Handled(known.id, added: false));
        }

        final d = draft ??= await _draft(file);

        // The file at a known path was rewritten (typically retagged) into
        // content no other track has: the track is the same song, so it is
        // updated in place and keeps its id for playlist entries.
        final rewritten = atPath == null
            ? null
            : await _liveTrackById(atPath.trackId);
        if (rewritten != null) {
          await _updateInPlace(rewritten.id, hash, d, path, bytes, mtimeMs);
          return Ok(_Handled(rewritten.id, added: false));
        }

        // The same bytes were imported before and the track deleted: bring
        // that row back (peers know its id) instead of inserting a clash.
        final deleted = await _deletedTrackByHash(hash);
        if (deleted != null) {
          await _updateInPlace(deleted.id, hash, d, path, bytes, mtimeMs);
          return Ok(_Handled(deleted.id, added: true));
        }

        final stamp = await _stamp.next();
        await _db
            .into(_db.tracks)
            .insert(
              TracksCompanion.insert(
                id: stamp.id,
                clock: stamp.clock,
                originDevice: stamp.originDevice,
                localSeq: stamp.localSeq,
                source: 'local',
                title: d.title,
                artist: d.artist,
                album: Value(d.album),
                durationMs: Value(d.durationMs),
                artworkRef: Value(d.artworkRef),
                fileHash: Value(hash),
                searchText: normalizeForSearch(
                  '${d.title} ${d.artist} ${d.album ?? ''}',
                ),
              ),
            );
        await _db
            .into(_db.localFiles)
            .insertOnConflictUpdate(
              LocalFilesCompanion.insert(
                trackId: stamp.id,
                path: path,
                state: 'done',
                bytes: bytes,
                mtimeMs: mtimeMs,
              ),
            );
        // The previous owner of this path no longer has its file here.
        if (atPath != null) await _setState(atPath.trackId, 'missing');
        return Ok(_Handled(stamp.id, added: true));
      });
    } on FileSystemException catch (e, s) {
      AppLog.w('Cannot handle $path', e, s);
      return Err(Failure(FailureKind.io, 'Cannot read $path', cause: e));
    } catch (e, s) {
      AppLog.w('Unexpected error handling $path', e, s);
      return Err(Failure(FailureKind.unknown, 'Failed on $path', cause: e));
    }
  }

  Future<Track?> _liveTrackById(String id) {
    return (_db.select(_db.tracks)
          ..where((t) => t.id.equals(id) & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// New content and tags for [trackId], with a fresh stamp, and its local
  /// file row brought up to date.
  Future<void> _updateInPlace(
    String trackId,
    String hash,
    _Draft d,
    String path,
    int bytes,
    int mtimeMs,
  ) async {
    final stamp = await _stamp.next();
    await (_db.update(_db.tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        title: Value(d.title),
        artist: Value(d.artist),
        album: Value(d.album),
        durationMs: Value(d.durationMs),
        artworkRef: Value(d.artworkRef),
        fileHash: Value(hash),
        searchText: Value(
          normalizeForSearch('${d.title} ${d.artist} ${d.album ?? ''}'),
        ),
        deleted: const Value(false),
        mergedInto: const Value(null),
        clock: Value(stamp.clock),
        originDevice: Value(stamp.originDevice),
        localSeq: Value(stamp.localSeq),
      ),
    );
    await _db
        .into(_db.localFiles)
        .insertOnConflictUpdate(
          LocalFilesCompanion.insert(
            trackId: trackId,
            path: path,
            state: 'done',
            bytes: bytes,
            mtimeMs: mtimeMs,
          ),
        );
  }

  Future<Track?> _deletedTrackByHash(String hash) {
    return (_db.select(_db.tracks)
          ..where((t) => t.fileHash.equals(hash) & t.deleted.equals(true)))
        .getSingleOrNull();
  }

  Future<Track?> _liveTrackByHash(String hash) {
    return (_db.select(_db.tracks)
          ..where((t) => t.fileHash.equals(hash) & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// Points [trackId]'s local file at [path] (new content for a known track).
  /// If the track's current file still exists elsewhere, the first path wins
  /// and nothing changes.
  Future<void> _attach(
    String trackId,
    String path,
    int bytes,
    int mtimeMs,
  ) async {
    final current = await (_db.select(
      _db.localFiles,
    )..where((f) => f.trackId.equals(trackId))).getSingleOrNull();
    if (current != null &&
        current.path != path &&
        current.state == 'done' &&
        await File(current.path).exists()) {
      return;
    }
    await _db
        .into(_db.localFiles)
        .insertOnConflictUpdate(
          LocalFilesCompanion.insert(
            trackId: trackId,
            path: path,
            state: 'done',
            bytes: bytes,
            mtimeMs: mtimeMs,
          ),
        );
  }

  /// Rows of the local library. YouTube download rows share the table but
  /// belong to the download queue: scans, missing-marking and relinking must
  /// never see them.
  Expression<bool> _isLocalRow($LocalFilesTable f) => f.trackId.isNotInQuery(
    _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.id])
      ..where(_db.tracks.source.equals('yt')),
  );

  Future<void> _setState(String trackId, String state) {
    return (_db.update(_db.localFiles)
          ..where((f) => f.trackId.equals(trackId) & _isLocalRow(f)))
        .write(LocalFilesCompanion(state: Value(state)));
  }

  /// Tags with filename fallbacks: a throwing reader, or a blank title, falls
  /// back to the filename (`Artist - Title` is split).
  Future<_Draft> _draft(File file) async {
    var tags = const TrackTags();
    try {
      tags = await _tags.read(file);
    } catch (e, s) {
      AppLog.w('Tag read failed for ${file.path}, using filename', e, s);
    }

    final name = p.basenameWithoutExtension(file.path);
    final match = _artistTitle.firstMatch(name);
    final tagTitle = _clean(tags.title);
    final title = tagTitle ?? (match?.group(2) ?? name);
    final artist =
        _clean(tags.artist) ??
        (tagTitle == null ? match?.group(1) : null) ??
        kUnknownArtist;

    final Uint8List? picture = tags.picture;
    return _Draft(
      title: title,
      artist: artist,
      album: _clean(tags.album),
      durationMs: tags.duration?.inMilliseconds ?? 0,
      artworkRef: picture == null || picture.isEmpty
          ? null
          : await _art.put(picture),
    );
  }

  String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}
