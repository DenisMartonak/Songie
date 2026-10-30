import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/sync/device_identity.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('songies_identity'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('creates once and reloads the same fingerprint', () async {
    final a = await DeviceIdentity.loadOrCreate(dir);
    final b = await DeviceIdentity.loadOrCreate(dir);
    expect(a.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(b.fingerprint, a.fingerprint);
    expect(b.certPem, a.certPem);
    expect(File('${dir.path}/cert.pem').existsSync(), isTrue);
    expect(File('${dir.path}/key.pem').existsSync(), isTrue);
    if (Platform.isLinux) {
      expect(File('${dir.path}/key.pem').statSync().mode & 0x1ff, 384); // 0600
    }
  });

  test('server context serves TLS on loopback', () async {
    final id = await DeviceIdentity.loadOrCreate(dir);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      id.serverContext(),
    );
    server.listen((r) {
      r.response
        ..write('ok')
        ..close();
    });
    X509Certificate? seen;
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        seen = cert;
        return true;
      };
    try {
      final req = await client.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/'),
      );
      final res = await req.close();
      await res.drain<void>();
      expect(seen, isNotNull);
      expect(DeviceIdentity.fingerprintOf(seen!), id.fingerprint);
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test('corrupt files are regenerated and the old ones kept as .bak', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
    addTearDown(() => debugPrint = original);
    final a = await DeviceIdentity.loadOrCreate(dir);
    File('${dir.path}/cert.pem').writeAsStringSync('garbage cert');
    final b = await DeviceIdentity.loadOrCreate(dir);
    expect(b.fingerprint, isNot(a.fingerprint));
    expect(logs.single, contains('regenerating'));
    expect(logs.single, isNot(contains('PRIVATE')));
    expect(File('${dir.path}/cert.pem.bak').readAsStringSync(), 'garbage cert');
    expect(File('${dir.path}/key.pem.bak').readAsStringSync(), a.keyPem);
    expect((await DeviceIdentity.loadOrCreate(dir)).fingerprint, b.fingerprint);
  });

  test('an unreadable file throws and nothing is overwritten', () async {
    final a = await DeviceIdentity.loadOrCreate(dir);
    final key = File('${dir.path}/key.pem');
    Process.runSync('chmod', ['000', key.path]);
    addTearDown(() => Process.runSync('chmod', ['600', key.path]));
    var readable = true;
    try {
      key.readAsStringSync();
    } on FileSystemException {
      readable = false;
    }
    if (readable) return; // running as root: cannot simulate
    await expectLater(
      DeviceIdentity.loadOrCreate(dir),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${dir.path}/cert.pem').readAsStringSync(), a.certPem);
    expect(File('${dir.path}/cert.pem.bak').existsSync(), isFalse);
    expect(File('${dir.path}/key.pem.bak').existsSync(), isFalse);
  }, skip: !Platform.isLinux);
}
