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
}
