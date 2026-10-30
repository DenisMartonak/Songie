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

  /// Seqs handed out lately, with when, oldest first (see [recentSeqs]).
  final _issued = Queue<(int, int)>();

  /// How long an issued seq counts as possibly not yet written.
  static const pendingWindow = Duration(seconds: 60);
  int _seq;

  final String deviceId;

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
    _issue([seq]);
    final clock = _clock.tick().pack();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        SettingsCompanion.insert(key: _kLocalSeq, value: seq.toString()),
        SettingsCompanion.insert(key: _kHlcLast, value: clock),
      ]);
    });
    return Stamp(
      id: id ?? newId(),
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
    _issue([for (final st in stamps) st.localSeq]);
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
    final seqs = <int>[for (var i = 0; i < n; i++) ++_seq];
    _issue(seqs);
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        SettingsCompanion.insert(key: _kLocalSeq, value: _seq.toString()),
        SettingsCompanion.insert(key: _kHlcLast, value: _clock.last.pack()),
      ]);
    });
    return seqs;
  }

  /// Seqs issued within [pendingWindow], ascending. A caller may still be
  /// about to write a row with one of them (stamps are handed out before the
  /// write commits, not always inside a transaction), so a sync watermark
  /// must not pass the lowest one that has no row yet.
  List<int> recentSeqs() {
    _prune();
    return [for (final (seq, _) in _issued) seq];
  }

  void _issue(List<int> seqs) {
    final at = _nowMs();
    for (final s in seqs) {
      _issued.add((s, at));
    }
    _prune();
  }

  void _prune() {
    final cutoff = _nowMs() - pendingWindow.inMilliseconds;
    while (_issued.isNotEmpty && _issued.first.$2 < cutoff) {
      _issued.removeFirst();
    }
  }

  static Future<void> _put(AppDatabase db, String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
