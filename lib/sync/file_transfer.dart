import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/paths.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../library/file_hasher.dart';
import '../library/library_scanner.dart';
import '../theme/font_service.dart';
import 'sync_client.dart';
import 'sync_progress.dart';
import 'sync_server.dart';

enum FileKind { audio, font, art }

final _hashName = RegExp(r'^[0-9a-f]{64}$');
final _artName = RegExp(r'^(yt2-)?[0-9a-f]{64}\.jpg$');

/// A file one device needs from the other.
class FileRef {
  /// Throws [FormatException] unless [name] and [ext] fit [kind] (see
  /// [FileTransfer]); nothing touches the filesystem with an unchecked name.
  FileRef(this.kind, this.name, {this.ext, this.have = 0}) {
    final ok = switch (kind) {
      FileKind.audio =>
        _hashName.hasMatch(name) &&
            (ext == null || FileTransfer.audioExts.contains(ext)),
      FileKind.font =>
        _hashName.hasMatch(name) &&
            (ext == null || FileTransfer.fontExts.contains(ext)),
      FileKind.art => _artName.hasMatch(name) && ext == null,
    };
    if (!ok || have < 0) {
      throw FormatException('bad file ref: ${kind.name} $name $ext');
    }
  }

  factory FileRef.fromWire(Map<String, Object?> m) => FileRef(
    kindOf(m['kind'] as String),
    m['name'] as String,
    ext: m['ext'] as String?,
    have: (m['have'] as int?) ?? 0,
  );

  /// The kind named [name]; throws [FormatException] for any other.
  static FileKind kindOf(String name) =>
      FileKind.values.asNameMap()[name] ??
      (throw FormatException('bad file kind: $name'));

  final FileKind kind;

  /// The SHA-256 of the file (audio, fonts) or the art ref.
  final String name;

  /// The extension, for audio and fonts; null when not known yet.
  final String? ext;

  /// The size of the `.part` already here.
  final int have;

  FileRef withHave(int have) => FileRef(kind, name, ext: ext, have: have);

  Map<String, Object?> toWire() => {
    'kind': kind.name,
    'name': name,
    'ext': ext,
    'have': have,
  };

  String get _path => '/files/${kind.name}/$name';

  @override
  String toString() => '${kind.name}/$name';
}

/// Where a file copy stands. [done] counts files handled in both directions
/// (copied or skipped) of [total]; [copied] counts the ones that were copied,
/// either way.
class FileProgress {
  const FileProgress({
    required this.done,
    required this.total,
    this.current,
    this.copied = 0,
  });

  final int done;
  final int total;
  final String? current;
  final int copied;
}

/// How one [FileTransfer.receive] ended.
enum _Got {
  /// Complete, checked and in place.
  done,

  /// The bytes ended early; the `.part` is kept to resume.
  partial,

  /// Too long or failed its check; the `.part` is gone (worth one retry).
  bad,

  /// Complete, but no longer wanted or not attachable: not worth a retry.
  dropped,
}

/// Copies the local audio files, imported fonts and covers one device has and
/// the other lacks (spec "Files").
///
/// Files are kept at `<appData>/library/local/<sha256>.<ext>`,
/// `<appData>/fonts/<sha256>.<ext>` and `<appData>/art/<ref>`. A copy is
/// written to `<file>.part`, checked (SHA-256 for audio and fonts, the size
/// for art, whose ref hashes the source image rather than the JPEG), then
/// renamed. A cut or cancelled copy keeps its `.part` and resumes from it.
///
/// The initiator runs [exchange]; the responder answers with [serve],
/// [accept], [needs] and [offer] behind its session checks.
class FileTransfer {
  FileTransfer({
    required this._db,
    required this._paths,
    required this._scanner,
    required this._fonts,
  });

  /// Audio extensions [LibraryScanner] imports.
  static const audioExts = {'mp3'};
  static const fontExts = {'ttf', 'otf'};

  /// The largest file accepted, per kind.
  static const maxBytes = {
    FileKind.audio: 1024 * 1024 * 1024,
    FileKind.font: 10 * 1024 * 1024,
    FileKind.art: 10 * 1024 * 1024,
  };

  final AppDatabase _db;
  final AppPaths _paths;
  final LibraryScanner _scanner;
  final FontService _fonts;

  // --- What is missing here ------------------------------------------------

  /// Live local tracks with a hash and no `done` local file (as `t`).
  static const _audioMissing =
      'FROM tracks t '
      "WHERE t.deleted = 0 AND t.source = 'local' "
      'AND t.file_hash IS NOT NULL AND NOT EXISTS (SELECT 1 FROM local_files f '
      "WHERE f.track_id = t.id AND f.state = 'done')";

  /// The files this device lacks: audio of live local tracks with no `done`
  /// local file, live fonts and referenced covers whose file is missing.
  Future<List<FileRef>> needs() async {
    final out = <FileRef>[];
    final audio = await _db
        .customSelect(
          'SELECT DISTINCT t.file_hash AS h $_audioMissing',
          readsFrom: {_db.tracks, _db.localFiles},
        )
        .get();
    for (final row in audio) {
      final hash = row.read<String>('h');
      if (!_hashName.hasMatch(hash)) continue;
      out.add(FileRef(FileKind.audio, hash, have: await _audioPartSize(hash)));
    }

    final fonts = <String>{};
    for (final f in await _liveFonts()) {
      if (!_hashName.hasMatch(f.fileHash) || !fontExts.contains(f.ext)) {
        continue;
      }
      final r = FileRef(FileKind.font, f.fileHash, ext: f.ext);
      if (fonts.add(f.fileHash) && !await _dest(r).exists()) {
        out.add(r.withHave(await _partSize(r)));
      }
    }

    for (final ref in await _artRefs()) {
      final r = FileRef(FileKind.art, ref);
      if (!await _dest(r).exists()) out.add(r.withHave(await _partSize(r)));
    }
    return out;
  }

  /// Whether [r] is one of [needs] (with the extension this device expects).
  Future<bool> wants(FileRef r) async {
    switch (r.kind) {
      case FileKind.audio:
        if (r.ext == null) return false;
        final row = await _db
            .customSelect(
              'SELECT 1 $_audioMissing AND t.file_hash = ? LIMIT 1',
              variables: [Variable.withString(r.name)],
              readsFrom: {_db.tracks, _db.localFiles},
            )
            .getSingleOrNull();
        return row != null;
      case FileKind.font:
        final fonts = await _liveFonts(hash: r.name);
        return fonts.any((f) => f.ext == r.ext) && !await _dest(r).exists();
      case FileKind.art:
        return (await _artRefs(only: r.name)).isNotEmpty &&
            !await _dest(r).exists();
    }
  }

  Future<List<FontRow>> _liveFonts({String? hash}) {
    final q = _db.select(_db.fonts)..where((f) => f.deleted.equals(false));
    if (hash != null) q.where((f) => f.fileHash.equals(hash));
    return q.get();
  }

  /// Art refs of live tracks and playlists ([only] to look for one).
  Future<Set<String>> _artRefs({String? only}) async {
    final filter = only == null ? '' : ' AND ref = ?';
    final rows = await _db
        .customSelect(
          'SELECT ref FROM (SELECT artwork_ref AS ref FROM tracks '
          'WHERE deleted = 0 UNION SELECT cover_ref AS ref FROM playlists '
          'WHERE deleted = 0) WHERE ref IS NOT NULL$filter',
          variables: [if (only != null) Variable.withString(only)],
          readsFrom: {_db.tracks, _db.playlists},
        )
        .get();
    return {
      for (final row in rows)
        if (_artName.hasMatch(row.read<String>('ref'))) row.read<String>('ref'),
    };
  }

  // --- Files on disk -------------------------------------------------------

  /// This device's copy of [r], or null when it has none.
  Future<File?> locate(FileRef r) async {
    switch (r.kind) {
      case FileKind.audio:
        final rows = await _db
            .customSelect(
              'SELECT f.path AS path FROM tracks t '
              'JOIN local_files f ON f.track_id = t.id '
              "WHERE t.deleted = 0 AND t.file_hash = ? AND f.state = 'done'",
              variables: [Variable.withString(r.name)],
              readsFrom: {_db.tracks, _db.localFiles},
            )
            .get();
        for (final row in rows) {
          final file = File(row.read<String>('path'));
          if (_audioExtOf(file) != null && await file.exists()) return file;
        }
        return null;
      case FileKind.font:
        for (final f in await _liveFonts(hash: r.name)) {
          if (!fontExts.contains(f.ext)) continue;
          final file = _dest(FileRef(FileKind.font, r.name, ext: f.ext));
          if (await file.exists()) return file;
        }
        return null;
      case FileKind.art:
        // Only covers live rows use: a deleted row's cover stays private.
        if ((await _artRefs(only: r.name)).isEmpty) return null;
        final file = _dest(r);
        return await file.exists() ? file : null;
    }
  }

  static String? _audioExtOf(File f) {
    final ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
    return audioExts.contains(ext) ? ext : null;
  }

  /// The final file for [r] (whose ext is known for audio and fonts).
  File _dest(FileRef r) => switch (r.kind) {
    FileKind.audio => File(
      p.join(_paths.libraryLocal.path, '${r.name}.${r.ext}'),
    ),
    FileKind.font => File(p.join(_paths.fonts.path, '${r.name}.${r.ext}')),
    FileKind.art => File(p.join(_paths.art.path, r.name)),
  };

  File _part(FileRef r) => File('${_dest(r).path}.part');

  Future<int> _partSize(FileRef r) async {
    final part = _part(r);
    return await part.exists() ? await part.length() : 0;
  }

  Future<int> _audioPartSize(String hash) async {
    for (final ext in audioExts) {
      final have = await _partSize(FileRef(FileKind.audio, hash, ext: ext));
      if (have > 0) return have;
    }
    return 0;
  }

  /// Writes [bytes] (the file from byte `r.have` on, [total] bytes in all) to
  /// [r]'s `.part`. Returns true once the file is complete, checked, renamed
  /// and registered (audio through [LibraryScanner.importFile], fonts through
  /// [FontService.loadImported]).
  ///
  /// Returns false, keeping the `.part`, when [bytes] ends early; and false,
  /// deleting it, when the file is too long or fails its check, or when it is
  /// no longer wanted once complete (say its track was deleted meanwhile). An
  /// error in [bytes] propagates and keeps the `.part`. Throws
  /// [FormatException] for a bad ref, ext or size, or a `.part` shorter than
  /// `r.have`.
  Future<bool> receive(
    FileRef r,
    Stream<List<int>> bytes, {
    required int total,
  }) async => await _receive(r, bytes, total: total) == _Got.done;

  Future<_Got> _receive(
    FileRef r,
    Stream<List<int>> bytes, {
    required int total,
  }) async {
    if (r.kind != FileKind.art && r.ext == null) {
      throw const FormatException('missing ext');
    }
    if (total <= 0 || total > maxBytes[r.kind]! || r.have > total) {
      throw FormatException('bad size: ${r.have}/$total');
    }
    final dest = _dest(r);
    final part = _part(r);
    // Checked before opening, which would create an empty `.part`.
    final length = await _partSize(r);
    if (length < r.have) {
      throw FormatException('partial file is $length bytes, not ${r.have}');
    }
    await dest.parent.create(recursive: true);
    final raf = await part.open(mode: FileMode.append);
    var written = r.have;
    var tooLong = false;
    try {
      if (length > r.have) await raf.truncate(r.have);
      await raf.setPosition(r.have);
      await for (final chunk in bytes) {
        if (written + chunk.length > total) {
          tooLong = true;
          break;
        }
        await raf.writeFrom(chunk);
        written += chunk.length;
      }
    } finally {
      await raf.close();
    }
    if (tooLong) {
      AppLog.w('File $r is longer than announced; discarded');
      await part.delete();
      return _Got.bad;
    }
    if (written < total) return _Got.partial;
    if (r.kind != FileKind.art && await sha256File(part) != r.name) {
      AppLog.w('File $r failed its hash check; discarded');
      await part.delete();
      return _Got.bad;
    }
    // The copy took a while: importing a file whose track was deleted
    // meanwhile would bring the track back.
    if (!await wants(r)) {
      AppLog.i('File $r is no longer needed; discarded');
      await part.delete();
      return _Got.dropped;
    }
    await part.rename(dest.path);
    switch (r.kind) {
      case FileKind.audio:
        if (await _scanner.importFile(dest.path) case Err(:final failure)) {
          AppLog.w('Received $r could not be attached: ${failure.message}');
          return _Got.dropped;
        }
      case FileKind.font:
        await _fonts.loadImported();
      case FileKind.art:
        break;
    }
    return _Got.done;
  }

  // --- Initiator -----------------------------------------------------------

  /// Copies files both ways over [c], one at a time: first this device's
  /// [needs] that the peer has (`GET /files/<kind>/<name>`, resuming from a
  /// `.part`), then the peer's (`PUT /files/<kind>/<name>?ext=&from=&total=`).
  /// A file that fails its check is tried once more, then skipped, like one
  /// the peer refuses or no longer has. [cancel] stops after the bytes in
  /// flight, keeping `.part` files. A broken connection ends the stream with
  /// its [SyncNetError].
  Stream<FileProgress> exchange(SyncClient c, {SyncCancel? cancel}) async* {
    bool cancelled() => cancel?.isCancelled ?? false;

    final missing = await c.getJson('/files/missing');
    final pushes = <(FileRef, File)>[];
    for (final m in missing['files'] as List) {
      final r = FileRef.fromWire(Map<String, Object?>.from(m as Map));
      final file = await locate(r);
      if (file == null) continue;
      final ext = r.kind == FileKind.audio ? _audioExtOf(file) : r.ext;
      pushes.add((FileRef(r.kind, r.name, ext: ext, have: r.have), file));
    }

    final mine = {for (final r in await needs()) r.toString(): r};
    final offered = await c.postJson('/files/have', {
      'files': [
        for (final r in mine.values) {'kind': r.kind.name, 'name': r.name},
      ],
      'pushing': pushes.length,
    });
    final pulls = <(FileRef, int)>[];
    for (final o in offered['files'] as List) {
      final m = Map<String, Object?>.from(o as Map);
      final r = FileRef.fromWire(m);
      final size = m['size'];
      final need = mine[r.toString()];
      if (need == null || size is! int || size > maxBytes[r.kind]!) continue;
      if (r.kind != FileKind.art && r.ext == null) continue;
      pulls.add((r, size));
    }

    final total = pulls.length + pushes.length;
    var done = 0;
    var copied = 0;
    yield FileProgress(done: 0, total: total);
    for (final (r, size) in pulls) {
      if (cancelled()) return;
      yield FileProgress(
        done: done,
        total: total,
        current: r.name,
        copied: copied,
      );
      if (await _pull(c, r, size, cancelled)) copied++;
      done++;
      yield FileProgress(done: done, total: total, copied: copied);
    }
    for (final (r, file) in pushes) {
      if (cancelled()) return;
      yield FileProgress(
        done: done,
        total: total,
        current: r.name,
        copied: copied,
      );
      if (await _push(c, r, file, cancelled)) copied++;
      done++;
      yield FileProgress(done: done, total: total, copied: copied);
    }
  }

  Future<bool> _pull(
    SyncClient c,
    FileRef r,
    int size,
    bool Function() cancelled,
  ) async {
    for (var attempt = 0; attempt < 2 && !cancelled(); attempt++) {
      var have = await _partSize(r);
      if (have > size) {
        await _part(r).delete();
        have = 0;
      }
      try {
        final bytes = c
            .getFile(r._path, from: have)
            .takeWhile((_) => !cancelled());
        switch (await _receive(r.withHave(have), bytes, total: size)) {
          case _Got.done:
            return true;
          case _Got.dropped:
            return false;
          case _Got.partial || _Got.bad:
            break; // resume or retry once
        }
      } on SyncNetError catch (e) {
        if (_skips(e)) {
          AppLog.w('Skipping $r', e);
          return false;
        }
        rethrow;
      }
    }
    if (!cancelled()) AppLog.w('Skipping $r: no good copy');
    return false;
  }

  /// Whether the peer took the file.
  Future<bool> _push(
    SyncClient c,
    FileRef r,
    File file,
    bool Function() cancelled,
  ) async {
    for (var attempt = 0; attempt < 2 && !cancelled(); attempt++) {
      try {
        final size = await file.length();
        final from = attempt == 0 && r.have <= size ? r.have : 0;
        await c.putFile(
          r.ext == null ? r._path : '${r._path}?ext=${r.ext}',
          file.openRead(from).takeWhile((_) => !cancelled()),
          from: from,
          total: size,
        );
        return true;
      } on FileSystemException catch (e) {
        AppLog.w('Skipping $r: cannot read it', e);
        return false;
      } on SyncNetError catch (e) {
        if (cancelled()) return false;
        if (e.status == HttpStatus.unprocessableEntity) continue;
        if (_skips(e)) {
          AppLog.w('Skipping $r', e);
          return false;
        }
        rethrow;
      }
    }
    if (!cancelled()) AppLog.w('Skipping $r: the peer rejected it twice');
    return false;
  }

  /// Whether [e] concerns one file (it is gone, refused or rejected) rather
  /// than the connection or the pairing.
  static bool _skips(SyncNetError e) {
    final s = e.status;
    return s != null &&
        s >= 400 &&
        s < 500 &&
        s != HttpStatus.unauthorized &&
        s != HttpStatus.forbidden;
  }

  // --- Responder -----------------------------------------------------------

  /// The ref named by a `/files/<kind>/<name>` request (plus `?ext=`).
  /// Throws [FormatException] (a 400) for anything else.
  static FileRef refOf(Uri uri) {
    final s = uri.pathSegments;
    if (s.length != 3 || s[0] != 'files') {
      throw FormatException('bad file path: ${uri.path}');
    }
    return FileRef(FileRef.kindOf(s[1]), s[2], ext: uri.queryParameters['ext']);
  }

  /// Which of [wanted] (`[{kind, name}]`) this device can send, as
  /// `[{kind, name, ext, size}]`.
  Future<List<Map<String, Object?>>> offer(List<Object?> wanted) async {
    final out = <Map<String, Object?>>[];
    for (final w in wanted) {
      final m = w as Map;
      final r = FileRef(
        FileRef.kindOf(m['kind'] as String),
        m['name'] as String,
      );
      final file = await locate(r);
      if (file == null) continue;
      out.add({
        'kind': r.kind.name,
        'name': r.name,
        'ext': switch (r.kind) {
          FileKind.audio => _audioExtOf(file),
          FileKind.font => p.extension(file.path).replaceFirst('.', ''),
          FileKind.art => null,
        },
        'size': await file.length(),
      });
    }
    return out;
  }

  /// Answers `GET /files/<kind>/<name>` (with `Range: bytes=<from>-`).
  /// Returns whether the whole file was sent. [onChunk] runs as each chunk
  /// goes out.
  Future<bool> serve(HttpRequest req, {void Function()? onChunk}) async {
    final r = refOf(req.uri);
    final file = await locate(r);
    if (file == null) {
      await sendJson(req, {'error': 'not_found'}, status: HttpStatus.notFound);
      return false;
    }
    final size = await file.length();
    var from = 0;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'^bytes=(\d{1,15})-$').firstMatch(range);
      if (m == null) throw FormatException('bad range: $range');
      from = int.parse(m[1]!);
      if (from > size) {
        await sendJson(req, {
          'error': 'range',
        }, status: HttpStatus.requestedRangeNotSatisfiable);
        return false;
      }
    }
    req.response
      ..statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent
      ..headers.contentType = ContentType.binary
      ..contentLength = size - from;
    await req.response.addStream(_watched(file.openRead(from), onChunk));
    await req.response.close();
    return true;
  }

  /// Answers `PUT /files/<kind>/<name>?ext=&from=&total=`: 409 `not_needed`
  /// for a file this device does not lack (or no longer wants once it
  /// arrived), 422 `rejected` for one that failed its check (the sender
  /// retries once). Returns whether the file arrived. [onChunk] runs as each
  /// chunk comes in.
  Future<bool> accept(HttpRequest req, {void Function()? onChunk}) async {
    final r = refOf(req.uri);
    final q = req.uri.queryParameters;
    final from = int.parse(q['from'] ?? '');
    final total = int.parse(q['total'] ?? '');
    if (r.kind != FileKind.art && r.ext == null) {
      throw const FormatException('missing ext');
    }
    if (!await wants(r)) {
      await sendJson(req, {'error': 'not_needed'}, status: HttpStatus.conflict);
      return false;
    }
    final got = await _receive(
      r.withHave(from),
      _watched(req, onChunk),
      total: total,
    );
    await sendJson(
      req,
      switch (got) {
        _Got.done => {'ok': true},
        _Got.dropped => {'error': 'not_needed'},
        _Got.partial || _Got.bad => {'error': 'rejected'},
      },
      status: switch (got) {
        _Got.done => HttpStatus.ok,
        _Got.dropped => HttpStatus.conflict,
        _Got.partial || _Got.bad => HttpStatus.unprocessableEntity,
      },
    );
    return got == _Got.done;
  }

  static Stream<List<int>> _watched(
    Stream<List<int>> s,
    void Function()? onChunk,
  ) => onChunk == null
      ? s
      : s.map((chunk) {
          onChunk();
          return chunk;
        });
}
