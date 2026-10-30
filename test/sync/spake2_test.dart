import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:songies/sync/spake2.dart';

/// Hands out the bytes of fixed scalars, so the test controls x and y. The
/// scalar is drawn as 32 big-endian bytes from `nextInt(256)`.
class _FixedRandom implements Random {
  _FixedRandom(String hex) : _bytes = _unhex(hex);
  final Uint8List _bytes;
  int _i = 0;

  @override
  int nextInt(int max) {
    assert(max == 256);
    return _bytes[_i++];
  }

  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

Uint8List _unhex(String s) {
  final clean = s.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

// RFC 9382 Appendix B, first vector (A='server', B='client').
const _w = '2ee57912099d31560b3a44b1184b9b4866e904c49d12ac5042c97dca461b1a5f';
const _x = '43dd0fd7215bdcb482879fca3220c6a968e66d70b1356cac18bb26c84a78d729';
const _pA =
    '04a56fa807caaa53a4d28dbb9853b9815c61a411118a6fe516a8798434751470'
    'f9010153ac33d0d5f2047ffdb1a3e42c9b4e6be662766e1eeb4116988ede5f912c';
const _y = 'dcb60106f276b02606d8ef0a328c02e4b629f84f89786af5befb0bc75b6e66be';
const _pB =
    '0406557e482bd03097ad0cbaa5df82115460d951e3451962f1eaf4367a420676'
    'd09857ccbc522686c83d1852abfa8ed6e4a1155cf8f1543ceca528afb591a1e0b7';
const _k =
    '0412af7e89717850671913e6b469ace67bd90a4df8ce45c2af19010175e37eed'
    '69f75897996d539356e2fa6a406d528501f907e04d97515fbe83db277b715d3325';
const _ke = '0e0672dc86f8e45565d338b0540abe69';
const _confA =
    '58ad4aa88e0b60d5061eb6b5dd93e80d9c4f00d127c65b3b35b1b5281fee38f0';
const _confB =
    'd3e2e547f1ae04f2dbdbf0fc4b79f8ecff2dff314b5d32fe9fcef2fb26dc459b';

const _fpA = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';
const _fpB = 'bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22';

void main() {
  test('matches the RFC 9382 P-256 test vector', () {
    final w = BigInt.parse(_w, radix: 16);
    final a = Spake2.initiator(
      w,
      idA: utf8.encode('server'),
      idB: utf8.encode('client'),
      random: _FixedRandom(_x),
    );
    final b = Spake2.responder(
      w,
      idA: utf8.encode('server'),
      idB: utf8.encode('client'),
      random: _FixedRandom(_y),
    );
    expect(_hex(a.message), _pA);
    expect(_hex(b.message), _pB);

    final ka = a.finish(b.message);
    final kb = b.finish(a.message);
    expect(_hex(a.debugSharedPoint), _k);
    expect(_hex(b.debugSharedPoint), _k);
    expect(_hex(ka.ke), _ke);
    expect(_hex(kb.ke), _ke);
    expect(_hex(ka.myConfirm), _confA);
    expect(_hex(ka.peerConfirm), _confB);
    expect(_hex(kb.myConfirm), _confB);
    expect(_hex(kb.peerConfirm), _confA);
    expect(ka.verifyPeer(kb.myConfirm), isTrue);
    expect(kb.verifyPeer(ka.myConfirm), isTrue);
  });

  (Spake2Keys, Spake2Keys) run(
    String codeA,
    String codeB, {
    String idBSeenByA = _fpB,
  }) {
    final a = Spake2.initiator(
      pairingScalar(codeA),
      idA: utf8.encode(_fpA),
      idB: utf8.encode(idBSeenByA),
    );
    final b = Spake2.responder(
      pairingScalar(codeB),
      idA: utf8.encode(_fpA),
      idB: utf8.encode(_fpB),
    );
    return (a.finish(b.message), b.finish(a.message));
  }

  test('same code gives the same pair key on both sides', () {
    final (a, b) = run('042917', '042917');
    expect(a.verifyPeer(b.myConfirm), isTrue);
    expect(b.verifyPeer(a.myConfirm), isTrue);
    expect(pairKeyFrom(a.ke), hasLength(32));
    expect(pairKeyFrom(a.ke), pairKeyFrom(b.ke));
    expect(pairKeyFrom(a.ke), isNot(a.ke));
  });

  test('different codes fail confirmation', () {
    final (a, b) = run('042917', '042918');
    expect(a.verifyPeer(b.myConfirm), isFalse);
    expect(b.verifyPeer(a.myConfirm), isFalse);
    expect(a.ke, isNot(b.ke));
  });

  test('different idB (a MITM certificate) fails confirmation', () {
    final mitm = 'cc33' * 16;
    final (a, b) = run('042917', '042917', idBSeenByA: mitm);
    expect(a.verifyPeer(b.myConfirm), isFalse);
    expect(b.verifyPeer(a.myConfirm), isFalse);
  });

  test('rejects an off-curve point', () {
    final a = Spake2.initiator(
      pairingScalar('123456'),
      idA: utf8.encode(_fpA),
      idB: utf8.encode(_fpB),
    );
    final offCurve = _unhex(_pB)..[64] ^= 1;
    expect(() => a.finish(offCurve), throwsFormatException);
  });

  test('rejects the identity and malformed encodings', () {
    Spake2 fresh() => Spake2.initiator(
      pairingScalar('123456'),
      idA: utf8.encode(_fpA),
      idB: utf8.encode(_fpB),
    );
    expect(
      () => fresh().finish(Uint8List.fromList([0])),
      throwsFormatException,
    );
    expect(() => fresh().finish(Uint8List(65)), throwsFormatException);
    expect(
      () => fresh().finish(Uint8List.fromList(_unhex(_pB).sublist(0, 33))),
      throwsFormatException,
    );
    // Coordinates must be below p; x = p is congruent to 0 but not canonical.
    final p = _unhex(
      'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    );
    expect(
      () => fresh().finish(Uint8List.fromList([4, ...p, ...p])),
      throwsFormatException,
    );
  });

  test('pairingScalar and pairKeyFrom match independently computed values', () {
    // SHA-256("songies-pair-v1" || "000000") mod n, computed with Python.
    expect(
      pairingScalar('000000'),
      BigInt.parse(
        '7b4146997667770bf9bb8642b2bebd5a67fdcf25be84b02af0ce188a45e96d74',
        radix: 16,
      ),
    );
    // HKDF-SHA256(ikm = the vector's Ke, empty salt, 'songies pair key v1').
    expect(
      _hex(pairKeyFrom(_unhex(_ke))),
      '80b0ca078458904025ac1419087b62e645374bdc17292af042a24746fe0559a0',
    );
  });

  test('a share that makes K the identity is rejected', () {
    // RFC 9382 §6 M and N; sending w*N (to A) or w*M (to B) zeroes K.
    final curve = ECCurve_secp256r1().curve;
    final m = curve.decodePoint(
      _unhex(
        '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f',
      ),
    )!;
    final n = curve.decodePoint(
      _unhex(
        '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49',
      ),
    )!;
    final w = pairingScalar('123456');
    Uint8List enc(ECPoint p) => Uint8List.fromList(p.getEncoded(false));
    final a = Spake2.initiator(
      w,
      idA: utf8.encode(_fpA),
      idB: utf8.encode(_fpB),
    );
    final b = Spake2.responder(
      w,
      idA: utf8.encode(_fpA),
      idB: utf8.encode(_fpB),
    );
    final degenerate = throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('degenerate'),
      ),
    );
    expect(() => a.finish(enc((n * w)!)), degenerate);
    expect(() => b.finish(enc((m * w)!)), degenerate);
  });

  test('pairingScalar accepts only six ASCII digits', () {
    for (final bad in ['', '12345', '1234567', '12345a', ' 12345', '١٢٣٤٥٦']) {
      expect(() => pairingScalar(bad), throwsArgumentError, reason: bad);
    }
    expect(pairingScalar('000000'), isA<BigInt>());
  });
}
