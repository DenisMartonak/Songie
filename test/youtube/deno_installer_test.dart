import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/deno_installer.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('denoinst'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<int> zipOf(String name, List<int> data) {
    final a = Archive()..addFile(ArchiveFile(name, data.length, data));
    return ZipEncoder().encode(a);
  }

  final linuxZip = zipOf('deno', utf8.encode('fake-deno'));
  final windowsZip = zipOf('deno.exe', utf8.encode('fake-deno-exe'));
  String hex(List<int> b) => sha256.convert(b).toString();

  late List<List<String>> runs;
  late int versionExit;

  DenoInstaller make({
    required bool isWindows,
    String? sums,
    Object? throwOnZip,
    List<Uri>? seen,
    List<(int, int?)>? progress,
  }) {
    runs = [];
    final zip = isWindows ? windowsZip : linuxZip;
    return DenoInstaller(
      dir,
      isWindows: isWindows,
      download: (uri, {onProgress}) async {
        seen?.add(uri);
        if (uri.path.endsWith('.sha256sum')) {
          return utf8.encode(sums ?? '${hex(zip)}  ${uri.pathSegments.last}');
        }
        if (throwOnZip != null) throw throwOnZip;
        onProgress?.call(zip.length, zip.length);
        return zip;
      },
      runProcess: (exe, args) async {
        runs.add([exe, ...args]);
        if (args.contains('--version')) {
          return ProcessResult(0, versionExit, 'deno 2.5.6 (stable)\nv8\n', '');
        }
        return ProcessResult(0, 0, '', '');
      },
    );
  }

  setUp(() => versionExit = 0);

  List<String> leftovers() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList();

  test('installs, marks executable, checks it runs', () async {
    final seen = <Uri>[];
    final progress = <(int, int?)>[];
    final i = make(isWindows: false, seen: seen);
    final r = await i.install(onProgress: (a, b) => progress.add((a, b)));
    expect(r, isA<Ok<String>>());
    expect((r as Ok<String>).value, 'deno 2.5.6 (stable)');
    expect(File('${dir.path}/deno').readAsStringSync(), 'fake-deno');
    expect(runs.any((c) => c.first == 'chmod' && c.contains('+x')), isTrue);
    expect(seen.map((u) => u.pathSegments.last), [
      'deno-x86_64-unknown-linux-gnu.zip.sha256sum',
      'deno-x86_64-unknown-linux-gnu.zip',
    ]);
    expect(progress, isNotEmpty);
    expect(leftovers(), ['deno']);
  });

  test('Windows reads the PowerShell checksum table', () async {
    final sums =
        'Algorithm Hash Path\n--------- ---- ----\n'
        'SHA256    ${hex(windowsZip).toUpperCase()}    '
        r'D:\a\deno\deno-x86_64-pc-windows-msvc.zip';
    final r = await make(isWindows: true, sums: sums).install();
    expect(r, isA<Ok<String>>());
    expect(File('${dir.path}/deno.exe').existsSync(), isTrue);
  });

  test('a checksum mismatch leaves nothing behind', () async {
    final r = await make(isWindows: false, sums: '${'0' * 64}  x').install();
    expect(r, isA<Err<String>>());
    expect(leftovers(), isEmpty);
  });

  test('a failed download is a network error, nothing left', () async {
    final r = await make(
      isWindows: false,
      throwOnZip: const SocketException('cut off'),
    ).install();
    expect((r as Err<String>).failure.kind, FailureKind.network);
    expect(leftovers(), isEmpty);
  });

  test('a binary that does not run is removed', () async {
    versionExit = 1;
    final r = await make(isWindows: false).install();
    expect(r, isA<Err<String>>());
    expect(leftovers(), isEmpty);
  });

  test('remove deletes the installed Deno', () async {
    final i = make(isWindows: false);
    await i.install();
    await i.remove();
    expect(i.binary.existsSync(), isFalse);
  });
}
