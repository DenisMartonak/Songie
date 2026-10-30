import 'dart:async';
import 'dart:io';

import '../core/app_version.dart';
import '../core/log.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../downloads/download_repository.dart';
import 'change_feed.dart';
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
/// - `POST /session/begin {sync_id}` (409 `busy` while a session is open or
///   this device runs a sync of its own)
/// - `GET /changes?since=&cursor=&limit=` → `{rows, next, high}`
/// - `POST /apply/part {sync_id, rows, total?}` stages at most [maxPartRows]
/// - `POST /apply/commit {sync_id}` applies every staged row in one
///   transaction → `{written, playlists_changed, songs_added}`
/// - `POST /commit {sync_id, initiator_high, responder_high}` saves the
///   watermarks and ends the session
/// - `POST /session/abort {sync_id}`, `POST /unpair`
///
/// A step of a session that is not open (or belongs to another peer) gets a
/// 409 `no_session`. A session idle for [idleTimeout] is dropped with its
/// staged rows.
class SyncResponder {
  SyncResponder({
    required this._db,
    required this._stamp,
    required this._peers,
    required this._myDeviceId,
    required this._myName,
    required this._downloads,
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
    if (_session != null || _runningLocally()) {
      return sendJson(req, {'error': 'busy'}, status: HttpStatus.conflict);
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
    final feed = ChangeFeed(_db);
    // Taken before the first page is read, so every row at or below it is
    // in the pages; rows written later go out next time.
    if (cursor == null || s.high == null) s.high = await feed.highSeq();
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
    final responderHigh = _seq(body['responder_high']);
    await _peers.setWatermarks(
      peerId!,
      sent: responderHigh,
      received: initiatorHigh,
      at: _now(),
    );
    _end(s);
    await sendJson(req, {'ok': true});
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
          filesCopied: 0,
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

  /// The open session named by the request's `sync_id`, if it is [peerId]'s.
  _Session? _open(HttpRequest req, String? peerId) {
    final s = _session;
    if (s == null || s.peerId != peerId || s.syncId != _syncId(req)) {
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
      _session = null;
      _emit(const Idle());
    });
  }

  void _end(_Session s) {
    s.idle?.cancel();
    if (identical(_session, s)) _session = null;
  }

  void _emit(ResponderState st) => _state.add(st);

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
  Timer? idle;
}
