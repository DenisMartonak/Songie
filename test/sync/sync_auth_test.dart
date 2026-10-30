import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/device_identity.dart';
import 'package:songies/sync/peer_repository.dart';
import 'package:songies/sync/sync_auth.dart';
import 'package:songies/sync/sync_client.dart';
import 'package:songies/sync/sync_server.dart';

import '../helpers/test_db.dart';

final _key = Uint8List.fromList(List.generate(32, (i) => i));

PeerRow _peer(String id, Uint8List key, {String fp = ''}) => PeerRow(
  deviceId: id,
  name: 'Peer $id',
  certFingerprint: fp.isEmpty ? 'ab' * 32 : fp,
  pairKey: base64.encode(key),
  lastSentSeq: 0,
  lastReceivedSeq: 0,
);

void main() {
  late AppDatabase db;
  late PeerRepository peers;
  late Directory dir;
  late DeviceIdentity identity;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('songies_sync_auth');
    identity = await DeviceIdentity.loadOrCreate(dir);
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  setUp(() {
    db = testDb();
    peers = PeerRepository(db);
  });
  tearDown(() => db.close());

  test('signRequest is base64 HMAC-SHA256 over the canonical string', () {
    final sig = signRequest(
      _key,
      method: 'POST',
      pathAndQuery: '/a?b=1',
      timeMs: 42,
      bodyHash: 'stream',
    );
    final expected = base64.encode(
      Hmac(sha256, _key).convert(utf8.encode('POST\n/a?b=1\n42\nstream')).bytes,
    );
    expect(sig, expected);
  });

  test('schema version matches the database', () {
    expect(syncSchemaVersion, db.schemaVersion);
  });

  test('verifier accepts a fresh signature and rejects stale, replayed, tampered and unknown', () async {
    await peers.save(_peer('dev-b', _key));
    var now = DateTime.utc(2026, 10, 30, 12);
    final verifier = RequestVerifier(peers, now: () => now);
    final results = <VerifyResult>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      results.add(await verifier.verify(req, 'h' * 64));
      await req.response.close();
    });
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Future<void> send({
      String device = 'dev-b',
      required int timeMs,
      String bodyHash = '',
      Uint8List? key,
    }) async {
      const path = '/changes?since=3';
      final req = await client.get('127.0.0.1', server.port, path);
      req.headers
        ..set(headerDevice, device)
        ..set(headerTime, '$timeMs')
        ..set(
          headerSig,
          signRequest(
            key ?? _key,
            method: 'GET',
            pathAndQuery: path,
            timeMs: timeMs,
            bodyHash: bodyHash.isEmpty ? 'h' * 64 : bodyHash,
          ),
        );
      await (await req.close()).drain<void>();
    }

    final t = now.millisecondsSinceEpoch;
    await send(timeMs: t);
    await send(timeMs: t); // same signature again
    await send(timeMs: t - 61000);
    await send(timeMs: t + 61000);
    await send(timeMs: t + 1, bodyHash: 'x' * 64); // tampered body
    await send(timeMs: t + 2, key: Uint8List(32)); // wrong key
    await send(timeMs: t + 3, device: 'stranger');
    await send(timeMs: t + 59000); // within the window
    now = now.add(const Duration(seconds: 50));
    await send(timeMs: t + 50000); // fresh against the moved clock
    expect(results, [
      VerifyResult.ok,
      VerifyResult.replay,
      VerifyResult.stale,
      VerifyResult.stale,
      VerifyResult.badSignature,
      VerifyResult.badSignature,
      VerifyResult.unknownDevice,
      VerifyResult.ok,
      VerifyResult.ok,
    ]);
  });

  group('server and pinned client', () {
    late SyncServer server;
    late int port;
    final seen = <String?>[];

    setUp(() async {
      seen.clear();
      await peers.save(_peer('dev-b', _key));
      server = SyncServer(identity, RequestVerifier(peers));
      server.route('POST', '/echo', (req, peerId) async {
        seen.add(peerId);
        final body = SyncServer.jsonBody(req);
        await sendJson(req, {'got': body['value'] as int});
      });
      server.route('POST', '/open', (req, peerId) async {
        await sendJson(req, {'keys': SyncServer.jsonBody(req).keys.length});
      }, open: true);
      server.route('GET', '/hello', (req, peerId) async {
        seen.add(peerId);
        await sendJson(req, {'hi': true});
      }, open: true);
      final stored = <int>[];
      server.route('PUT', '/files/', (req, peerId) async {
        await for (final chunk in req) {
          stored.addAll(chunk);
        }
        await sendJson(req, {
          'path': req.uri.path,
          'from': req.uri.queryParameters['from'],
          'total': req.uri.queryParameters['total'],
          'ext': req.uri.queryParameters['ext'],
        });
      });
      server.route('GET', '/files/', (req, peerId) async {
        final from = int.parse(
          (req.headers.value('range') ?? 'bytes=0-').substring(6).split('-')[0],
        );
        req.response.statusCode = from > 0 ? 206 : 200;
        req.response.add(stored.sublist(from));
        await req.response.close();
      });
      port = await server.start(
        preferredPort: 0,
        address: InternetAddress.loopbackIPv4,
      );
    });
    tearDown(() => server.stop());

    SyncClient pinned({
      String? fingerprint,
      Uint8List? key,
      String device = 'dev-b',
      Duration offset = Duration.zero,
    }) {
      final c = SyncClient.pinned(
        host: '127.0.0.1',
        port: port,
        fingerprint: fingerprint ?? identity.fingerprint,
        pairKey: key ?? _key,
        myDeviceId: device,
        clockOffset: offset,
      );
      addTearDown(c.close);
      return c;
    }

    Future<SyncNetError> failure(Future<Object?> f) async {
      try {
        await f;
      } on SyncNetError catch (e) {
        return e;
      }
      fail('expected a SyncNetError');
    }

    test('signed JSON round trip names the peer', () async {
      final res = await pinned().postJson('/echo', {'value': 7});
      expect(res['got'], 7);
      expect(res['schema_version'], syncSchemaVersion);
      expect(seen, ['dev-b']);
    });

    test('open route needs no signature', () async {
      final c = SyncClient.open(host: '127.0.0.1', port: port);
      addTearDown(c.close);
      expect((await c.getJson('/hello'))['hi'], isTrue);
      expect(c.seenFingerprint, identity.fingerprint);
      expect(seen, [null]);
    });

    test('auth failures map to their kinds', () async {
      expect(
        (await failure(pinned(key: Uint8List(32)).postJson('/echo', {}))).kind,
        SyncNetKind.auth,
      );
      expect(
        (await failure(pinned(device: 'stranger').postJson('/echo', {}))).kind,
        SyncNetKind.unknownDevice,
      );
      expect(
        (await failure(
          pinned(offset: const Duration(minutes: 2))
              .postJson('/echo', {'value': 1}),
        )).kind,
        SyncNetKind.auth,
      );
      // An unsigned request to a signed route.
      final open = SyncClient.open(host: '127.0.0.1', port: port);
      addTearDown(open.close);
      expect(
        (await failure(open.postJson('/echo', {'value': 1}))).kind,
        SyncNetKind.unknownDevice,
      );
      expect(seen, isEmpty);
    });

    test('schema mismatch is a 409', () async {
      final e = await failure(
        pinned().postJson('/echo', {'schema_version': 7, 'value': 1}),
      );
      expect(e.kind, SyncNetKind.schema);
      expect(e.status, 409);
    });

    /// AppLog's console lines (it prints when no log file is set up).
    List<String> captureLog() {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (m, {wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = previous);
      return lines;
    }

    test('malformed body is a 400, not a 500, and is logged', () async {
      final log = captureLog();
      final e = await failure(pinned().postJson('/echo', {'value': 'nope'}));
      expect(e.kind, SyncNetKind.server);
      expect(e.status, 400);
      expect(e.message, contains('bad_request'));
      expect(log, [
        allOf(
          contains(' W Sync request POST /echo answered 400'),
          contains('is not a subtype'),
          isNot(contains('nope')),
        ),
      ]);
    });

    test('a StateError in a handler is a logged 400', () async {
      server.route('POST', '/state', (req, peerId) async {
        throw StateError('no such row');
      });
      final log = captureLog();
      final e = await failure(pinned().postJson('/state', {}));
      expect(e.status, 400);
      expect(log, [
        allOf(
          contains(' W Sync request POST /state answered 400'),
          contains('no such row'),
        ),
      ]);
    });

    Future<int> raw(
      String method,
      String path, {
      List<int> body = const [],
      void Function(HttpHeaders h)? headers,
    }) async {
      final http = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => http.close(force: true));
      final req = await http.openUrl(
        method,
        Uri.parse('https://127.0.0.1:$port$path'),
      );
      headers?.call(req.headers);
      req.add(body);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    test('malformed JSON bytes and non-object JSON are a 400', () async {
      expect(await raw('POST', '/open', body: utf8.encode('{"schema_')), 400);
      expect(await raw('POST', '/open', body: [0xff, 0xfe, 0x7b]), 400);
      expect(await raw('POST', '/open', body: utf8.encode('[8]')), 400);
      expect(
        await raw(
          'POST',
          '/open',
          body: utf8.encode('{"schema_version":$syncSchemaVersion}'),
        ),
        200,
      );
    });

    test('repeated signature headers are refused, not a 500', () async {
      // dart:io's client folds repeated headers into one line, so this
      // writes the request by hand, one header line per value.
      final t = DateTime.now().millisecondsSinceEpoch;
      final sig = signRequest(
        _key,
        method: 'GET',
        pathAndQuery: '/hello2',
        timeMs: t,
        bodyHash: bodyHashOf(const []),
      );
      server.route('GET', '/hello2', (req, _) => sendJson(req, {}));
      for (final repeated in [headerDevice, headerTime, headerSig]) {
        final socket = await SecureSocket.connect(
          '127.0.0.1',
          port,
          onBadCertificate: (_) => true,
        );
        socket.write(
          'GET /hello2 HTTP/1.1\r\n'
          'host: 127.0.0.1\r\n'
          'connection: close\r\n'
          '$headerDevice: dev-b\r\n'
          '$headerTime: $t\r\n'
          '$headerSig: $sig\r\n'
          '$repeated: other\r\n'
          '\r\n',
        );
        final reply = await utf8.decoder.bind(socket).join();
        socket.destroy();
        expect(reply, startsWith('HTTP/1.1 401'), reason: repeated);
      }
      expect(seen, isEmpty);
    });

    test('unknown route is a 404', () async {
      final e = await failure(pinned().getJson('/nothing'));
      expect(e.status, 404);
    });

    test('files go up and down under a prefix route', () async {
      final c = pinned();
      final bytes = List.generate(1000, (i) => i % 251);
      final res = await c.putFile(
        '/files/audio/abc?ext=mp3',
        Stream.fromIterable([bytes.sublist(0, 400), bytes.sublist(400)]),
        total: 1000,
      );
      expect(res['path'], '/files/audio/abc');
      expect(res['ext'], 'mp3');
      expect(res['from'], '0');
      expect(res['total'], '1000');
      final whole = await c
          .getFile('/files/audio/abc')
          .expand((b) => b)
          .toList();
      expect(whole, bytes);
      final tail = await c
          .getFile('/files/audio/abc', from: 600)
          .expand((b) => b)
          .toList();
      expect(tail, bytes.sublist(600));
    });

    test('wrong pinned fingerprint is refused', () async {
      final e = await failure(
        pinned(fingerprint: 'cd' * 32).postJson('/echo', {'value': 1}),
      );
      expect(e.kind, SyncNetKind.wrongCertificate);
      expect(seen, isEmpty);
    });

    test('nothing listening is unreachable', () async {
      await server.stop();
      final e = await failure(pinned().getJson('/hello'));
      expect(e.kind, SyncNetKind.unreachable);
    });
  });
}
