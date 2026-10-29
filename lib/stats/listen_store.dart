import 'package:drift/drift.dart';

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import 'main_artist.dart';

/// Stamped `listens` rows: one per listening session. Every method logs
/// failures and never throws.
class ListenStore {
  ListenStore(this._db, this._stamp, {DateTime Function() now = DateTime.now})
    : _now = now; // ignore: prefer_initializing_formals

  final AppDatabase _db;
  final SyncStamp _stamp;
  final DateTime Function() _now;

  /// Rows older than this are deleted by [prune]: 12 months plus the
  /// previous 12 months for the comparison.
  static const retention = Duration(days: 730);

  /// Inserts a listen of [t] that began at [startedAtUtc]; returns its id, or
  /// null if it could not be written.
  Future<String?> start(
    Track t,
    DateTime startedAtUtc,
    Duration heard,
    bool counted,
  ) async {
    try {
      final r = await guardDb<String>(_db, () async {
        final st = await _stamp.next();
        await _db
            .into(_db.listens)
            .insert(
              ListensCompanion.insert(
                id: st.id,
                clock: st.clock,
                originDevice: st.originDevice,
                localSeq: st.localSeq,
                trackId: t.id,
                startedAt: startedAtUtc.toUtc(),
                heardMs: heard.inMilliseconds,
                counted: counted,
                mainArtist: mainArtist(t.artist, youtube: t.source == 'yt'),
                titleSnapshot: t.title,
                artistSnapshot: t.artist,
                artworkRef: Value(t.artworkRef),
              ),
            );
        return Ok(st.id);
      });
      if (r is Ok<String>) return r.value;
      if (r is Err<String>) {
        AppLog.w('Listen start failed: ${r.failure.message}');
      }
    } catch (e, s) {
      AppLog.w('Listen start failed unexpectedly', e, s);
    }
    return null;
  }

  /// Re-stamps listen [id] with the time heard so far.
  Future<void> update(String id, Duration heard, bool counted) async {
    try {
      final r = await guardDb<void>(_db, () async {
        final st = await _stamp.next(id: id);
        await (_db.update(_db.listens)..where((t) => t.id.equals(id))).write(
          ListensCompanion(
            clock: Value(st.clock),
            originDevice: Value(st.originDevice),
            localSeq: Value(st.localSeq),
            heardMs: Value(heard.inMilliseconds),
            counted: Value(counted),
          ),
        );
        return const Ok(null);
      });
      if (r is Err<void>) {
        AppLog.w('Listen update failed: ${r.failure.message}');
      }
    } catch (e, s) {
      AppLog.w('Listen update failed unexpectedly', e, s);
    }
  }

  /// Deletes listens that started more than [retention] before now.
  Future<void> prune() async {
    try {
      final cutoff = _now().toUtc().subtract(retention);
      final r = await guardDb<void>(_db, () async {
        await (_db.delete(
          _db.listens,
        )..where((t) => t.startedAt.isSmallerThanValue(cutoff))).go();
        return const Ok(null);
      });
      if (r is Err<void>) AppLog.w('Listen prune failed: ${r.failure.message}');
    } catch (e, s) {
      AppLog.w('Listen prune failed unexpectedly', e, s);
    }
  }
}
