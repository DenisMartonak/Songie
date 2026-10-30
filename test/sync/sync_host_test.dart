import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/sync/device_identity.dart';
import 'package:songies/sync/discovery.dart';
import 'package:songies/sync/merger.dart';
import 'package:songies/sync/pairing_service.dart';
import 'package:songies/sync/peer_repository.dart';
import 'package:songies/sync/sync_client.dart';
import 'package:songies/sync/sync_host.dart';
import 'package:songies/sync/sync_progress.dart';
import 'package:songies/sync/sync_responder.dart';

import '../helpers/sync_devices.dart';
import '../helpers/test_db.dart';

/// Records what the host advertises; [emit] plays what browsing finds.
class FakeDiscovery implements Discovery {
  final advertised = <({String id, String name, int port, bool pairing})>[];
  final _found = StreamController<List<FoundDevice>>.broadcast();
  bool advertising = false;
  bool browsing = false;
  bool disposed = false;

  ({String id, String name, int port, bool pairing}) get last =>
      advertised.last;

  void emit(List<FoundDevice> devices) => _found.add(devices);

  @override
  Future<void> advertise({
    required String id,
    required String name,
    required int port,
    required bool pairing,
  }) async {
    advertised.add((id: id, name: name, port: port, pairing: pairing));
    advertising = true;
  }

  @override
  Future<void> stopAdvertising() async => advertising = false;

  @override
  Stream<List<FoundDevice>> get found => _found.stream;

  @override
  Future<void> startBrowsing() async => browsing = true;

  @override
  Future<void> dispose() async {
    advertising = false;
    browsing = false;
    disposed = true;
    await _found.close();
  }
}

/// One simulated device around a [SyncHost].
class _Dev {
  _Dev._(this.name, this.identity, this.db, this.stamp, this.peers);

  final String name;
  final DeviceIdentity identity;
  final AppDatabase db;
  final SyncStamp stamp;
  final PeerRepository peers;
  final discoveries = <FakeDiscovery>[];
  late final SyncHost host;

  String get id => stamp.deviceId;
  FakeDiscovery get discovery => discoveries.last;
  int get port => host.port!;

  FoundDevice found({bool pairing = false, int? port}) => FoundDevice(
    id: id,
    name: name,
    host: '127.0.0.1',
    port: port ?? this.port,
    pairing: pairing,
  );

  static Future<_Dev> create(
    Directory root,
    String name, {
    Duration findTimeout = SyncHost.findTimeout,
  }) async {
    final db = testDb();
    final d = _Dev._(
      name,
      await testIdentity(root, name),
      db,
      await SyncStamp.load(db),
      PeerRepository(db),
    );
    d.host = SyncHost(
      db: db,
      stamp: d.stamp,
      peers: d.peers,
      identity: d.identity,
      downloads: DownloadRepository(db),
      myName: () => name,
      discovery: () {
        final f = FakeDiscovery();
        d.discoveries.add(f);
        return f;
      },
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      findTimeout: findTimeout,
    );
    await d.host.start();
    return d;
  }

  Future<void> dispose() async {
    await host.dispose();
    await db.close();
  }
}

Future<void> _pairRows(_Dev a, _Dev b, {String? host, int? port}) async {
  final rnd = Random.secure();
  final key = base64.encode([for (var i = 0; i < 32; i++) rnd.nextInt(256)]);
  PeerRow row(_Dev other) => PeerRow(
    deviceId: other.id,
    name: other.name,
    certFingerprint: other.identity.fingerprint,
    pairKey: key,
    lastSentSeq: 0,
    lastReceivedSeq: 0,
  );
  await a.peers.save(row(b).copyWith(host: Value(host), port: Value(port)));
  await b.peers.save(row(a));
}

Future<Map<String, Resolution>?> _noClashes(List<PlaylistClash> c) async =>
    fail('unexpected clash');

/// A loopback port nobody listens on.
Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// Lets stream listeners and the peers table watch catch up.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  final root = setUpSyncDevices('songies_sync_host_');
  final devs = <_Dev>[];

  Future<_Dev> dev(String name, {Duration? findTimeout}) async {
    final d = await _Dev.create(
      root(),
      name,
      findTimeout: findTimeout ?? SyncHost.findTimeout,
    );
    devs.add(d);
    return d;
  }

  tearDown(() async {
    for (final d in devs) {
      await d.dispose();
    }
    devs.clear();
  });

  test(
    'pairByCode tries each pairing device and pairs with the right one',
    () async {
      final a = await dev('A');
      final b = await dev('B');
      final c = await dev('C');
      final code = a.host.showCode();
      final other = c.host.showCode();
      expect(other.code, isNot(code.code)); // vanishingly rare otherwise
      final runs = <HostRun>[];
      b.host.runs.listen(runs.add);

      b.discovery.emit([c.found(pairing: true), a.found(pairing: true)]);
      await _settle();
      expect(await b.host.pairByCode(code.code), FindOutcome.paired);

      final peerA = await b.peers.byId(a.id);
      expect(peerA?.name, 'A');
      expect((peerA?.host, peerA?.port), ('127.0.0.1', a.port));
      expect(await a.peers.byId(b.id), isNotNull);
      expect(await c.peers.byId(b.id), isNull);

      // The device that typed the code syncs straight away.
      expect(runs.single.peerId, a.id);
      final events = await runs.single.progress.toList();
      expect(events.last, isA<SyncDone>());

      // A's code paired once, so A stops advertising pairing.
      await _settle();
      expect(a.discovery.last.pairing, isFalse);
    },
  );

  test(
    'pairByCode reports wrongCode when devices answer but none match',
    () async {
      final a = await dev('A');
      final b = await dev('B', findTimeout: const Duration(milliseconds: 300));
      final code = a.host.showCode().code;
      final wrong = ((int.parse(code) + 1) % 1000000).toString().padLeft(
        6,
        '0',
      );
      b.discovery.emit([a.found(pairing: true)]);
      await _settle();
      expect(await b.host.pairByCode(wrong), FindOutcome.wrongCode);
      expect(await b.peers.byId(a.id), isNull);
    },
  );

  test('pairByCode waits for discovery to report devices', () async {
    final a = await dev('A');
    final b = await dev('B');
    final code = a.host.showCode().code;
    final outcome = b.host.pairByCode(code);
    await _settle();
    b.discovery.emit([a.found()]); // not pairing yet: skipped
    await _settle();
    b.discovery.emit([a.found(pairing: true)]);
    expect(await outcome, FindOutcome.paired);
  });

  test('pairByCode reports noneFound after 10 seconds', () async {
    final b = await dev('B');
    expect(SyncHost.findTimeout, const Duration(seconds: 10));
    fakeAsync((async) {
      FindOutcome? outcome;
      b.host.pairByCode('123456').then((o) => outcome = o);
      async.elapse(const Duration(milliseconds: 9900));
      expect(outcome, isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(outcome, FindOutcome.noneFound);
    });
  });

  test('own advertisement is ignored', () async {
    final a = await dev('A');
    final b = await dev('B', findTimeout: const Duration(milliseconds: 300));
    final code = a.host.showCode().code;
    final views = <List<SyncDeviceView>>[];
    b.host.devices.listen(views.add);
    // An entry with B's own id is skipped, wherever it points (here at A,
    // which would pair).
    b.discovery.emit([
      FoundDevice(
        id: b.id,
        name: 'B',
        host: '127.0.0.1',
        port: a.port,
        pairing: true,
      ),
    ]);
    await _settle();
    expect(await b.host.pairByCode(code), FindOutcome.noneFound);
    expect(await b.peers.byId(a.id), isNull);
    expect(views.expand((v) => v), isEmpty);
  });

  test('pairByAddress pairs and starts a sync', () async {
    final a = await dev('A');
    final b = await dev('B');
    final code = a.host.showCode().code;
    final runs = <HostRun>[];
    b.host.runs.listen(runs.add);
    expect(
      await b.host.pairByAddress('127.0.0.1', a.port, code),
      PairOutcome.paired,
    );
    expect(runs.single.peerId, a.id);
    expect((await runs.single.progress.toList()).last, isA<SyncDone>());
  });

  test('remembered peer at a new address', () async {
    final a = await dev('A');
    final b = await dev('B');
    await _pairRows(b, a, host: '127.0.0.1', port: await _deadPort());

    b.discovery.emit([a.found()]);
    await _settle();
    final events = await b.host.sync(a.id, choose: _noClashes).toList();
    expect(events.last, isA<SyncDone>());
    final peer = await b.peers.byId(a.id);
    expect((peer?.host, peer?.port), ('127.0.0.1', a.port));
  });

  test(
    'a paired device found on the network gets its address stored',
    () async {
      final a = await dev('A');
      final b = await dev('B');
      await _pairRows(a, b); // B's row for A has no address (responder side)
      final views = <List<SyncDeviceView>>[];
      b.host.devices.listen(views.add);
      b.discovery.emit([a.found()]);
      await _settle();
      final peer = await b.peers.byId(a.id);
      expect((peer?.host, peer?.port), ('127.0.0.1', a.port));
      expect(views.last.single.peer.deviceId, a.id);
      expect(views.last.single.online?.port, a.port);
    },
  );

  test('remembered peer not on the network fails as notFound', () async {
    final a = await dev('A');
    final b = await dev('B');
    await _pairRows(b, a, host: '127.0.0.1', port: await _deadPort());
    final events = await b.host.sync(a.id, choose: _noClashes).toList();
    expect((events.last as SyncFailed).failure, SyncFailure.notFound);

    // With no stored address either, it fails without trying.
    final c = await dev('C');
    await _pairRows(b, c);
    final none = await b.host.sync(c.id, choose: _noClashes).toList();
    expect(none.map((e) => (e as SyncFailed).failure), [SyncFailure.notFound]);
  });

  test('showCode advertises pairing and hideCode clears it', () async {
    final a = await dev('A');
    expect(a.discovery.browsing, isTrue);
    expect(a.discovery.last, (
      id: a.id,
      name: 'A',
      port: a.port,
      pairing: false,
    ));
    a.host.showCode();
    await _settle();
    expect(a.discovery.last.pairing, isTrue);
    a.host.hideCode();
    await _settle();
    expect(a.discovery.last.pairing, isFalse);
  });

  test('stop closes the server and the advertisement', () async {
    final a = await dev('A');
    final port = a.port;
    final discovery = a.discovery;
    await a.host.stop();
    expect(discovery.advertising, isFalse);
    expect(discovery.disposed, isTrue);
    expect(a.host.port, isNull);
    final client = SyncClient.open(host: '127.0.0.1', port: port);
    await expectLater(client.getJson('/hello'), throwsA(isA<SyncNetError>()));
    client.close();

    // start() again serves anew; a second start() is a no-op.
    await a.host.start();
    await a.host.start();
    expect(a.discoveries, hasLength(2));
    expect(a.discovery.advertising, isTrue);
    final again = SyncClient.open(host: '127.0.0.1', port: a.port);
    expect((await again.getJson('/hello'))['device_id'], a.id);
    again.close();
  });

  test('a local run is refused while a peer has a session open here', () async {
    final a = await dev('A');
    final b = await dev('B');
    final c = await dev('C');
    await _pairRows(a, b, host: '127.0.0.1', port: b.port);
    await _pairRows(c, a, host: '127.0.0.1', port: a.port);
    final states = <ResponderState>[];
    a.host.responder.listen(states.add);

    final cPeerA = (await c.peers.byId(a.id))!;
    final client = SyncClient.pinned(
      host: '127.0.0.1',
      port: a.port,
      fingerprint: cPeerA.certFingerprint,
      pairKey: base64.decode(cPeerA.pairKey),
      myDeviceId: c.id,
    );
    await client.postJson('/session/begin', {'sync_id': 's1'});
    await _settle();
    expect(states.last, isA<WaitingFor>());

    final events = await a.host.sync(b.id, choose: _noClashes).toList();
    expect(events.map((e) => (e as SyncFailed).failure), [SyncFailure.busy]);
    client.close();
  });

  test('a peer is refused while a local run is in progress', () async {
    final a = await dev('A');
    final c = await dev('C');
    // A syncs with "B" at an address that accepts and never answers.
    final hang = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    hang.listen(sockets.add);
    final b = await dev('B');
    await _pairRows(a, b, host: '127.0.0.1', port: hang.port);
    await _pairRows(c, a, host: '127.0.0.1', port: a.port);

    final run = a.host.sync(b.id, choose: _noClashes).toList();
    await _settle();
    final cPeerA = (await c.peers.byId(a.id))!;
    final client = SyncClient.pinned(
      host: '127.0.0.1',
      port: a.port,
      fingerprint: cPeerA.certFingerprint,
      pairKey: base64.decode(cPeerA.pairKey),
      myDeviceId: c.id,
    );
    await expectLater(
      client.postJson('/session/begin', {'sync_id': 's1'}),
      throwsA(
        isA<SyncNetError>().having((e) => e.kind, 'kind', SyncNetKind.busy),
      ),
    );
    client.close();
    for (final s in sockets) {
      s.destroy();
    }
    await hang.close();
    expect((await run).last, isA<SyncFailed>());
  });

  test('unpair tells the peer and removes it here', () async {
    final a = await dev('A');
    final b = await dev('B');
    await _pairRows(b, a, host: '127.0.0.1', port: a.port);
    await b.host.unpair(a.id);
    expect(await b.peers.byId(a.id), isNull);
    expect(await a.peers.byId(b.id), isNull);
  });

  test('unpair removes the peer even when it is unreachable', () async {
    final a = await dev('A');
    final b = await dev('B');
    await _pairRows(b, a, host: '127.0.0.1', port: await _deadPort());
    await b.host.unpair(a.id);
    expect(await b.peers.byId(a.id), isNull);
  });

  test('pausing stops the host and resuming starts it again', () async {
    final a = await dev('A');
    await a.host.onLifecycle(AppLifecycleState.paused);
    expect(a.host.port, isNull);
    expect(a.discoveries.first.disposed, isTrue);
    await a.host.onLifecycle(AppLifecycleState.resumed);
    expect(a.host.port, isNotNull);
    expect(a.discovery.advertising, isTrue);
  });

  test('pausing during a run stops the host once the run ends', () async {
    final a = await dev('A');
    final hang = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    hang.listen(sockets.add);
    final b = await dev('B');
    await _pairRows(a, b, host: '127.0.0.1', port: hang.port);

    final run = a.host.sync(b.id, choose: _noClashes).toList();
    await _settle();
    await a.host.onLifecycle(AppLifecycleState.paused);
    expect(a.host.port, isNotNull);
    for (final s in sockets) {
      s.destroy();
    }
    await hang.close();
    await run;
    await _settle();
    expect(a.host.port, isNull);
  });

  test('localAddresses lists no loopback address', () async {
    final a = await dev('A');
    final addresses = await a.host.localAddresses();
    for (final s in addresses) {
      final ip = InternetAddress(s);
      expect(ip.type, InternetAddressType.IPv4);
      expect(ip.isLoopback, isFalse);
    }
  });
}
