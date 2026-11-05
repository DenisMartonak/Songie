import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/connectivity.dart';
import '../../core/log.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../data/sync_stamp.dart';
import '../../library/favorites.dart';
import '../change_feed.dart';
import '../row_applier.dart';
import '../sync_row.dart';
import 'cloud_remote.dart';
import 'sync_status.dart';

/// Rows per push and per pull.
const kCloudPageSize = 500;

/// The largest row `push_rows` takes (its `data` as JSON).
const _maxRowBytes = 256 * 1024;

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
    this._pushDelay = const Duration(seconds: 3),
    this._now = DateTime.now,
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
  final Duration _pushDelay;
  final DateTime Function() _now;

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
  bool _again = false;
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
  static String _key(SyncRow r) => '${r.table.wire}/${r.id}';

  /// Starts syncing for [userId] and returns once the first sync is done.
  /// Signing in as another account than last time first asks whether to
  /// merge this device's library into it or start empty.
  Future<void> start(String userId) async {
    if (_uid == userId) return;
    if (_uid != null) await stop();
    final gen = ++_gen;
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
    if (gen != _gen) return;
    _uid = userId;
    _onServer.clear();
    final ms = int.tryParse(
      await _settings.getString(_syncedKey(userId)) ?? '',
    );
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

  /// Stops syncing (signed out). Waits for a running sync to stop.
  Future<void> stop() async {
    // Also stops a start that is still asking or wiping.
    _gen++;
    if (_uid == null) return;
    _uid = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    await _changesSub?.cancel();
    _changesSub = null;
    try {
      await _running;
    } catch (_) {}
    await _remote.close();
    _onServer.clear();
    _setStatus(const SyncStatus(SyncPhase.idle));
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

  /// Whether this device has rows the account hasn't got yet.
  Future<bool> hasUnsent() async {
    final uid = _uid ?? await _settings.getString(kCloudLastAccount);
    if (uid == null) return false;
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
    try {
      do {
        _again = false;
        await _runOnce(_uid!, _gen);
      } while (_again && _uid != null);
    } finally {
      _running = null;
    }
  }

  Future<void> _runOnce(String uid, int gen) async {
    if (_offline) {
      _setStatus(SyncStatus(SyncPhase.offline, lastSynced: _status.lastSynced));
      return;
    }
    _setStatus(SyncStatus(SyncPhase.syncing, lastSynced: _status.lastSynced));
    try {
      await _pushAll(uid, gen);
      await _pullAll(uid, gen);
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
      if (send.isNotEmpty) await _remote.push(send);
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
      await _pushAll(uid, gen);
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

/// A sync for an account that was signed out (or switched) meanwhile.
class _Stopped implements Exception {
  const _Stopped();
}
