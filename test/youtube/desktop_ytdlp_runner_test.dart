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
      start: (e, a) async => fail('must not start'),
    );
    await expectLater(r.run(['--version']), throwsA(isA<YtDlpMissing>()));
    expect(await r.version(), isNull);
  });

  test('ProcessException maps to YtDlpMissing', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/yt-dlp'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a) async => throw const ProcessException('yt-dlp', []),
    );
    await expectLater(r.run(['x']), throwsA(isA<YtDlpMissing>()));
  });

  test('systemBinary uses that executable name and passes args', () async {
    String? exe;
    List<String>? args;
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/nope'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a) async {
        exe = e;
        args = a;
        return _FakeProcess.done(3, 'out é', 'err');
      },
    );
    final run = await r.run(['-J', 'u'], timeout: const Duration(seconds: 60));
    expect(exe, 'yt-dlp');
    expect(args, ['-J', 'u']);
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
      start: (e, a) async {
        exe = e;
        return _FakeProcess.done(0, '2026.1.1\n', '');
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

  test('onLine gets stdout lines in order as they arrive', () async {
    final p = _FakeProcess();
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a) async => p,
    );
    final lines = <String>[];
    final done = r.run(['x'], onLine: lines.add, processId: 'a');
    await pumpEventQueue();
    p.out('one\ntw');
    await pumpEventQueue();
    expect(lines, ['one']);
    p.out('o\r\nthree\n');
    await pumpEventQueue();
    expect(lines, ['one', 'two', 'three']);
    p.finish(0);
    final run = await done;
    expect(run.stdout, 'one\ntwo\r\nthree\n');
    expect(lines, ['one', 'two', 'three']);
  });

  test('a last line without a newline still reaches onLine', () async {
    final p = _FakeProcess();
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, a) async => p,
    );
    final lines = <String>[];
    final done = r.run(['x'], onLine: lines.add);
    await pumpEventQueue();
    p.out('tail');
    p.finish(0);
    await done;
    expect(lines, ['tail']);
  });

  test('cancel kills the process with that id only', () async {
    final a = _FakeProcess();
    final b = _FakeProcess();
    final procs = [a, b];
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'yt-dlp',
      start: (e, args) async => procs.removeAt(0),
    );
    final runA = r.run(['x'], processId: 'a');
    await pumpEventQueue();
    final runB = r.run(['x'], processId: 'b');
    await pumpEventQueue();
    await r.cancel('a');
    expect(a.killed, isNotEmpty);
    expect(b.killed, isEmpty);
    expect((await runA).exitCode, isNot(0));
    await r.cancel('nope');
    b.finish(0);
    expect((await runB).exitCode, 0);
    // Finished runs are forgotten.
    await r.cancel('b');
    expect(b.killed, isEmpty);
  });

  test('default starter: streams lines from a real process', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'printf',
    );
    final lines = <String>[];
    final run = await r.run([r'a\nb\nc\n'], onLine: lines.add);
    expect(lines, ['a', 'b', 'c']);
    expect(run.stdout, 'a\nb\nc\n');
  }, skip: Platform.isWindows);

  test('default starter: cancel kills a real child', () async {
    final r = DesktopYtDlpRunner(
      binary: () => File('${dir.path}/x'),
      installer: installer([]),
      systemBinary: 'sleep',
    );
    final run = r.run(['32.3'], processId: 's');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await r.cancel('s');
    final res = await run.timeout(const Duration(seconds: 5));
    expect(res.exitCode, isNot(0));
    final ps = await Process.run('pgrep', [r'-f', r'^sleep 32\.3$']);
    expect(ps.exitCode, isNot(0), reason: 'sleep still running');
  }, skip: Platform.isWindows);
}

/// A process whose output and exit the test drives.
class _FakeProcess implements Process {
  _FakeProcess();

  factory _FakeProcess.done(int code, String out, String err) {
    final p = _FakeProcess();
    p.out(out);
    p._err.add(utf8.encode(err));
    p.finish(code);
    return p;
  }

  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _exit = Completer<int>();
  final List<ProcessSignal> killed = [];

  void out(String s) => _out.add(utf8.encode(s));

  void finish(int code) {
    if (_exit.isCompleted) return;
    _out.close();
    _err.close();
    _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed.add(signal);
    finish(-15);
    return true;
  }
}
