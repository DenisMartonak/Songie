import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/connectivity.dart';
import '../../core/hlc.dart';
import '../../core/log.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../data/sync_stamp.dart';
import '../../library/favorites.dart';
import '../change_feed.dart';
import '../row_applier.dart';
import '../sync_row.dart';
import 'cloud_files.dart';
import 'cloud_remote.dart';
import 'sync_status.dart';

/// Rows per push and per pull.
const kCloudPageSize = 500;

/// The largest row sent (its `data` as JSON). `push_rows` takes 256 KB as
/// jsonb text, which spaces out the JSON, so this stays clear of it.
const _maxRowBytes = 240 * 1024;

/// Syncs the synced tables with the signed-in account's rows on the server.
///
/// Up: rows whose local seq is past the account's push watermark, pushed in
/// pages, the watermark moving only after the server took a page. Down: the
/// server's rows past the pull watermark, applied newest-clock-wins by
/// [RowApplier], one transaction per page together with the watermark.
/// Rows applied as they came are not pushed back (see [_onServer]).
///
/// Syncs run one at a time; a trigger during one schedules exactly one more.
/// Signed out (before [start], after [stop]) nothing touches the server.
class CloudSync {
  CloudSync({
    required this._db,
    required this._stamp,
    required this._remote,
    required this._settings,
    Stream<NetworkKind>? network,
    Future<bool> Function()? askMerge,
    this._fontsDir,
    this._files,
    this._pushDelay = const Duration(seconds: 3),
    this._now = DateTime.now,
    this._stopWait = kCloudCallTimeout,
  }) : _askMerge = askMerge ?? _merge {
    _writesSub = _stamp.writes.listen((_) => localWrite());
    _netSub = network?.listen(_onNetwork, onError: (Object _) {});
  }

  static Future<bool> _merge() async => true;

  final AppDatabase _db;
  final SyncStamp _stamp;
  final CloudRemote _remote;
  final SettingsRepository _settings;
  final Future<bool> Function() _askMerge;
  final Directory? _fontsDir;

  /// Fonts and covers the synced rows point at, reconciled after each run.
  final CloudFiles? _files;
  final Duration _pushDelay;
  final DateTime Function() _now;

  /// How long [stop] waits for a running sync (a hung call) before leaving
  /// it behind.
  final Duration _stopWait;

  late final StreamSubscription<void> _writesSub;
  StreamSubscription<NetworkKind>? _netSub;
  StreamSubscription<void>? _changesSub;
  Timer? _pushTimer;

  /// The signed-in account; null when signed out.
  String? _uid;

  /// Bumped by every [start] and [stop], so a sync for an earlier account
  /// stops at its next step.
  int _gen = 0;
  Future<void>? _running;

  /// The running loop's token; a loop left behind by [stop] sees another.
  Object? _runToken;

  /// A [stop] still tidying up; [start] waits for it.
  Future<void>? _stopping;
  bool _again = false;

  /// Set during a run: a push failed (shown as error once the pull is done).
  bool _pushFailed = false;

  /// Set during a run: the server finds this device's clock a day ahead.
  bool _clockWrong = false;
  bool _offline = false;

  /// Pulled rows this device stores as they came, by `'<wire>/<id>'` to
  /// their clock: the server has them, so a push skips them unless they
  /// changed here since (a new clock).
  final _onServer = <String, String>{};

  final _statuses = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(SyncPhase.idle);

  /// The current status, then every change.
  Stream<SyncStatus> get status async* {
    yield _status;
    yield* _statuses.stream;
  }

  SyncStatus get current => _status;

  static String _pushKey(String uid) => '$kCloudPushSeqPrefix$uid';
  static String _pullKey(String uid) => '$kCloudPullSeqPrefix$uid';
  static String _syncedKey(String uid) => '$kCloudLastSyncedPrefix$uid';
  static String _filesKey(String uid) => '$kCloudFilesPendingPrefix$uid';
  static String _key(SyncRow r) => '${r.table.wire}/${r.id}';

  /// Starts syncing for [userId] and returns once the first sync is done.
  /// Signing in as another account than last time first asks whether to
  /// merge this device's library into it or start empty.
  Future<void> start(String userId) async {
    if (_uid == userId && _stopping == null) return;
    final gen = ++_gen;
    if (_uid != null) unawaited(_halt());
    while (_stopping != null) {
      await _stopping;
    }
    if (gen != _gen) return;
    final last = await _settings.getString(kCloudLastAccount);
    if (last != null && last != userId) {
      final merge = await _askMerge();
      if (gen != _gen) return;
      if (!merge) await wipeForNewAccount();
      // Everything here goes up to the new account, and all of its rows
      // come down.
      await _settings.setString(_pushKey(userId), null);
      await _settings.setString(_pullKey(userId), null);
    }
    await _settings.setString(kCloudLastAccount, userId);
    final ms = int.tryParse(
      await _settings.getString(_syncedKey(userId)) ?? '',
    );
    if (gen != _gen) return;
    _uid = userId;
    _onServer.clear();
    _setStatus(
      SyncStatus(
        _offline ? SyncPhase.offline : SyncPhase.idle,
        lastSynced: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      ),
    );
    _changesSub = _remote
        .changes(userId)
        .listen((_) => unawaited(syncNow()), onError: (Object _) {});
    await syncNow();
  }

  /// Stops syncing (signed out). Waits for a running sync to stop, but no
  /// longer than the stop wait.
  Future<void> stop() {
    // Also stops a start that is still asking or wiping.
    _gen++;
    return _halt();
  }

  /// Signs the engine out; the tidying up is [_stopping] until done.
  Future<void> _halt() {
    if (_uid == null) return _stopping ?? Future.value();
    _uid = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    final sub = _changesSub;
    _changesSub = null;
    final running = _running;
    late final Future<void> done;
    done = () async {
      await sub?.cancel();
      if (running != null) {
        try {
          await running.timeout(_stopWait);
        } on TimeoutException {
          AppLog.w('Cloud sync: a sync did not stop in time; left behind');
          if (identical(_running, running)) {
            _running = null;
            _runToken = null;
          }
        } catch (_) {}
      }
      await _remote.close();
      _onServer.clear();
      _setStatus(const SyncStatus(SyncPhase.idle));
      if (identical(_stopping, done)) _stopping = null;
    }();
    return _stopping = done;
  }

  /// Pushes and pulls now. During a sync, schedules one more after it; the
  /// future completes when that one is done. Never throws: a failure shows
  /// in [status].
  Future<void> syncNow() {
    if (_uid == null) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop();
  }

  /// A local write to a synced table: pushes after [pushDelay] without
  /// another write.
  void localWrite() {
    if (_uid == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () {
      _pushTimer = null;
      unawaited(syncNow());
    });
  }

  /// Whether this device has rows or files the account hasn't got yet.
  Future<bool> hasUnsent() async {
    final uid = _uid ?? await _settings.getString(kCloudLastAccount);
    if (uid == null) return false;
    // Files still to go up (kept across restarts).
    if (await _settings.getString(_filesKey(uid)) == '1') return true;
    final feed = ChangeFeed(_db, stamp: _stamp);
    var seq = await _getInt(_pushKey(uid));
    while (true) {
      final page = await feed.since(seq, limit: kCloudPageSize);
      if (page.rows.any((r) => _onServer[_key(r)] != r.clock)) return true;
      if (page.next == null) return false;
      seq = page.next!;
    }
  }

  /// "Start empty": removes this device's playlists and entries (Favorites
  /// stays, emptied), themes, fonts and their files, lyrics, listens and
  /// YouTube seen-lists. Tracks, local files, downloads and settings stay.
  /// Rows are removed outright, so nothing of it goes to the new account.
  Future<void> wipeForNewAccount() async {
    final fonts = await _db.select(_db.fonts).get();
    await _db.transaction(() async {
      await _db.delete(_db.playlistEntries).go();
      await (_db.delete(
        _db.playlists,
      )..where((p) => p.id.equals(kFavoritesPlaylistId).not())).go();
      await (_db.delete(
        _db.playlistDevicePrefs,
      )..where((p) => p.playlistId.equals(kFavoritesPlaylistId).not())).go();
      await _db.delete(_db.ytSeen).go();
      await _db.delete(_db.themes).go();
      await _db.delete(_db.fonts).go();
      await _db.delete(_db.lyrics).go();
      await _db.delete(_db.listens).go();
    });
    final dir = _fontsDir;
    if (dir == null) return;
    for (final f in fonts) {
      final file = File(p.join(dir.path, '${f.fileHash}.${f.ext}'));
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (e) {
        AppLog.w('Could not delete font file ${file.path}', e);
      }
    }
  }

  /// Cancels every subscription and timer (tests; the app keeps one).
  Future<void> dispose() async {
    await stop();
    await _writesSub.cancel();
    await _netSub?.cancel();
    await _statuses.close();
  }

  // --- Running --------------------------------------------------------------

  /// Runs syncs until no trigger came during the last one. Clears
  /// [_running] in the same step as that last check, so no trigger is lost.
  Future<void> _loop() async {
    final token = _runToken = Object();
    try {
      do {
        _again = false;
        await _runOnce(_uid!, _gen);
      } while (_again && _uid != null && identical(_runToken, token));
    } finally {
      if (identical(_runToken, token)) {
        _running = null;
        _runToken = null;
      }
    }
  }

  Future<void> _runOnce(String uid, int gen) async {
    if (_offline) {
      _setStatus(SyncStatus(SyncPhase.offline, lastSynced: _status.lastSynced));
      return;
    }
    _setStatus(SyncStatus(SyncPhase.syncing, lastSynced: _status.lastSynced));
    _pushFailed = false;
    _clockWrong = false;
    try {
      await _pushSafe(uid, gen);
      await _pullAll(uid, gen);
      _check(gen);
      // Never throws; offline it stops quietly and catches up next run.
      final files = await _files?.reconcile(uid, cancelled: () => gen != _gen);
      _check(gen);
      if (files?.pending case final pending?) {
        await _settings.setString(_filesKey(uid), pending ? '1' : null);
        _check(gen);
      }
      // Files left by the per-run cap go in a follow-up run, after the rows.
      if (files?.more ?? false) _again = true;
      if (_clockWrong || _pushFailed || (files?.failed ?? false)) {
        final phase = _clockWrong ? SyncPhase.clockWrong : SyncPhase.error;
        _setStatus(SyncStatus(phase, lastSynced: _status.lastSynced));
        return;
      }
      if (files?.offline ?? false) {
        _setStatus(
          SyncStatus(SyncPhase.offline, lastSynced: _status.lastSynced),
        );
        return;
      }
      // Still syncing: the follow-up run moves the rest.
      if (files?.more ?? false) return;
      final at = _now();
      await _settings.setString(
        _syncedKey(uid),
        at.millisecondsSinceEpoch.toString(),
      );
      _check(gen);
      _setStatus(SyncStatus(SyncPhase.idle, lastSynced: at));
    } on _Stopped {
      return;
    } on CloudOffline catch (e) {
      if (gen != _gen) return;
      AppLog.i('Cloud sync waits for the connection ($e)');
      _setStatus(SyncStatus(SyncPhase.offline, lastSynced: _status.lastSynced));
    } catch (e, s) {
      if (gen != _gen) return;
      AppLog.w('Cloud sync failed', e, s);
      _setStatus(SyncStatus(SyncPhase.error, lastSynced: _status.lastSynced));
    }
  }

  /// [_pushAll], but a failure that isn't the connection only marks the run
  /// ([_pushFailed], [_clockWrong]), so the pull still runs. Once one push
  /// failed, the run pushes no more.
  Future<void> _pushSafe(String uid, int gen) async {
    if (_pushFailed || _clockWrong) return;
    try {
      await _pushAll(uid, gen);
    } on _ClockWrong {
      AppLog.w("Cloud sync: the server finds this device's clock a day ahead");
      _clockWrong = true;
    } on CloudOffline {
      rethrow;
    } on _Stopped {
      rethrow;
    } catch (e, s) {
      AppLog.w('Cloud sync: push failed', e, s);
      _pushFailed = true;
    }
  }

  /// Pushes every row past the push watermark, a page at a time.
  Future<void> _pushAll(String uid, int gen) async {
    final feed = ChangeFeed(_db, stamp: _stamp);
    var seq = await _getInt(_pushKey(uid));
    // Rows past [high] may still be joined by a write with a lower seq: they
    // go now, but the watermark stops at [high], so they go again next time.
    final high = await feed.safeHigh();
    while (true) {
      _check(gen);
      final page = await feed.since(seq, limit: kCloudPageSize);
      final send = <SyncRow>[];
      final passed = <SyncRow>[];
      for (final r in page.rows) {
        if (_onServer[_key(r)] == r.clock) {
          passed.add(r);
        } else if (_tooBig(r)) {
          AppLog.w('Cloud sync: ${_key(r)} is too big to upload; skipped');
        } else {
          send.add(r);
        }
      }
      if (send.isNotEmpty) await _pushRows(send);
      final next = page.next;
      final to = next == null || next > high ? high : next;
      if (to > seq) {
        seq = to;
        await _settings.setString(_pushKey(uid), '$seq');
      }
      for (final r in [...passed, ...send]) {
        if (r.localSeq <= seq) _onServer.remove(_key(r));
      }
      if (next == null || to < next) return;
    }
  }

  /// Pushes [rows]. When the server refuses them for some of the rows, those
  /// are found by halving: rows with a clock a day ahead of this device's
  /// time get fresh stamps (they go up on the next run), other bad rows are
  /// skipped, and the rest go up. If no row is ahead by this device's time,
  /// its time itself is wrong: [_ClockWrong].
  Future<void> _pushRows(List<SyncRow> rows) async {
    try {
      await _remote.push(rows);
    } on CloudRejected catch (e) {
      if (e.reason == CloudRejection.clockAhead) {
        final limit =
            _now().millisecondsSinceEpoch + SyncStamp.maxAhead.inMilliseconds;
        final ahead = [
          for (final r in rows)
            if (Hlc.parse(r.clock).wallMs > limit) r,
        ];
        if (ahead.isEmpty) throw const _ClockWrong();
        await _restamp(ahead);
        final rest = [
          for (final r in rows)
            if (!ahead.contains(r)) r,
        ];
        if (rest.isNotEmpty) await _pushRows(rest);
        return;
      }
      if (rows.length == 1) {
        AppLog.w(
          'Cloud sync: the server refused ${_key(rows.single)} '
          '(${e.reason.name}); skipped',
        );
        return;
      }
      final half = rows.length ~/ 2;
      await _pushRows(rows.sublist(0, half));
      await _pushRows(rows.sublist(half));
    }
  }

  /// Gives [rows] fresh stamps from this device (its clock first put back
  /// from the future), keeping their content. A row changed here since the
  /// page was read (another clock) is left alone: that edit has its own,
  /// newer stamp and goes up as it is.
  Future<void> _restamp(List<SyncRow> rows) async {
    if (_stamp.clampFutureClock()) {
      AppLog.w('Cloud sync: put a clock from the future back to now');
    }
    var n = 0;
    await _db.transaction(() async {
      for (final r in rows) {
        final stored = await _db
            .customSelect(
              'SELECT clock FROM ${r.table.wire} WHERE id = ?',
              variables: [Variable.withString(r.id)],
            )
            .getSingleOrNull();
        if (stored?.read<String>('clock') != r.clock) continue;
        n++;
        final st = await _stamp.next(id: r.id);
        await _db
            .into(r.table.info(_db))
            .insertOnConflictUpdate(
              r
                  .withStamp(clock: st.clock, originDevice: st.originDevice)
                  .toInsertable(st.localSeq),
            );
      }
    });
    if (n > 0) AppLog.w('Cloud sync: restamped $n rows with clocks ahead');
  }

  /// Pulls and applies every server row past the pull watermark; after each
  /// page, pushes what applying it changed here (merged rows).
  Future<void> _pullAll(String uid, int gen) async {
    var after = await _getInt(_pullKey(uid));
    while (true) {
      _check(gen);
      final page = await _remote.pull(after, max: kCloudPageSize);
      _check(gen);
      if (page.isEmpty) return;
      final rows = [for (final (_, r) in page) r];
      final last = page.last.$1;
      await _db.transaction(() async {
        await RowApplier(_db, _stamp, now: _now).apply(rows);
        await _settings.setString(_pullKey(uid), '$last');
      });
      after = last;
      await _markOnServer(uid, rows);
      await _pushSafe(uid, gen);
      if (page.length < kCloudPageSize) return;
    }
  }

  /// Notes the pulled [rows] that are now stored here unchanged and not yet
  /// past the push watermark, so the push leaves them out.
  Future<void> _markOnServer(String uid, List<SyncRow> rows) async {
    final pushed = await _getInt(_pushKey(uid));
    final byTable = <SyncTable, Map<String, String>>{};
    for (final r in rows) {
      (byTable[r.table] ??= {})[r.id] = r.clock;
    }
    for (final MapEntry(key: t, value: clocks) in byTable.entries) {
      final ids = clocks.keys.toList();
      // SQLite allows 999 variables; a page holds at most 500.
      final local = await _db
          .customSelect(
            'SELECT id, clock FROM ${t.wire} WHERE local_seq > ? '
            'AND id IN (${List.filled(ids.length, '?').join(', ')})',
            variables: [
              Variable.withInt(pushed),
              for (final id in ids) Variable.withString(id),
            ],
          )
          .get();
      for (final row in local) {
        final id = row.read<String>('id');
        final clock = row.read<String>('clock');
        if (clocks[id] == clock) _onServer['${t.wire}/$id'] = clock;
      }
    }
  }

  void _onNetwork(NetworkKind kind) {
    final offline = kind == NetworkKind.offline;
    final was = _offline;
    _offline = offline;
    if (_uid == null) return;
    if (offline) {
      if (_status.phase != SyncPhase.syncing) {
        _setStatus(
          SyncStatus(SyncPhase.offline, lastSynced: _status.lastSynced),
        );
      }
    } else if (was || _status.phase == SyncPhase.offline) {
      unawaited(syncNow());
    }
  }

  void _check(int gen) {
    if (gen != _gen) throw const _Stopped();
  }

  static bool _tooBig(SyncRow r) =>
      utf8.encode(jsonEncode(rowToServer(r)['data'])).length > _maxRowBytes;

  Future<int> _getInt(String key) async =>
      int.tryParse(await _settings.getString(key) ?? '') ?? 0;

  void _setStatus(SyncStatus s) {
    if (s == _status) return;
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }
}

/// The server refuses this device's clocks though none is ahead of its own
/// time: the device's date and time are wrong.
class _ClockWrong implements Exception {
  const _ClockWrong();
}

/// A sync for an account that was signed out (or switched) meanwhile.
class _Stopped implements Exception {
  const _Stopped();
}
