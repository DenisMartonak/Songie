import 'dart:async';
import 'dart:io';

import '../core/app_version.dart';
import '../core/log.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../downloads/download_repository.dart';
import 'change_feed.dart';
import 'file_transfer.dart';
import 'peer_repository.dart';
import 'row_applier.dart';
import 'sync_progress.dart';
import 'sync_row.dart';
import 'sync_server.dart';

/// What the responding device shows.
sealed class ResponderState {
  const ResponderState();
}

class Idle extends ResponderState {
  const Idle();
}

/// A peer has a session open and is working on its side (pulling, merging
/// or asking the user about clashes).
class WaitingFor extends ResponderState {
  const WaitingFor(this.peerName);

  final String peerName;
}

class Receiving extends ResponderState {
  const Receiving(this.stage, this.done, this.total);

  final SyncStage stage;
  final int done;

  /// 0 when unknown.
  final int total;
}

class ResponderDone extends ResponderState {
  const ResponderDone(this.summary);

  final SyncSummary summary;
}

/// Answers a peer's [SyncRunner] (spec "A sync run"), one session at a time.
///
/// Routes (all signed except `/hello`):
/// - `GET /hello` → `{device_id, name, app_version, schema_version, time_ms}`
/// - `POST /session/begin {sync_id}` (409 `busy` while another peer's
///   session is open or this device runs a sync of its own; the same peer's
///   open session is replaced)
/// - `GET /changes?since=&cursor=&limit=` → `{rows, next, high}`
/// - `POST /apply/part {sync_id, rows, total?}` stages at most [maxPartRows]
/// - `POST /apply/commit {sync_id}` applies every staged row in one
///   transaction → `{written, playlists_changed, songs_added}`
/// - `POST /commit {sync_id, initiator_high, responder_high}` saves the
///   watermarks and moves the session to its files phase; `responder_high`
///   must be the high `/changes` served in this session (409 `high_mismatch`
///   otherwise)
/// - files phase, with [FileTransfer]: `GET /files/missing` → `{files}`,
///   `POST /files/have {files, pushing}` → `{files}`,
///   `GET /files/<kind>/<name>` and `PUT /files/<kind>/<name>?ext=&from=&total=`
/// - `POST /files/done {sync_id, copied?}` ends the session (shows
///   [ResponderDone] with `copied` files, else the files served or received)
/// - `POST /session/abort {sync_id}`, `POST /unpair`
///
/// A step of a session that is not open (or belongs to another peer, or is
/// not in that step's phase) gets a 409 `no_session`; so do file routes
/// outside the files phase of the asking peer's session. A session idle for
/// [idleTimeout] is dropped with its staged rows; one in its files phase is
/// finished instead.
class SyncResponder {
  SyncResponder({
    required this._db,
    required this._stamp,
    required this._peers,
    required this._myDeviceId,
    required this._myName,
    required this._downloads,
    this._files,
    this._runningLocally = _never,
    this._now = DateTime.now,
    this._timer = Timer.new,
  });

  static const idleTimeout = Duration(minutes: 15);
  static const maxPartRows = 500;

  final AppDatabase _db;
  final SyncStamp _stamp;
  final PeerRepository _peers;
  final String _myDeviceId;
  final String Function() _myName;
  final DownloadRepository _downloads;
  final FileTransfer? _files;
  final bool Function() _runningLocally;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timer;
  final _state = StreamController<ResponderState>.broadcast();

  _Session? _session;

  static bool _never() => false;

  Stream<ResponderState> get state => _state.stream;

  /// Whether a peer has a session open here.
  bool get inSession => _session != null;

  void register(SyncServer s) {
    s.route('GET', '/hello', _hello, open: true);
    s.route('POST', '/session/begin', _begin);
    s.route('GET', '/changes', _changes);
    s.route('POST', '/apply/part', _part);
    s.route('POST', '/apply/commit', _applyCommit);
    s.route('POST', '/commit', _commit);
    if (_files != null) {
      s.route('GET', '/files/missing', _filesMissing);
      s.route('POST', '/files/have', _filesHave);
      s.route('GET', '/files/', _fileGet);
      s.route('PUT', '/files/', _filePut);
    }
    s.route('POST', '/files/done', _filesDone);
    s.route('POST', '/session/abort', _abort);
    s.route('POST', '/unpair', _unpair);
  }

  Future<void> _hello(HttpRequest req, String? _) => sendJson(req, {
    'device_id': _myDeviceId,
    'name': _myName(),
    'app_version': appVersion,
    'time_ms': _now().millisecondsSinceEpoch,
  });

  Future<void> _begin(HttpRequest req, String? peerId) async {
    final syncId = _syncId(req);
    final peer = await _peers.byId(peerId!);
    if (peer == null) {
      return sendJson(req, {
        'error': 'unknown_device',
      }, status: HttpStatus.unauthorized);
    }
    final open = _session;
    if (_runningLocally() || (open != null && open.peerId != peerId)) {
      return sendJson(req, {'error': 'busy'}, status: HttpStatus.conflict);
    }
    if (open != null) {
      // The same peer starting over (say after a crash): its old session and
      // staged rows are dropped.
      AppLog.i('Sync session with ${peer.name} restarted');
      _end(open);
    }
    final s = _session = _Session(syncId, peerId, peer.name);
    _touch(s);
    AppLog.i('Sync session with ${peer.name}');
    _emit(WaitingFor(peer.name));
    await sendJson(req, {'ok': true});
  }

  Future<void> _changes(HttpRequest req, String? peerId) async {
    final s = _session;
    if (s == null || s.peerId != peerId) return _noSession(req);
    _touch(s);
    final q = req.uri.queryParameters;
    final since = _seq(int.tryParse(q['since'] ?? ''));
    final cursor = q.containsKey('cursor')
        ? _seq(int.tryParse(q['cursor']!))
        : null;
    final limit = (int.tryParse(q['limit'] ?? '') ?? maxPartRows).clamp(
      1,
      maxPartRows,
    );
    final feed = ChangeFeed(_db, stamp: _stamp);
    // Taken before the first page is read, so every row at or below it is
    // in the pages; rows written later go out next time.
    if (cursor == null || s.high == null) s.high = await feed.safeHigh();
    final page = await feed.since(cursor ?? since, limit: limit);
    s.sent += page.rows.length;
    _emit(
      page.next == null
          ? WaitingFor(s.peerName)
          : Receiving(SyncStage.pulling, s.sent, 0),
    );
    await sendJson(req, {
      'rows': [for (final r in page.rows) r.toWire()],
      'next': page.next,
      'high': s.high,
    });
  }

  Future<void> _part(HttpRequest req, String? peerId) async {
    final s = _open(req, peerId);
    if (s == null) return _noSession(req);
    final body = SyncServer.jsonBody(req);
    final raw = body['rows'] as List;
    if (raw.length > maxPartRows) {
      throw const FormatException('too many rows in one part');
    }
    final rows = [
      for (final r in raw)
        SyncRow.fromWire(Map<String, Object?>.from(r as Map)),
    ];
    // Malformed rows fail here (a 400), not later inside the apply.
    for (final r in rows) {
      r.toInsertable(0);
    }
    s.staged.addAll(rows);
    final total = body['total'];
    _emit(
      Receiving(SyncStage.applying, s.staged.length, total is int ? total : 0),
    );
    await sendJson(req, {'staged': s.staged.length});
  }

  Future<void> _applyCommit(HttpRequest req, String? peerId) async {
    final s = _open(req, peerId);
    if (s == null) return _noSession(req);
    final staged = s.staged;
    s.staged = [];
    s.idle?.cancel(); // the apply may take a while
    try {
      final report = await RowApplier(_db, _stamp, now: _now).apply(staged);
      s.playlistsChanged += report.playlistIds.length;
      s.songsAdded += report.tracksAdded;
      await sendJson(req, {
        'written': report.written,
        'playlists_changed': report.playlistIds.length,
        'songs_added': report.tracksAdded,
      });
    } finally {
      if (identical(_session, s)) _touch(s);
    }
  }

  Future<void> _commit(HttpRequest req, String? peerId) async {
    final s = _open(req, peerId);
    if (s == null) return _noSession(req);
    if (s.staged.isNotEmpty) {
      return sendJson(req, {
        'error': 'not_applied',
      }, status: HttpStatus.conflict);
    }
    final body = SyncServer.jsonBody(req);
    final initiatorHigh = _seq(body['initiator_high']);
    // The watermark is the high this session served, never a value the
    // initiator makes up: a mismatch, or no pull at all, is refused.
    final responderHigh = s.high;
    if (responderHigh == null || body['responder_high'] != responderHigh) {
      return sendJson(req, {
        'error': 'high_mismatch',
      }, status: HttpStatus.conflict);
    }
    await _peers.setWatermarks(
      peerId!,
      sent: responderHigh,
      received: initiatorHigh,
      at: _now(),
    );
    s.committed = true;
    if (_files != null) _emit(Receiving(SyncStage.files, 0, 0));
    await sendJson(req, {'ok': true});
  }

  // --- Files phase ----------------------------------------------------------

  /// The asking peer's session, when it is in its files phase.
  _Session? _filesSession(String? peerId) {
    final s = _session;
    if (s == null || s.peerId != peerId || !s.committed) return null;
    _touch(s);
    return s;
  }

  Future<void> _filesMissing(HttpRequest req, String? peerId) async {
    if (_filesSession(peerId) == null) return _noSession(req);
    await sendJson(req, {
      'files': [for (final r in await _files!.needs()) r.toWire()],
    });
  }

  Future<void> _filesHave(HttpRequest req, String? peerId) async {
    final s = _filesSession(peerId);
    if (s == null) return _noSession(req);
    final body = SyncServer.jsonBody(req);
    final offered = await _files!.offer(body['files'] as List);
    final pushing = body['pushing'];
    s.filesTotal =
        offered.length + (pushing is int && pushing > 0 ? pushing : 0);
    _emit(Receiving(SyncStage.files, s.filesHandled.length, s.filesTotal));
    await sendJson(req, {'files': offered});
  }

  Future<void> _fileGet(HttpRequest req, String? peerId) =>
      _transfer(req, peerId, received: false);

  Future<void> _filePut(HttpRequest req, String? peerId) =>
      _transfer(req, peerId, received: true);

  /// Sends or receives one file.
  Future<void> _transfer(
    HttpRequest req,
    String? peerId, {
    required bool received,
  }) async {
    final s = _filesSession(peerId);
    if (s == null) return _noSession(req);
    final ref = FileTransfer.refOf(req.uri).toString();
    // Each chunk keeps the session alive; a peer that stalls lets it time out.
    void alive() {
      if (identical(_session, s)) _touch(s);
    }

    try {
      final ok = received
          ? await _files!.accept(req, onChunk: alive)
          : await _files!.serve(req, onChunk: alive);
      if (!identical(_session, s)) return;
      // A retried file counts once.
      s.filesHandled.add(ref);
      if (ok) s.filesCopied++;
      _emit(Receiving(SyncStage.files, s.filesHandled.length, s.filesTotal));
    } finally {
      alive();
    }
  }

  Future<void> _filesDone(HttpRequest req, String? peerId) async {
    final s = _open(req, peerId, committed: true);
    if (s == null) return _noSession(req);
    // The initiator knows which copies passed their check on its side.
    final copied = SyncServer.jsonBody(req)['copied'];
    if (copied is int && copied >= 0) s.filesCopied = copied;
    await _finish(s);
    await sendJson(req, {'ok': true});
  }

  /// Ends [s] after its files phase: queues downloads and shows the summary.
  Future<void> _finish(_Session s) async {
    _end(s);
    try {
      await _downloads.queueNewInEnabled();
    } catch (e) {
      AppLog.w('Queueing downloads after sync failed', e);
    }
    _emit(
      ResponderDone(
        SyncSummary(
          peerName: s.peerName,
          playlistsChanged: s.playlistsChanged,
          songsAdded: s.songsAdded,
          filesCopied: s.filesCopied,
        ),
      ),
    );
  }

  Future<void> _abort(HttpRequest req, String? peerId) async {
    final s = _open(req, peerId);
    if (s != null) {
      AppLog.i('Sync with ${s.peerName} aborted');
      _end(s);
      _emit(const Idle());
    }
    await sendJson(req, {'ok': true});
  }

  Future<void> _unpair(HttpRequest req, String? peerId) async {
    final s = _session;
    if (s != null && s.peerId == peerId) {
      _end(s);
      _emit(const Idle());
    }
    await _peers.remove(peerId!);
    AppLog.i('Unpaired by $peerId');
    await sendJson(req, {'ok': true});
  }

  // --- Sessions -------------------------------------------------------------

  /// The open session named by the request's `sync_id`, if it is [peerId]'s
  /// and in the phase [committed] asks for.
  _Session? _open(HttpRequest req, String? peerId, {bool committed = false}) {
    final s = _session;
    if (s == null ||
        s.peerId != peerId ||
        s.syncId != _syncId(req) ||
        s.committed != committed) {
      return null;
    }
    _touch(s);
    return s;
  }

  /// Restarts [s]'s idle timer.
  void _touch(_Session s) {
    s.idle?.cancel();
    s.idle = _timer(idleTimeout, () {
      if (!identical(_session, s)) return;
      AppLog.w('Sync session with ${s.peerName} timed out');
      if (s.committed) {
        // Its rows are in; only files were left.
        unawaited(_finish(s));
        return;
      }
      _session = null;
      _emit(const Idle());
    });
  }

  void _end(_Session s) {
    s.idle?.cancel();
    if (identical(_session, s)) _session = null;
  }

  void _emit(ResponderState st) {
    if (!_state.isClosed) _state.add(st);
  }

  /// Drops any open session (with its staged rows) and closes [state]. The
  /// responder is not used again.
  Future<void> dispose() async {
    final s = _session;
    if (s != null) _end(s);
    await _state.close();
  }

  static Future<void> _noSession(HttpRequest req) =>
      sendJson(req, {'error': 'no_session'}, status: HttpStatus.conflict);

  static String _syncId(HttpRequest req) {
    final id = SyncServer.jsonBody(req)['sync_id'] as String;
    if (id.isEmpty || id.length > 64) {
      throw const FormatException('bad sync_id');
    }
    return id;
  }

  /// [v] as a non-negative seq; anything else is a 400.
  static int _seq(Object? v) {
    if (v is! int || v < 0) throw FormatException('bad seq: $v');
    return v;
  }
}

class _Session {
  _Session(this.syncId, this.peerId, this.peerName);

  final String syncId;
  final String peerId;
  final String peerName;
  int? high;
  int sent = 0;
  List<SyncRow> staged = [];
  int playlistsChanged = 0;
  int songsAdded = 0;

  /// Set once `/commit` saved the watermarks: only files are left.
  bool committed = false;
  final filesHandled = <String>{};
  int filesTotal = 0;

  /// Files copied either way (the initiator's count once it reports it).
  int filesCopied = 0;
  Timer? idle;
}
