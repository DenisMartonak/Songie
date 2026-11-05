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
  CloudFiles({
    required this._db,
    required this._remote,
    required this._fontsDir,
    required this._artDir,
  });

  final AppDatabase _db;
  final CloudRemote _remote;
  final Directory _fontsDir;
  final Directory _artDir;

  /// The bucket's limit per file.
  static const maxBytes = 10 * 1024 * 1024;

  static final _fontName = RegExp(r'^[0-9a-f]{64}\.(ttf|otf)$');
  static final _artName = RegExp(r'^(yt2-)?[0-9a-f]{64}\.jpg$');

  /// Whether [name] is `<sha256>.<ttf|otf>`.
  static bool isFontName(String name) => _fontName.hasMatch(name);

  /// Whether [name] is an art cache ref (`[yt2-]<sha256>.jpg`).
  static bool isArtName(String name) => _artName.hasMatch(name);

  static String _fontType(String name) =>
      name.endsWith('.otf') ? 'font/otf' : 'font/ttf';

  /// Uploads the account's files the bucket lacks and downloads the ones
  /// this device lacks. Never throws: offline it stops quietly, any other
  /// failure is logged and the file is tried again on the next run.
  /// [cancelled] is asked between files (signed out meanwhile).
  Future<void> reconcile(String userId, {bool Function()? cancelled}) async {
    try {
      final fonts = await _fontNames();
      final art = await _artRefs();
      for (final (kind, names, dir, type) in [
        ('font', fonts, _fontsDir, _fontType),
        ('art', art, _artDir, (String _) => 'image/jpeg'),
      ]) {
        if (names.isEmpty) continue;
        if (cancelled?.call() ?? false) return;
        final folder = '$userId/$kind';
        final there = await _remote.listFiles(folder);
        for (final name in names) {
          if (cancelled?.call() ?? false) return;
          final file = File(p.join(dir.path, name));
          try {
            if (there.contains(name)) {
              if (!await file.exists()) {
                await _download('$folder/$name', file, verify: kind == 'font');
              }
            } else if (await file.exists()) {
              await _upload('$folder/$name', file, type(name));
            }
          } on CloudOffline {
            rethrow;
          } catch (e) {
            // Data-free: no names, no paths.
            AppLog.w(
              'Cloud sync: a $kind file failed to sync (${e.runtimeType}); '
              'tried again next time',
            );
          }
        }
      }
    } on CloudOffline {
      AppLog.i('Cloud sync: files wait for the connection');
    } catch (e) {
      AppLog.w('Cloud sync: files failed (${e.runtimeType})');
    }
  }

  /// Deletes every file in [userId]'s folder. Throws when that fails, so the
  /// account isn't deleted with its files left behind.
  Future<void> deleteAll(String userId) async {
    for (final kind in const ['font', 'art']) {
      final folder = '$userId/$kind';
      final names = (await _remote.listFiles(folder)).toList();
      for (var i = 0; i < names.length; i += 500) {
        await _remote.removeFiles([
          for (final n in names.skip(i).take(500)) '$folder/$n',
        ]);
      }
    }
  }

  Future<void> _upload(String path, File file, String contentType) async {
    final size = await file.length();
    if (size == 0 || size > maxBytes) {
      AppLog.w('Cloud sync: a file is too big to upload ($size bytes)');
      return;
    }
    await _remote.uploadFile(
      path,
      await file.readAsBytes(),
      contentType: contentType,
    );
  }

  /// Writes the file at [path] to [to] through a `.part`; a font must match
  /// the hash its name carries.
  Future<void> _download(String path, File to, {required bool verify}) async {
    final bytes = await _remote.downloadFile(path);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('bad size');
    }
    if (verify && '${sha256.convert(bytes)}' != _hashOf(to)) {
      throw const FormatException('hash mismatch');
    }
    await to.parent.create(recursive: true);
    final part = File('${to.path}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(to.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
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
