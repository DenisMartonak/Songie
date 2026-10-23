import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/desktop_ytdlp_runner.dart';
import 'package:songies/youtube/ytdlp_installer.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ytrun'));
  tearDown(() => dir.deleteSync(recursive: true));

  YtDlpInstaller installer(List<String> calls) => YtDlpInstaller(
    dir,
    isWindows: false,
    download: (uri) async => utf8.encode('x'),
    runProcess: (exe, args) async {
      calls.add(exe);
      return ProcessResult(0, 0, '1.0\n', '');
    },
  );

  test('missing binary throws YtDlpMissing', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/yt-dlp'),
      installer: installer([]),
      start: (e, a, t) async => fail('must not start'),
    );
    await expectLater(r.run(['--version']), throwsA(isA<YtDlpMissing>()));
    expect(await r.version(), isNull);
  });

  test('ProcessException maps to YtDlpMissing', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/yt-dlp'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a, t) async => throw const ProcessException('yt-dlp', []),
    );
    await expectLater(r.run(['x']), throwsA(isA<YtDlpMissing>()));
  });

  test('systemBinary uses that executable name and passes args', () async {
    String? exe;
    List<String>? args;
    Duration? to;
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/nope'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a, t) async {
        exe = e;
        args = a;
        to = t;
        return ProcessResult(0, 3, 'out é', 'err');
      },
    );
    final run = await r.run(['-J', 'u'], timeout: const Duration(seconds: 60));
    expect(exe, 'yt-dlp');
    expect(args, ['-J', 'u']);
    expect(to, const Duration(seconds: 60));
    expect(run.exitCode, 3);
    expect(run.stdout, 'out é');
    expect(run.stderr, 'err');
  });

  test('uses managed binary path when present', () async {
    final f = File('${dir.path}/yt-dlp')..writeAsStringSync('x');
    String? exe;
    final r = DesktopYtDlpRunner(
      binary: () => f,
      installer: installer([]),
      start: (e, a, t) async {
        exe = e;
        return ProcessResult(0, 0, '2026.1.1\n', '');
      },
    );
    expect(await r.version(), '2026.1.1');
    expect(exe, f.path);
  });

  test('update: system mode is unsupported', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/yt-dlp'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
    );
    final res = await r.update();
    final f = (res as Err<void>).failure;
    expect(f.kind, FailureKind.unsupported);
    expect(
      f.message,
      'Using system yt-dlp — update it with your package manager',
    );
  });

  test('update: delegates to installer', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/yt-dlp'),
      installer: YtDlpInstaller(
        dir,
        isWindows: false,
        download: (uri) async => throw const SocketException('offline'),
      ),
    );
    final res = await r.update();
    expect((res as Err<void>).failure.kind, FailureKind.network);
  });

  test('default starter: timeout throws and kills the child', () async {
    final f = File('${dir.path}/yt-dlp')..writeAsStringSync('x');
    final r = DesktopYtDlpRunner(
      binary: () => f,
      installer: installer([]),
      systemBinary: 'sleep',
    );
    final sw = Stopwatch()..start();
    await expectLater(
      r.run(['31.7'], timeout: const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ps = await Process.run('pgrep', [r'-f', r'^sleep 31\.7$']);
    expect(ps.exitCode, isNot(0), reason: 'sleep still running');
  }, skip: Platform.isWindows);

  test('default starter: decodes utf8 and tolerates malformed bytes', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'printf',
    );
    final run = await r.run([r'caf\303\251 \377']);
    expect(run.exitCode, 0);
    expect(run.stdout.startsWith('café '), isTrue);
  }, skip: Platform.isWindows);
}
