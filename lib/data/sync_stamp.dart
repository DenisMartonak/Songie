import 'dart:async';
import 'dart:collection';

import '../core/hlc.dart';
import '../core/ids.dart';
import 'database.dart';

const _kDeviceId = 'device_id';
const _kLocalSeq = 'local_seq';
const _kHlcLast = 'hlc_last';

/// Sync metadata for one row write.
class Stamp {
  const Stamp({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.localSeq,
  });

  final String id;
  final String clock;
  final String originDevice;
  final int localSeq;
}

/// Issues [Stamp]s for local writes: a fresh HLC value, this device's id and
/// the next `local_seq`. State is persisted in the `Settings` table so it
/// survives restarts.
class SyncStamp {
  SyncStamp._(this._db, this.deviceId, this._clock, this._seq, this._nowMs);

  final AppDatabase _db;
  final HlcClock _clock;
  final int Function() _nowMs;

  /// Seqs handed out lately, with their stamp's id and when, oldest first
  /// (see [recentStamps]).
  final _issued = Queue<(int, String, int)>();

  /// How far ahead of now the clock may be; the server refuses clocks
  /// further ahead (see [clampFutureClock]).
  static const maxAhead = Duration(days: 1);

  /// How long an issued seq counts as possibly not yet written.
  static const pendingWindow = Duration(seconds: 60);
  int _seq;

  final String deviceId;

  final _writes = StreamController<void>.broadcast();

  /// Fires (asynchronously) each time [next] or [nextMany] hands out stamps:
  /// a local write to a synced table is landing. Not for [reserve], which
  /// only applies rows that came from elsewhere.
  Stream<void> get writes => _writes.stream;

  /// Loads (or, on first run, creates) this device's id and clock state.
  static Future<SyncStamp> load(AppDatabase db, {int Function()? nowMs}) async {
    final values = <String, String>{
      for (final s in await db.select(db.settings).get()) s.key: s.value,
    };

    var deviceId = values[_kDeviceId];
    if (deviceId == null) {
      deviceId = newId();
      await _put(db, _kDeviceId, deviceId);
    }

    final hlcLast = values[_kHlcLast];
    final clock = HlcClock(
      deviceId,
      last: hlcLast == null ? null : Hlc.parse(hlcLast),
      nowMs: nowMs,
    );
    // A clock stored while the device's time ran fast would stamp every
    // later write in the future.
    clock.clampAhead(maxAhead);
    final seq = int.tryParse(values[_kLocalSeq] ?? '') ?? 0;
    return SyncStamp._(
      db,
      deviceId,
      clock,
      seq,
      nowMs ?? () => DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns the next stamp (with [id], or a new UUID) and persists the
  /// counters. Safe to call inside a caller's `db.transaction`: the writes join
  /// that transaction. The in-memory counters advance synchronously, so
  /// concurrent calls never hand out the same values; if a surrounding
  /// transaction rolls back, the in-memory state stays ahead of the stored one,
  /// which only leaves harmless gaps.
  Future<Stamp> next({String? id}) async {
    final seq = ++_seq;
    final stampId = id ?? newId();
    _issue([(seq, stampId)]);
    final clock = _clock.tick().pack();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        SettingsCompanion.insert(key: _kLocalSeq, value: seq.toString()),
        SettingsCompanion.insert(key: _kHlcLast, value: clock),
      ]);
    });
    return Stamp(
      id: stampId,
      clock: clock,
      originDevice: deviceId,
      localSeq: seq,
    );
  }

  /// Returns [n] distinct, strictly increasing stamps (clock and `local_seq`)
  /// persisted with one settings write. [ids], if given, must have length [n]
  /// (null entries get a new UUID). Same transaction semantics as [next].
  Future<List<Stamp>> nextMany(int n, {List<String?>? ids}) async {
    if (ids != null && ids.length != n) {
      throw ArgumentError('ids must have length $n');
    }
    if (n <= 0) return <Stamp>[];
    final stamps = <Stamp>[
      for (var i = 0; i < n; i++)
        Stamp(
          id: ids?[i] ?? newId(),
          clock: _clock.tick().pack(),
          originDevice: deviceId,
          localSeq: ++_seq,
        ),
    ];
    _issue([for (final st in stamps) (st.localSeq, st.id)]);
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        SettingsCompanion.insert(key: _kLocalSeq, value: _seq.toString()),
        SettingsCompanion.insert(key: _kHlcLast, value: stamps.last.clock),
      ]);
    });
    return stamps;
  }

  /// Reserves [n] fresh, strictly increasing `local_seq` values for rows
  /// applied from a peer. With [observedClock] the clock is advanced past it
  /// (so later local stamps sort after everything seen). Persisted with one
  /// settings write; same transaction semantics as [next].
  Future<List<int>> reserve(int n, {String? observedClock}) async {
    if (observedClock != null) _clock.receive(Hlc.parse(observedClock));
    // Not tracked as pending: the applier writes these rows in the same
    // transaction that reserves them.
    final seqs = <int>[for (var i = 0; i < n; i++) ++_seq];
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        SettingsCompanion.insert(key: _kLocalSeq, value: _seq.toString()),
        SettingsCompanion.insert(key: _kHlcLast, value: _clock.last.pack()),
      ]);
    });
    return seqs;
  }

  /// Puts the clock back to now if it is more than [maxAhead] in the future
  /// (the device's time was wrong and has been fixed). Returns whether it
  /// did; the next stamp persists it.
  bool clampFutureClock() => _clock.clampAhead(maxAhead);

  /// Seqs issued by [next] and [nextMany] within [pendingWindow], ascending,
  /// each with its stamp's id (the row's id for an insert, or one passed in).
  /// A caller may still be about to write a row with one of them (stamps are
  /// handed out before the write commits, not always inside a transaction),
  /// so a sync watermark must not pass the lowest one that has no row yet.
  List<(int, String)> recentStamps() {
    _prune();
    return [for (final (seq, id, _) in _issued) (seq, id)];
  }

  void _issue(List<(int, String)> stamps) {
    _writes.add(null);
    final at = _nowMs();
    for (final (seq, id) in stamps) {
      _issued.add((seq, id, at));
    }
    _prune();
  }

  void _prune() {
    final cutoff = _nowMs() - pendingWindow.inMilliseconds;
    while (_issued.isNotEmpty && _issued.first.$3 < cutoff) {
      _issued.removeFirst();
    }
  }

  static Future<void> _put(AppDatabase db, String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
