import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/core/result.dart';
import 'package:songies/youtube/ytdlp_installer.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ytinst'));
  tearDown(() => dir.deleteSync(recursive: true));

  final bytes = utf8.encode('fake-binary-bytes');
  final hash = sha256.convert(bytes).toString();

  YtDlpInstaller make({
    required bool isWindows,
    String? sums,
    Object? throwOn,
    List<Uri>? seen,
  }) {
    final name = isWindows ? 'yt-dlp.exe' : 'yt-dlp_linux';
    return YtDlpInstaller(
      dir,
      isWindows: isWindows,
      download: (uri) async {
        seen?.add(uri);
        if (throwOn != null) throw throwOn;
        if (uri.pathSegments.last == 'SHA2-256SUMS') {
          return utf8.encode(sums ?? '$hash  $name\n${'0' * 64}  other-file\n');
        }
        return bytes;
      },
      runProcess: (exe, args) async => ProcessResult(0, 0, '2026.10.01\n', ''),
    );
  }

  test('good hash installs exact bytes and returns version (linux)', () async {
    final seen = <Uri>[];
    final inst = make(isWindows: false, seen: seen);
    final r = await inst.installOrUpdate();
    expect(r, isA<Ok<String>>());
    expect((r as Ok<String>).value, '2026.10.01');
    expect(inst.binary.path, p.join(dir.path, 'yt-dlp'));
    expect(inst.binary.readAsBytesSync(), bytes);
    expect(File('${inst.binary.path}.download').existsSync(), isFalse);
    expect(
      seen.map((u) => u.toString()),
      contains(
        'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux',
      ),
    );
  });

  test('windows uses yt-dlp.exe', () async {
    final inst = make(isWindows: true);
    expect(await inst.installOrUpdate(), isA<Ok<String>>());
    expect(inst.binary.path, p.join(dir.path, 'yt-dlp.exe'));
  });

  test('bad hash is Err(io) and old binary untouched', () async {
    final inst = make(isWindows: false, sums: '${'a' * 64}  yt-dlp_linux\n');
    inst.binary.writeAsBytesSync([1, 2, 3]);
    final r = await inst.installOrUpdate();
    expect(r, isA<Err<String>>());
    final f = (r as Err<String>).failure;
    expect(f.kind, FailureKind.io);
    expect(f.message, 'yt-dlp download failed verification');
    expect(inst.binary.readAsBytesSync(), [1, 2, 3]);
    expect(File('${inst.binary.path}.download').existsSync(), isFalse);
  });

  test('missing sums line is a verification failure', () async {
    final inst = make(isWindows: false, sums: '$hash  something-else\n');
    final r = await inst.installOrUpdate();
    expect((r as Err<String>).failure.kind, FailureKind.io);
    expect(inst.binary.existsSync(), isFalse);
  });

  test('download throw is Err(network), old binary unchanged', () async {
    final inst = make(isWindows: false, throwOn: const SocketException('x'));
    inst.binary.writeAsBytesSync([9]);
    final r = await inst.installOrUpdate();
    expect((r as Err<String>).failure.kind, FailureKind.network);
    expect(inst.binary.readAsBytesSync(), [9]);
  });

  for (final thrown in [false, true]) {
    test('failing version check (throw=$thrown) keeps old binary', () async {
      final inst = YtDlpInstaller(
        dir,
        isWindows: false,
        download: (uri) async => uri.pathSegments.last == 'SHA2-256SUMS'
            ? utf8.encode('$hash  yt-dlp_linux\n')
            : bytes,
        runProcess: (exe, args) async {
          if (exe == 'chmod') return ProcessResult(0, 0, '', '');
          if (thrown) throw const ProcessException('x', []);
          return ProcessResult(0, 1, '', 'boom');
        },
      );
      inst.binary.writeAsBytesSync([7, 7]);
      final r = await inst.installOrUpdate();
      expect(r, isA<Err<String>>());
      expect(inst.binary.readAsBytesSync(), [7, 7]);
      expect(File('${inst.binary.path}.download').existsSync(), isFalse);
    });
  }

  test('a hanging --version run times out and keeps the old binary', () async {
    final inst = YtDlpInstaller(
      dir,
      isWindows: false,
      download: (uri) async => uri.pathSegments.last == 'SHA2-256SUMS'
          ? utf8.encode('$hash  yt-dlp_linux\n')
          : bytes,
      runProcess: (exe, args) {
        if (exe == 'chmod') return Future.value(ProcessResult(0, 0, '', ''));
        return Completer<ProcessResult>().future; // never finishes
      },
      versionTimeout: const Duration(milliseconds: 50),
    );
    inst.binary.writeAsBytesSync([7, 7]);
    final r = await inst.installOrUpdate();
    expect(r, isA<Err<String>>());
    expect(inst.binary.readAsBytesSync(), [7, 7]);
    expect(File('${inst.binary.path}.download').existsSync(), isFalse);
  });

  group('httpDownload (loopback server)', () {
    late HttpServer server;
    late Future<void> Function(HttpRequest) handler;
    final open = <HttpResponse>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => handler(req));
    });
    tearDown(() async {
      for (final r in open) {
        try {
          await r.detachSocket().then((s) => s.destroy());
        } on Object {
          // already closed
        }
      }
      open.clear();
      await server.close(force: true);
    });

    Uri url() => Uri.parse('http://127.0.0.1:${server.port}/f');

    test('downloads the body', () async {
      handler = (req) async {
        req.response.add([1, 2, 3]);
        await req.response.close();
      };
      expect(await httpDownload(url()), [1, 2, 3]);
    });

    test('a stalled body hits the idle timeout', () async {
      handler = (req) async {
        req.response.contentLength = 100;
        req.response.add([1, 2, 3]);
        await req.response.flush();
        open.add(req.response); // then nothing more
      };
      await expectLater(
        httpDownload(url(), idleTimeout: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('no response headers hits the idle timeout', () async {
      handler = (req) async => open.add(req.response);
      await expectLater(
        httpDownload(url(), idleTimeout: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a trickling body hits the overall cap', () async {
      handler = (req) async {
        req.response.contentLength = 1000;
        open.add(req.response);
        for (var i = 0; i < 40; i++) {
          try {
            req.response.add([i]);
            await req.response.flush();
          } on Object {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      };
      await expectLater(
        httpDownload(
          url(),
          idleTimeout: const Duration(seconds: 5),
          totalTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
