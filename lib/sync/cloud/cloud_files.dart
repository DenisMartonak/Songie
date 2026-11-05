import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/log.dart';
import '../../data/database.dart';
import 'cloud_remote.dart';

/// The files synced rows point at that can't be had again elsewhere, kept in
/// the account's folder of the `sync-files` bucket:
///
/// - `<user id>/font/<sha256>.<ttf|otf>`: imported fonts (live `fonts` rows;
///   the file is `<fontsDir>/<sha256>.<ext>`).
/// - `<user id>/art/<ref>`: covers in the art cache (`<artDir>/<ref>`, always
///   JPEG) that aren't YouTube's: art read from a local file's tags (local
///   tracks, and listens of them) and covers the user picked for a playlist.
///   A YouTube track's art is fetched again from YouTube on each device, so
///   it never goes up, whatever its ref looks like.
///
/// [reconcile] uploads what the bucket lacks and downloads what this device
/// lacks; nothing is sent or fetched twice. Every name is checked before it
/// touches the filesystem or the bucket.
class CloudFiles {
  /// [onFontsArrived] runs after a reconcile that downloaded fonts, so they
  /// get registered (`FontService.loadImported`).
  CloudFiles({
    required this._db,
    required this._remote,
    required this._fontsDir,
    required this._artDir,
    this._onFontsArrived,
  });

  final AppDatabase _db;
  final CloudRemote _remote;
  final Directory _fontsDir;
  final Directory _artDir;
  final Future<void> Function()? _onFontsArrived;

  /// The bucket's limit per file.
  static const maxBytes = 10 * 1024 * 1024;

  /// At most this many files move in one reconcile ...
  static const maxFilesPerRun = 20;

  /// ... and at most about this many bytes (the file that passes it still
  /// goes), so row pushes get a turn between them.
  static const maxBytesPerRun = 25 * 1024 * 1024;

  static final _fontName = RegExp(r'^[0-9a-f]{64}\.(ttf|otf)$');
  static final _artName = RegExp(r'^(yt2-)?[0-9a-f]{64}\.jpg$');

  /// Whether [name] is `<sha256>.<ttf|otf>`.
  static bool isFontName(String name) => _fontName.hasMatch(name);

  /// Whether [name] is an art cache ref (`[yt2-]<sha256>.jpg`).
  static bool isArtName(String name) => _artName.hasMatch(name);

  static String _fontType(String name) =>
      name.endsWith('.otf') ? 'font/otf' : 'font/ttf';

  /// Uploads the account's files the bucket lacks and downloads the ones
  /// this device lacks, at most [maxFilesPerRun] files or [maxBytesPerRun]
  /// bytes per call ([FilesOutcome.more] when some are left). Never throws:
  /// offline it stops quietly; other failures are logged once per call and
  /// the files are tried again next time. [cancelled] is asked between files
  /// and before a download is put in place (signed out meanwhile).
  Future<FilesOutcome> reconcile(
    String userId, {
    bool Function()? cancelled,
  }) async {
    bool stop() => cancelled?.call() ?? false;
    var pending = false;
    var uploadFailed = false;
    var moved = 0;
    var movedBytes = 0;
    var fontsArrived = 0;
    final failures = <String>{};
    var failCount = 0;
    try {
      final fonts = await _fontNames();
      final art = await _artRefs();
      for (final (kind, names, dir, type) in [
        ('font', fonts, _fontsDir, _fontType),
        ('art', art, _artDir, (String _) => 'image/jpeg'),
      ]) {
        if (names.isEmpty) continue;
        if (stop()) return const FilesOutcome(pending: null);
        final folder = '$userId/$kind';
        final there = (await _remote.listFiles(folder)).files;
        for (final name in names) {
          if (stop()) return const FilesOutcome(pending: null);
          final file = File(p.join(dir.path, name));
          final down = there.contains(name);
          if (down ? await file.exists() : !await file.exists()) continue;
          final size = down ? 0 : await file.length();
          if (!down && (size == 0 || size > maxBytes)) {
            AppLog.w('Cloud sync: a file is too big to upload ($size bytes)');
            continue;
          }
          if (moved >= maxFilesPerRun || movedBytes >= maxBytesPerRun) {
            // Left for the next run, which may hold uploads: pending.
            return FilesOutcome(pending: true, more: true);
          }
          moved++;
          try {
            if (down) {
              final n = await _download(
                '$folder/$name',
                file,
                kind: kind,
                cancelled: stop,
              );
              movedBytes += n;
              if (n > 0 && kind == 'font') fontsArrived++;
            } else {
              movedBytes += size;
              await _remote.uploadFile(
                '$folder/$name',
                await file.readAsBytes(),
                contentType: type(name),
              );
            }
          } on CloudOffline {
            if (!down) pending = true;
            rethrow;
          } catch (e) {
            if (!down) {
              pending = true;
              uploadFailed = true;
            }
            failCount++;
            failures.add('${e.runtimeType}');
          }
        }
      }
      return FilesOutcome(pending: pending, failed: uploadFailed);
    } on CloudOffline {
      AppLog.i('Cloud sync: files wait for the connection');
      // What the bucket lacks of the rest isn't known.
      return FilesOutcome(pending: pending ? true : null, offline: true);
    } catch (e) {
      AppLog.w('Cloud sync: files failed (${e.runtimeType})');
      return const FilesOutcome(pending: null, failed: true);
    } finally {
      if (failCount > 0) {
        // Data-free: no names, no paths.
        AppLog.w(
          'Cloud sync: $failCount files failed to sync '
          '(${failures.join(', ')}); tried again next time',
        );
      }
      if (fontsArrived > 0) {
        try {
          await _onFontsArrived?.call();
        } catch (e) {
          AppLog.w(
            'Cloud sync: loading arrived fonts failed (${e.runtimeType})',
          );
        }
      }
    }
  }

  /// Deletes every file under [userId]'s folder, sub-folders too. Throws
  /// when that fails, so the account isn't deleted with files left behind.
  Future<void> deleteAll(String userId) => _deleteUnder(userId, 0);

  Future<void> _deleteUnder(String folder, int depth) async {
    final listing = await _remote.listFiles(folder);
    final names = listing.files.toList();
    for (var i = 0; i < names.length; i += 500) {
      await _remote.removeFiles([
        for (final n in names.skip(i).take(500)) '$folder/$n',
      ]);
    }
    // The layout is two deep; a little room for later kinds.
    if (depth >= 4) return;
    for (final sub in listing.folders) {
      await _deleteUnder('$folder/$sub', depth + 1);
    }
  }

  /// Writes the file at [path] to [to] through a `.part` and returns its
  /// size, or 0 when signed out meanwhile. A font must match the hash its
  /// name carries, art must be a JPEG.
  Future<int> _download(
    String path,
    File to, {
    required String kind,
    required bool Function() cancelled,
  }) async {
    final bytes = await _remote.downloadFile(path);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('bad size');
    }
    if (kind == 'font' && '${sha256.convert(bytes)}' != _hashOf(to)) {
      throw const FormatException('hash mismatch');
    }
    if (kind == 'art' &&
        (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8)) {
      throw const FormatException('not a JPEG');
    }
    if (cancelled()) return 0;
    await to.parent.create(recursive: true);
    final part = File('${to.path}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      if (cancelled()) {
        await part.delete();
        return 0;
      }
      await part.rename(to.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
    return bytes.length;
  }

  static String _hashOf(File f) => p.basenameWithoutExtension(f.path);

  /// `<sha256>.<ext>` of every live font, checked.
  Future<Set<String>> _fontNames() async {
    final rows = await (_db.select(
      _db.fonts,
    )..where((f) => f.deleted.equals(false))).get();
    return {
      for (final f in rows)
        if (isFontName('${f.fileHash}.${f.ext}')) '${f.fileHash}.${f.ext}',
    };
  }

  /// The art refs of live rows that YouTube can't give again: local tracks,
  /// listens of local tracks, and playlist covers (always picked by the
  /// user), checked.
  Future<Set<String>> _artRefs() async {
    final rows = await _db
        .customSelect(
          "SELECT artwork_ref AS ref FROM tracks WHERE deleted = 0 "
          "AND source = 'local' AND artwork_ref IS NOT NULL "
          'UNION SELECT cover_ref AS ref FROM playlists WHERE deleted = 0 '
          'AND cover_ref IS NOT NULL '
          'UNION SELECT l.artwork_ref AS ref FROM listens l '
          'JOIN tracks t ON t.id = l.track_id '
          "WHERE l.deleted = 0 AND t.source = 'local' "
          'AND l.artwork_ref IS NOT NULL',
          readsFrom: {_db.tracks, _db.playlists, _db.listens},
        )
        .get();
    return {
      for (final row in rows)
        if (isArtName(row.read<String>('ref'))) row.read<String>('ref'),
    };
  }
}

/// How one [CloudFiles.reconcile] went.
class FilesOutcome {
  const FilesOutcome({
    required this.pending,
    this.more = false,
    this.failed = false,
    this.offline = false,
  });

  /// Whether files of this device are still to go up; null when not known
  /// (offline before the bucket answered, or signed out meanwhile).
  final bool? pending;

  /// Files were left for another run (the per-run cap).
  final bool more;

  /// An upload failed for a reason other than the connection.
  final bool failed;

  /// The connection dropped.
  final bool offline;
}
