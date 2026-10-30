import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';

final _group = ECCurve_secp256r1();
final _curve = _group.curve as fp.ECCurve;
final BigInt _p = _curve.q!;
final BigInt _n = _group.n;

// RFC 9382 §6, P-256 point generation seeds (compressed SEC1).
final ECPoint _m = _curve.decodePoint(
  _hexBytes(
    '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f',
  ),
)!;
final ECPoint _nPoint = _curve.decodePoint(
  _hexBytes(
    '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49',
  ),
)!;

/// SPAKE2 (RFC 9382), suite P256-SHA256-HKDF-HMAC-SHA256, no AAD.
///
/// The device that types the pairing code is A ([Spake2.initiator]); the
/// device showing it is B ([Spake2.responder]). Both use the same [idA] and
/// [idB]: the lowercase hex certificate fingerprints as bytes, with idB being
/// the fingerprint A saw over TLS. Each instance is single-use.
class Spake2 {
  Spake2.initiator(
    BigInt w, {
    required List<int> idA,
    required List<int> idB,
    Random? random,
  }) : this._(true, w, idA, idB, random);

  Spake2.responder(
    BigInt w, {
    required List<int> idA,
    required List<int> idB,
    Random? random,
  }) : this._(false, w, idA, idB, random);

  Spake2._(this._isA, BigInt w, List<int> idA, List<int> idB, Random? random)
    : _w = w % _n,
      _idA = Uint8List.fromList(idA),
      _idB = Uint8List.fromList(idB) {
    _secret = _randomScalar(random ?? Random.secure());
    final mine = (_group.G * _secret)! + ((_isA ? _m : _nPoint) * _w)!;
    message = _encode(mine!);
  }

  final bool _isA;
  final BigInt _w;
  final Uint8List _idA;
  final Uint8List _idB;
  late final BigInt _secret;
  Uint8List? _k;

  /// This side's public share (pA or pB), uncompressed SEC1.
  late final Uint8List message;

  /// The shared point K, for checking against the RFC vectors only. It is
  /// never to be used as a key.
  @visibleForTesting
  Uint8List get debugSharedPoint => _k!;

  /// Completes the exchange with the peer's share. Throws [FormatException]
  /// when [peerMessage] is not an uncompressed point on P-256 (the identity
  /// cannot be encoded that way), and [StateError] when called twice.
  Spake2Keys finish(Uint8List peerMessage) {
    if (_k != null) throw StateError('Spake2.finish called twice');
    final peer = _decode(peerMessage);
    // K = h*x*(pB - w*N) for A, h*y*(pA - w*M) for B; h = 1 on P-256.
    final unblinded = peer - ((_isA ? _nPoint : _m) * _w)!;
    final k = (unblinded! * _secret)!;
    if (k.isInfinity) throw const FormatException('SPAKE2: degenerate share');
    final kBytes = _encode(k);
    _k = kBytes;

    final pA = _isA ? message : peerMessage;
    final pB = _isA ? peerMessage : message;
    final tt = BytesBuilder(copy: false);
    for (final part in [_idA, _idB, pA, pB, kBytes, _scalarBytes(_w)]) {
      tt
        ..add(_le64(part.length))
        ..add(part);
    }
    final transcript = tt.takeBytes();
    final hash = sha256.convert(transcript).bytes;
    final ke = Uint8List.fromList(hash.sublist(0, 16));
    final ka = Uint8List.fromList(hash.sublist(16));
    final kc = hkdfSha256(ka, utf8.encode('ConfirmationKeys'), 32);
    final cA = _mac(kc.sublist(0, 16), transcript);
    final cB = _mac(kc.sublist(16), transcript);
    return Spake2Keys._(
      ke: ke,
      myConfirm: _isA ? cA : cB,
      peerConfirm: _isA ? cB : cA,
    );
  }
}

/// The outcome of [Spake2.finish]. The responder sends [myConfirm] first;
/// the initiator checks it with [verifyPeer] before sending its own.
class Spake2Keys {
  Spake2Keys._({
    required this.ke,
    required this.myConfirm,
    required this.peerConfirm,
  });

  /// The shared secret Ke (16 bytes). Valid only once confirmed.
  final Uint8List ke;

  /// The confirmation MAC this side sends.
  final Uint8List myConfirm;

  /// The confirmation MAC this side expects from the peer.
  final Uint8List peerConfirm;

  /// Constant-time check of the peer's confirmation MAC.
  bool verifyPeer(List<int> received) {
    if (received.length != peerConfirm.length) return false;
    var diff = 0;
    for (var i = 0; i < received.length; i++) {
      diff |= (received[i] ^ peerConfirm[i]) & 0xff;
    }
    return diff == 0;
  }
}

/// The SPAKE2 password scalar for a pairing code:
/// SHA-256("songies-pair-v1" || code) as an unsigned integer mod n.
BigInt pairingScalar(String code) {
  final digest = sha256.convert([
    ...utf8.encode('songies-pair-v1'),
    ...utf8.encode(code),
  ]);
  return _bytesToBigInt(digest.bytes) % _n;
}

/// The long-term pair key derived from a confirmed [Spake2Keys.ke].
Uint8List pairKeyFrom(Uint8List ke) =>
    hkdfSha256(ke, utf8.encode('songies pair key v1'), 32);

/// HKDF-SHA256 (RFC 5869) with an empty salt.
@visibleForTesting
Uint8List hkdfSha256(Uint8List ikm, List<int> info, int length) {
  final kdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(ikm, length, null, Uint8List.fromList(info)));
  return kdf.process(Uint8List(0));
}

Uint8List _mac(List<int> key, List<int> data) =>
    Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

/// Uniform in [1, n-1] by rejection sampling of 32 random bytes.
BigInt _randomScalar(Random random) {
  while (true) {
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final k = _bytesToBigInt(bytes);
    if (k > BigInt.zero && k < _n) return k;
  }
}

ECPoint _decode(Uint8List bytes) {
  if (bytes.length != 65 || bytes[0] != 0x04) {
    throw const FormatException('SPAKE2: expected an uncompressed P-256 point');
  }
  final x = _bytesToBigInt(bytes.sublist(1, 33));
  final y = _bytesToBigInt(bytes.sublist(33));
  if (x >= _p || y >= _p) {
    throw const FormatException('SPAKE2: coordinate out of range');
  }
  final a = _curve.a!.toBigInteger()!;
  final b = _curve.b!.toBigInteger()!;
  if ((y * y - (x * x * x + a * x + b)) % _p != BigInt.zero) {
    throw const FormatException('SPAKE2: point is not on P-256');
  }
  // P-256 has cofactor 1, so every affine point on the curve is in the group
  // and is not the identity.
  return _curve.createPoint(x, y);
}

Uint8List _encode(ECPoint point) => Uint8List.fromList(point.getEncoded(false));

/// Big-endian, padded to the 32-byte length of p.
Uint8List _scalarBytes(BigInt v) {
  final out = Uint8List(32);
  var rest = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest >>= 8;
  }
  return out;
}

Uint8List _le64(int v) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little);

BigInt _bytesToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
