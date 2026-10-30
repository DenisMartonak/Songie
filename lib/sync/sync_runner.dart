import 'dart:async';
import 'dart:convert';

import '../core/ids.dart';
import '../core/log.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../downloads/download_repository.dart';
import 'change_feed.dart';
import 'merger.dart';
import 'peer_repository.dart';
import 'row_applier.dart';
import 'sync_client.dart';
import 'sync_progress.dart';
import 'sync_row.dart';

/// Asks the user about playlist clashes; null means they left without
/// deciding.
typedef ChooseClashes = Future<Map<String, Resolution>?> Function(
  List<PlaylistClash> clashes,
);

/// Copies files both ways after the commit and returns how many were copied
/// (Task 9's `FileTransfer`).
typedef FilesStep = Future<int> Function(SyncClient c, SyncCancel? cancel);

/// Drives a two-way sync with a paired device's [SyncResponder] (spec "A sync
/// run"): hello → begin → pull → merge → choose → stage → apply → commit →
/// files → downloads.
///
/// Nothing changes on either side until every row is staged on the peer, so a
/// cancel or a break up to then leaves both devices as they were. After that
/// each side applies in one transaction and the watermarks move only once
/// both have, so a rerun converges.
class SyncRunner {
  SyncRunner({
    required this._db,
    required this._stamp,
    required this._peers,
    required this._myDeviceId,
    required this._downloads,
    this._files,
    this._now = DateTime.now,
  });

  /// Rows per page pulled and per part sent.
  static const pageSize = 500;

  final AppDatabase _db;
  final SyncStamp _stamp;
  final PeerRepository _peers;
  final String _myDeviceId;
  final DownloadRepository _downloads;
  final FilesStep? _files;
  final DateTime Function() _now;

  bool _running = false;

  /// Whether a run is in progress (one at a time).
  bool get running => _running;

  /// Syncs with [peer] at [host]:[port]. The stream ends with one [SyncDone]
  /// or [SyncFailed]; it never errors. Cancelling its subscription works like
  /// [cancel].
  Stream<SyncProgress> run(
    PeerRow peer, {
    required String host,
    required int port,
    required ChooseClashes choose,
    SyncCancel? cancel,
  }) {
    // Cancelling the subscription cancels the run.
    final token = cancel ?? SyncCancel();
    var finished = false;
    final out = StreamController<SyncProgress>();
    out.onCancel = () {
      if (!finished) token.cancel();
    };
    out.onListen = () async {
      if (_running) {
        out.add(const SyncFailed(SyncFailure.busy));
      } else {
        _running = true;
        try {
          out.add(
            await _Run(this, peer, host, port, choose, token, out.add).go(),
          );
        } finally {
          _running = false;
        }
      }
      finished = true;
      await out.close();
    };
    return out.stream;
  }

  /// Tells [peer] at [host]:[port] to forget this device. Returns whether it
  /// confirmed; the caller removes the peer here either way.
  Future<bool> unpair(
    PeerRow peer, {
    required String host,
    required int port,
  }) async {
    SyncClient? client;
    try {
      client = await _connect(peer, host, port);
      await client.postJson('/unpair', const {});
      return true;
    } on SyncNetError catch (e) {
      AppLog.w('Unpair of ${peer.name} not confirmed', e);
      return false;
    } finally {
      client?.close();
    }
  }

  /// Says hello and returns a client that signs with the peer's clock.
  /// Throws [SyncNetError] (kind `schema` on a version mismatch).
  Future<SyncClient> _connect(PeerRow peer, String host, int port) async {
    SyncClient client({Duration offset = Duration.zero}) => SyncClient.pinned(
      host: host,
      port: port,
      fingerprint: peer.certFingerprint,
      pairKey: base64.decode(peer.pairKey),
      myDeviceId: _myDeviceId,
      clockOffset: offset,
    );
    final hello = client();
    try {
      final h = await hello.getJson('/hello');
      final time = h['time_ms'];
      if (time is! int) {
        throw SyncNetError(SyncNetKind.server, 'bad hello');
      }
      return client(
        offset: Duration(milliseconds: time - _now().millisecondsSinceEpoch),
      );
    } finally {
      hello.close();
    }
  }
}

class _Cancelled implements Exception {}

/// The state of one [SyncRunner.run].
class _Run {
  _Run(
    this._r,
    this._peer,
    this._host,
    this._port,
    this._choose,
    this._cancel,
    this._emit,
  );

  final SyncRunner _r;
  PeerRow _peer;
  final String _host;
  final int _port;
  final ChooseClashes _choose;
  final SyncCancel? _cancel;
  final void Function(SyncProgress) _emit;

  SyncClient? _client;
  String? _syncId;

  /// Set once the peer saved its watermarks; there is nothing to abort then.
  bool _committed = false;

  void _check() {
    if (_cancel?.isCancelled ?? false) throw _Cancelled();
  }

  Future<SyncProgress> go() async {
    var helloDone = false;
    try {
      final fresh = await _r._peers.byId(_peer.deviceId);
      if (fresh == null) return const SyncFailed(SyncFailure.forgotten);
      _peer = fresh;

      _emit(const SyncStep(SyncStage.hello));
      final client = _client = await _r._connect(_peer, _host, _port);
      helloDone = true;
      _check();
      final syncId = _syncId = newId();
      await client.postJson('/session/begin', {'sync_id': syncId});
      _check();

      final (theirs, responderHigh) = await _pull(client);

      _emit(const SyncStep(SyncStage.merging));
      final feed = ChangeFeed(_r._db, stamp: _r._stamp);
      // Before reading: rows written from now on go out next time.
      final initiatorHigh = await feed.safeHigh();
      final mine = await _readAll(feed, _peer.lastSentSeq);
      _check();
      final merger = Merger(stamp: _r._stamp, peerName: _peer.name);
      final merged = merger.merge(mine, theirs);
      var choices = const <String, Resolution>{};
      if (merged.clashes.isNotEmpty) {
        _emit(SyncStep(SyncStage.choosing, total: merged.clashes.length));
        final answer = await _choose(await _named(merged.clashes));
        if (answer == null) throw _Cancelled();
        choices = answer;
      }
      _check();
      final rows = await merger.resolve(merged, choices, DbLocalView(_r._db));

      // Stage on the peer first: a break or cancel here changes nothing.
      final toSend = _changedFrom(rows, theirs);
      _emit(SyncStep(SyncStage.applying, total: toSend.length));
      for (var i = 0; i < toSend.length; i += SyncRunner.pageSize) {
        final part = toSend.skip(i).take(SyncRunner.pageSize).toList();
        await client.postJson('/apply/part', {
          'sync_id': syncId,
          'rows': [for (final r in part) r.toWire()],
          'total': toSend.length,
        });
        _emit(
          SyncStep(
            SyncStage.applying,
            done: i + part.length,
            total: toSend.length,
          ),
        );
        _check();
      }
      _check(); // the last point where cancelling changes nothing

      final report = await RowApplier(
        _r._db,
        _r._stamp,
        now: _r._now,
      ).apply(_changedFrom(rows, mine));
      await client.postJson('/apply/commit', {'sync_id': syncId});

      _emit(const SyncStep(SyncStage.finishing));
      await client.postJson('/commit', {
        'sync_id': syncId,
        'initiator_high': initiatorHigh,
        'responder_high': responderHigh,
      });
      _committed = true;
      await _r._peers.setWatermarks(
        _peer.deviceId,
        sent: initiatorHigh,
        received: responderHigh,
        at: _r._now(),
      );

      var filesCopied = 0;
      final files = _r._files;
      if (files != null) {
        _emit(const SyncStep(SyncStage.files));
        filesCopied = await files(client, _cancel);
      }
      try {
        await _r._downloads.queueNewInEnabled();
      } catch (e) {
        AppLog.w('Queueing downloads after sync failed', e);
      }
      AppLog.i('Synced with ${_peer.name}');
      return SyncDone(
        SyncSummary(
          peerName: _peer.name,
          playlistsChanged: report.playlistIds.length,
          songsAdded: report.tracksAdded,
          filesCopied: filesCopied,
        ),
      );
    } on _Cancelled {
      await _abort();
      return const SyncFailed(SyncFailure.cancelled);
    } on SyncNetError catch (e) {
      AppLog.w('Sync with ${_peer.name} failed', e);
      await _abort();
      return SyncFailed(_failureOf(e, helloDone: helloDone));
    } catch (e, st) {
      AppLog.e('Sync with ${_peer.name} failed', e, st);
      await _abort();
      return const SyncFailed(SyncFailure.network);
    } finally {
      _client?.close();
    }
  }

  /// Every change of the peer since the watermark, and its high seq.
  Future<(List<SyncRow>, int)> _pull(SyncClient client) async {
    _emit(const SyncStep(SyncStage.pulling));
    final rows = <SyncRow>[];
    int? high;
    int? cursor;
    do {
      final page = await client.getJson(
        '/changes?since=${_peer.lastReceivedSeq}'
        '${cursor == null ? '' : '&cursor=$cursor'}'
        '&limit=${SyncRunner.pageSize}',
      );
      for (final r in page['rows'] as List) {
        rows.add(SyncRow.fromWire(Map<String, Object?>.from(r as Map)));
      }
      high ??= page['high'] as int;
      cursor = page['next'] as int?;
      _emit(SyncStep(SyncStage.pulling, done: rows.length));
      _check();
    } while (cursor != null);
    return (rows, high);
  }

  static Future<List<SyncRow>> _readAll(ChangeFeed feed, int since) async {
    final rows = <SyncRow>[];
    int? cursor = since;
    while (cursor != null) {
      final page = await feed.since(cursor, limit: SyncRunner.pageSize);
      rows.addAll(page.rows);
      cursor = page.next;
    }
    return rows;
  }

  /// [clashes] with a missing name read from the local playlist row.
  Future<List<PlaylistClash>> _named(List<PlaylistClash> clashes) async {
    final local = DbLocalView(_r._db);
    return [
      for (final c in clashes)
        c.name != null
            ? c
            : PlaylistClash(
                playlistId: c.playlistId,
                name:
                    (await local.row(
                          SyncTable.playlists,
                          c.playlistId,
                        ))?.data['name']
                        as String?,
                mineDeleted: c.mineDeleted,
                theirsDeleted: c.theirsDeleted,
                mine: c.mine,
                theirs: c.theirs,
              ),
    ];
  }

  /// The rows of [rows] that differ from the side's own version in [side]:
  /// a side never needs its own rows back (its applier would skip them).
  static List<SyncRow> _changedFrom(List<SyncRow> rows, List<SyncRow> side) {
    final have = {
      for (final r in side) '${r.table.wire}/${r.id}': r.contentHash,
    };
    return [
      for (final r in rows)
        if (have['${r.table.wire}/${r.id}'] != r.contentHash) r,
    ];
  }

  /// Best effort: tells the peer to drop the session and its staged rows.
  Future<void> _abort() async {
    final client = _client;
    final syncId = _syncId;
    if (client == null || syncId == null || _committed) return;
    try {
      await client.postJson('/session/abort', {'sync_id': syncId});
    } on SyncNetError catch (e) {
      AppLog.w('Sync abort not delivered', e);
    }
  }

  static SyncFailure _failureOf(SyncNetError e, {required bool helloDone}) =>
      switch (e.kind) {
        SyncNetKind.schema => SyncFailure.schemaMismatch,
        SyncNetKind.busy => SyncFailure.busy,
        SyncNetKind.unknownDevice => SyncFailure.forgotten,
        // Nobody, or another device, answers at the stored address.
        SyncNetKind.unreachable ||
        SyncNetKind.timeout ||
        SyncNetKind.wrongCertificate when !helloDone => SyncFailure.notFound,
        _ => SyncFailure.network,
      };
}
