import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../core/log.dart';
import '../data/database.dart';
import 'device_identity.dart';
import 'pairing_code.dart';
import 'peer_repository.dart';
import 'spake2.dart';
import 'sync_client.dart';
import 'sync_server.dart';

enum PairOutcome { paired, wrongCode, noCodeShowing, unreachable }

/// Pairing by code over SPAKE2, responder confirms first.
///
/// The device showing the code (responder, RFC "B") answers
/// `POST /pair/start {msg, id_a, device_id, name}` with
/// `{msg, confirm, device_id, name}`. The device typing the code (initiator,
/// RFC "A") checks that confirmation and only on a match sends
/// `POST /pair/finish {confirm}`, so nothing it sends can be tried offline.
/// Both bind their certificate fingerprints into the transcript.
class PairingService {
  PairingService({
    required this._identity,
    required this._peers,
    required this._myDeviceId,
    required this._myName,
    this._now = DateTime.now,
  });

  final DeviceIdentity _identity;
  final PeerRepository _peers;
  final String _myDeviceId;
  final String Function() _myName;
  final DateTime Function() _now;
  final _paired = StreamController<PeerRow>.broadcast();

  PairingCode? _code;
  _Pending? _pending;

  /// True while /pair/finish saves the peer; a /pair/start then is refused.
  bool _finishing = false;

  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');
  static const _maxNameLength = 64;

  /// Peers paired on either side, as they are saved.
  Stream<PeerRow> get paired => _paired.stream;

  void register(SyncServer s) {
    s.route('POST', '/pair/start', _start, open: true);
    s.route('POST', '/pair/finish', _finish, open: true);
  }

  /// Shows a fresh code, replacing any earlier one.
  PairingCode showCode() {
    _pending = null;
    return _code = PairingCode(now: _now);
  }

  void hideCode() {
    _code = null;
    _pending = null;
  }

  // Responder.

  Future<void> _start(HttpRequest req, String? _) async {
    final code = _code;
    if (code == null || !code.usable) {
      return sendJson(req, {'error': 'no_code'}, status: HttpStatus.forbidden);
    }
    if (_finishing) {
      return sendJson(req, {'error': 'busy'}, status: HttpStatus.conflict);
    }
    final body = SyncServer.jsonBody(req);
    final msg = base64.decode(body['msg'] as String);
    final idA = body['id_a'] as String;
    final deviceId = body['device_id'] as String;
    final name = _cleanName(body['name'] as String, deviceId);
    if (!_fingerprint.hasMatch(idA) || deviceId.isEmpty) {
      throw const FormatException('bad pairing request');
    }

    // A new exchange replaces any unfinished one: one at a time.
    _pending = null;
    final spake = Spake2.responder(
      pairingScalar(code.code),
      idA: utf8.encode(idA),
      idB: utf8.encode(_identity.fingerprint),
    );
    code.chargeAttempt();
    final keys = spake.finish(msg); // a bad share throws: a 400
    _pending = _Pending(keys, deviceId, name, idA);
    await sendJson(req, {
      'msg': base64.encode(spake.message),
      'confirm': base64.encode(keys.myConfirm),
      'device_id': _myDeviceId,
      'name': _myName(),
    });
  }

  Future<void> _finish(HttpRequest req, String? _) async {
    final pending = _pending;
    _pending = null;
    final confirm = base64.decode(
      SyncServer.jsonBody(req)['confirm'] as String,
    );
    if (pending == null || _code == null || !pending.keys.verifyPeer(confirm)) {
      return sendJson(req, {'error': 'auth'}, status: HttpStatus.forbidden);
    }
    _finishing = true;
    try {
      final peer = _peerRow(
        deviceId: pending.deviceId,
        name: pending.name,
        fingerprint: pending.fingerprint,
        keys: pending.keys,
      );
      await _peers.save(peer);
      _code = null; // a code pairs once
      AppLog.i('Paired with ${peer.name}');
      _paired.add(peer);
    } finally {
      _finishing = false;
    }
    await sendJson(req, {'ok': true});
  }

  // Initiator.

  /// Pairs with the device at [host]:[port] that shows [code].
  Future<PairOutcome> pairWith(String host, int port, String code) async {
    final BigInt w;
    try {
      w = pairingScalar(code);
    } on ArgumentError {
      return PairOutcome.wrongCode;
    }
    final client = SyncClient.open(host: host, port: port);
    try {
      final theirFingerprint = await client.fetchFingerprint();
      final spake = Spake2.initiator(
        w,
        idA: utf8.encode(_identity.fingerprint),
        idB: utf8.encode(theirFingerprint),
      );
      final Map<String, dynamic> reply;
      try {
        reply = await client.postJson('/pair/start', {
          'msg': base64.encode(spake.message),
          'id_a': _identity.fingerprint,
          'device_id': _myDeviceId,
          'name': _myName(),
        });
      } on SyncNetError catch (e) {
        return switch (e.kind) {
          SyncNetKind.auth || SyncNetKind.busy => PairOutcome.noCodeShowing,
          _ => PairOutcome.unreachable,
        };
      }

      final Spake2Keys keys;
      final String deviceId;
      final String name;
      try {
        keys = spake.finish(base64.decode(reply['msg'] as String));
        if (!keys.verifyPeer(base64.decode(reply['confirm'] as String))) {
          return PairOutcome.wrongCode;
        }
        deviceId = reply['device_id'] as String;
        name = _cleanName(reply['name'] as String, deviceId);
        if (deviceId.isEmpty) return PairOutcome.wrongCode;
      } on FormatException {
        return PairOutcome.wrongCode;
      } on TypeError {
        return PairOutcome.wrongCode;
      }

      try {
        await client.postJson('/pair/finish', {
          'confirm': base64.encode(keys.myConfirm),
        });
      } on SyncNetError catch (e) {
        return e.kind == SyncNetKind.auth
            ? PairOutcome.wrongCode
            : PairOutcome.unreachable;
      }

      final peer = _peerRow(
        deviceId: deviceId,
        name: name,
        fingerprint: theirFingerprint,
        keys: keys,
      ).copyWith(host: Value(host), port: Value(port));
      await _peers.save(peer);
      AppLog.i('Paired with ${peer.name}');
      _paired.add(peer);
      return PairOutcome.paired;
    } on SyncNetError {
      return PairOutcome.unreachable;
    } finally {
      client.close();
    }
  }

  static PeerRow _peerRow({
    required String deviceId,
    required String name,
    required String fingerprint,
    required Spake2Keys keys,
  }) => PeerRow(
    deviceId: deviceId,
    name: name,
    certFingerprint: fingerprint,
    pairKey: base64.encode(pairKeyFrom(keys.ke)),
    lastSentSeq: 0,
    lastReceivedSeq: 0,
  );

  static String _cleanName(String name, String fallback) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed.length > _maxNameLength
        ? trimmed.substring(0, _maxNameLength)
        : trimmed;
  }
}

class _Pending {
  _Pending(this.keys, this.deviceId, this.name, this.fingerprint);

  final Spake2Keys keys;
  final String deviceId;
  final String name;
  final String fingerprint;
}
