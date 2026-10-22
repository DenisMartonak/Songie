import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:songies/core/log.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';

/// Turns a [Track] into something an [AudioBackend] can load.
abstract class TrackResolver {
  Future<Result<AudioSourceRef>> resolve(Track t);
}

/// Resolves tracks through their `LocalFiles` row; fails with
/// [FailureKind.notFound] when there is no row or the file is gone.
class LocalTrackResolver implements TrackResolver {
  LocalTrackResolver(this._db);

  final AppDatabase _db;

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    final row = await (_db.select(
      _db.localFiles,
    )..where((f) => f.trackId.equals(t.id))).getSingleOrNull();
    if (row == null) {
      return Err(Failure(FailureKind.notFound, 'No local file for ${t.id}'));
    }
    if (!File(row.path).existsSync()) {
      return Err(Failure(FailureKind.notFound, 'File missing: ${row.path}'));
    }
    if (row.state != 'done') {
      // The file came back (or was restored) since it was flagged missing.
      try {
        await (_db.update(_db.localFiles)
              ..where((f) => f.trackId.equals(t.id)))
            .write(const LocalFilesCompanion(state: Value('done')));
      } catch (e, s) {
        AppLog.w('Could not clear the missing flag of ${t.id}', e, s);
      }
    }
    return Ok(FileSource(row.path));
  }
}
