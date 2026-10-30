import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'peer_repository.dart';

const headerDevice = 'x-songies-device';
const headerTime = 'x-songies-time';
const headerSig = 'x-songies-sig';

/// The body hash signed for file bodies, which are verified by content.
const streamBodyHash = 'stream';

/// Hex SHA-256 of a request body, as signed.
String bodyHashOf(List<int> body) => sha256.convert(body).toString();

/// The path and query of [uri] exactly as both sides sign it.
String pathAndQueryOf(Uri uri) =>
    uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

/// Base64 HMAC-SHA256 with [pairKey] over
/// `"$method\n$pathAndQuery\n$timeMs\n$bodyHash"`.
String signRequest(
  Uint8List pairKey, {
  required String method,
  required String pathAndQuery,
  required int timeMs,
  required String bodyHash,
}) => base64.encode(
  Hmac(
    sha256,
    pairKey,
  ).convert(utf8.encode('$method\n$pathAndQuery\n$timeMs\n$bodyHash')).bytes,
);

enum VerifyResult { ok, unknownDevice, stale, badSignature, replay }

/// Checks the signature headers of a request from a paired device.
class RequestVerifier {
  RequestVerifier(this._peers, {this._now = DateTime.now});

  /// Requests further than this from the receiver's clock are stale.
  static const maxSkew = Duration(seconds: 60);

  /// A signature seen within this window is a replay. It covers the whole
  /// freshness window on either side of the receiver's clock.
  static const replayWindow = Duration(seconds: 120);

  final PeerRepository _peers;
  final DateTime Function() _now;
  final _seen = <String, DateTime>{};

  Future<VerifyResult> verify(HttpRequest req, String bodyHash) async {
    final device = req.headers.value(headerDevice);
    final peer = device == null ? null : await _peers.byId(device);
    if (peer == null) return VerifyResult.unknownDevice;

    final timeMs = int.tryParse(req.headers.value(headerTime) ?? '');
    final sig = req.headers.value(headerSig);
    if (timeMs == null || sig == null) return VerifyResult.badSignature;
    final now = _now();
    final skew = now.millisecondsSinceEpoch - timeMs;
    if (skew.abs() > maxSkew.inMilliseconds) return VerifyResult.stale;

    final Uint8List key;
    try {
      key = base64.decode(peer.pairKey);
    } on FormatException {
      return VerifyResult.badSignature;
    }
    final expected = signRequest(
      key,
      method: req.method,
      pathAndQuery: pathAndQueryOf(req.uri),
      timeMs: timeMs,
      bodyHash: bodyHash,
    );
    if (!_equal(utf8.encode(expected), utf8.encode(sig))) {
      return VerifyResult.badSignature;
    }

    _seen.removeWhere((_, at) => now.difference(at).abs() > replayWindow);
    if (_seen.containsKey(sig)) return VerifyResult.replay;
    _seen[sig] = now;
    return VerifyResult.ok;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
