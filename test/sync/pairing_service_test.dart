import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/device_identity.dart';
import 'package:songies/sync/pairing_code.dart';
import 'package:songies/sync/pairing_service.dart';
import 'package:songies/sync/peer_repository.dart';
import 'package:songies/sync/spake2.dart';
import 'package:songies/sync/sync_auth.dart';
import 'package:songies/sync/sync_client.dart';
import 'package:songies/sync/sync_server.dart';

import '../helpers/test_db.dart';

/// One simulated device: identity, database, server and pairing service.
class _Device {
  _Device._(this.id, this.identity, this.db, this.peers, this.pairing);

  final String id;
  final DeviceIdentity identity;
  final AppDatabase db;
  final PeerRepository peers;
  final PairingService pairing;
  SyncServer? server;
  int port = 0;

  static Future<_Device> create(
    Directory root,
    String id, {
    DateTime Function() now = DateTime.now,
  }) async {
    final identity = await DeviceIdentity.loadOrCreate(
      Directory('${root.path}/$id'),
    );
    final db = testDb();
    final peers = PeerRepository(db);
    final pairing = PairingService(
      identity: identity,
      peers: peers,
      myDeviceId: id,
      myName: () => 'Name of $id',
      now: now,
    );
    return _Device._(id, identity, db, peers, pairing);
  }

  Future<void> serve() async {
    final s = SyncServer(identity, RequestVerifier(peers));
    pairing.register(s);
    server = s;
    port = await s.start(
      preferredPort: 0,
      address: InternetAddress.loopbackIPv4,
    );
  }

  Future<void> dispose() async {
    await server?.stop();
    await db.close();
  }
}

/// A code that is not [code].
String _other(String code) =>
    ((int.parse(code) + 1) % 1000000).toString().padLeft(6, '0');

void main() {
  late Directory root;
  late _Device a; // types the code (initiator)
  late _Device b; // shows the code (responder)
  var now = DateTime(2026, 10, 30, 12);

  final previousWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  final previousPrint = debugPrint;
  setUpAll(() async {
    // Two devices means two in-memory databases at once.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
    root = Directory.systemTemp.createTempSync('songies_pairing');
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarn;
    debugPrint = previousPrint;
    root.deleteSync(recursive: true);
  });

  setUp(() async {
    now = DateTime(2026, 10, 30, 12);
    a = await _Device.create(root, 'dev-a');
    b = await _Device.create(root, 'dev-b', now: () => now);
    await b.serve();
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('pairs over loopback with the right code', () async {
    final code = b.pairing.showCode();
    final bSaw = b.pairing.paired.first;
    final aSaw = a.pairing.paired.first;
    final outcome = await a.pairing.pairWith('127.0.0.1', b.port, code.code);
    expect(outcome, PairOutcome.paired);

    final onA = await a.peers.byId('dev-b');
    final onB = await b.peers.byId('dev-a');
    expect(onA, isNotNull);
    expect(onB, isNotNull);
    expect(onA!.certFingerprint, b.identity.fingerprint);
    expect(onB!.certFingerprint, a.identity.fingerprint);
    expect(onA.name, 'Name of dev-b');
    expect(onB.name, 'Name of dev-a');
    expect(onA.pairKey, onB.pairKey);
    expect(base64.decode(onA.pairKey), hasLength(32));
    expect(onA.host, '127.0.0.1');
    expect(onA.port, b.port);
    expect((await aSaw).deviceId, 'dev-b');
    expect((await bSaw).deviceId, 'dev-a');

    // The code is used up by a successful pairing.
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, code.code),
      PairOutcome.noCodeShowing,
    );
  });

  test('wrong code five times invalidates the code', () async {
    final code = b.pairing.showCode();
    for (var i = 0; i < PairingCode.maxAttempts; i++) {
      expect(
        await a.pairing.pairWith('127.0.0.1', b.port, _other(code.code)),
        PairOutcome.wrongCode,
      );
    }
    expect(code.usable, isFalse);
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, code.code),
      PairOutcome.noCodeShowing,
    );
    expect(await a.peers.byId('dev-b'), isNull);
    expect(await b.peers.byId('dev-a'), isNull);
  });

  test('a wrong code then the right one pairs', () async {
    final code = b.pairing.showCode();
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, _other(code.code)),
      PairOutcome.wrongCode,
    );
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, code.code),
      PairOutcome.paired,
    );
  });

  test('a bad share is a 400 and still charges an attempt', () async {
    final code = b.pairing.showCode();
    final c = SyncClient.open(host: '127.0.0.1', port: b.port);
    addTearDown(c.close);
    final offCurve = Uint8List(65)..[0] = 4; // (0, 0) is not on P-256
    for (var i = 0; i < PairingCode.maxAttempts; i++) {
      try {
        await c.postJson('/pair/start', {
          'msg': base64.encode(offCurve),
          'id_a': a.identity.fingerprint,
          'device_id': 'dev-a',
          'name': 'A',
        });
        fail('expected a 400');
      } on SyncNetError catch (e) {
        expect(e.status, 400);
      }
    }
    expect(code.usable, isFalse);
  });

  test('expired code is refused', () async {
    final code = b.pairing.showCode();
    now = now.add(PairingCode.lifetime);
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, code.code),
      PairOutcome.noCodeShowing,
    );
    expect(await b.peers.byId('dev-a'), isNull);
  });

  test('no code showing and hidden code are refused', () async {
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, '123456'),
      PairOutcome.noCodeShowing,
    );
    final code = b.pairing.showCode();
    b.pairing.hideCode();
    expect(
      await a.pairing.pairWith('127.0.0.1', b.port, code.code),
      PairOutcome.noCodeShowing,
    );
  });

  test('nothing listening is unreachable', () async {
    final port = b.port;
    await b.server!.stop();
    b.server = null;
    expect(
      await a.pairing.pairWith('127.0.0.1', port, '123456'),
      PairOutcome.unreachable,
    );
  });

  test('a fake device showing pairing learns nothing usable', () async {
    // The attacker does not know the code the user types, so it answers as
    // an honest responder with a guess.
    final fake = await _Device.create(root, 'dev-fake');
    addTearDown(() async {
      await fake.server?.stop();
      await fake.db.close();
    });
    final server = SyncServer(fake.identity, RequestVerifier(fake.peers));
    Map<String, dynamic>? recorded;
    var finishes = 0;
    server.route('POST', '/pair/start', (req, _) async {
      recorded = SyncServer.jsonBody(req);
      final guess = Spake2.responder(
        pairingScalar('000000'),
        idA: utf8.encode(recorded!['id_a'] as String),
        idB: utf8.encode(fake.identity.fingerprint),
      );
      final keys = guess.finish(base64.decode(recorded!['msg'] as String));
      await sendJson(req, {
        'msg': base64.encode(guess.message),
        'confirm': base64.encode(keys.myConfirm),
        'device_id': 'dev-fake',
        'name': 'Totally B',
      });
    }, open: true);
    server.route('POST', '/pair/finish', (req, _) async {
      finishes++;
      await sendJson(req, {'ok': true});
    }, open: true);
    final port = await server.start(
      preferredPort: 0,
      address: InternetAddress.loopbackIPv4,
    );
    fake.server = server;

    expect(
      await a.pairing.pairWith('127.0.0.1', port, '424242'),
      PairOutcome.wrongCode,
    );
    expect(recorded, isNotNull);
    expect(finishes, 0, reason: 'the initiator never sends its confirmation');
    expect(await a.peers.byId('dev-fake'), isNull);

    // By construction: the initiator's confirmation depends on the
    // responder's own random scalar, so knowing the right code and the
    // recorded message is not enough to reproduce it offline.
    final idA = utf8.encode(a.identity.fingerprint);
    final idB = utf8.encode(fake.identity.fingerprint);
    final w = pairingScalar('424242');
    final initiator = Spake2.initiator(
      w,
      idA: idA,
      idB: idB,
      random: Random(1),
    );
    final honest = Spake2.responder(w, idA: idA, idB: idB, random: Random(2));
    final aKeys = initiator.finish(honest.message);
    final replay = Spake2.responder(w, idA: idA, idB: idB, random: Random(3));
    final offline = replay.finish(initiator.message);
    expect(offline.peerConfirm, isNot(aKeys.myConfirm));
    expect(offline.verifyPeer(aKeys.myConfirm), isFalse);
    expect(offline.ke, isNot(aKeys.ke));
  });

  test('the code is never sent in clear', () async {
    // The start message carries only the SPAKE2 share, never the code.
    final fake = await _Device.create(root, 'dev-spy');
    addTearDown(() async {
      await fake.server?.stop();
      await fake.db.close();
    });
    final server = SyncServer(fake.identity, RequestVerifier(fake.peers));
    String? raw;
    server.route('POST', '/pair/start', (req, _) async {
      raw = jsonEncode(SyncServer.jsonBody(req));
      await sendJson(req, {'error': 'no_code'}, status: 403);
    }, open: true);
    final port = await server.start(
      preferredPort: 0,
      address: InternetAddress.loopbackIPv4,
    );
    fake.server = server;
    await a.pairing.pairWith('127.0.0.1', port, '987654');
    expect(raw, isNotNull);
    expect(raw, isNot(contains('987654')));
    expect((jsonDecode(raw!) as Map).keys.toSet(), {
      'schema_version',
      'msg',
      'id_a',
      'device_id',
      'name',
    });
    expect(
      Uint8List.fromList(base64.decode(jsonDecode(raw!)['msg'] as String)),
      hasLength(65),
    );
  });
}
