// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/result.dart';
import 'ytdlp_installer.dart';
import 'ytdlp_runner.dart';

/// Starts [executable] and returns its result; throws [TimeoutException]
/// (after killing the process) if [timeout] elapses.
typedef YtDlpProcessStarter = Future<ProcessResult> Function(
  String executable,
  List<String> args,
  Duration? timeout,
);

Future<ProcessResult> _defaultStart(
  String exe,
  List<String> args,
  Duration? timeout,
) async {
  final proc = await Process.start(exe, args, runInShell: false);
  final out = proc.stdout.transform(utf8.decoder).join();
  final err = proc.stderr.transform(utf8.decoder).join();
  final Future<int> exit = timeout == null
      ? proc.exitCode
      : proc.exitCode.timeout(
          timeout,
          onTimeout: () {
            proc.kill();
            throw TimeoutException('yt-dlp timed out', timeout);
          },
        );
  final code = await exit;
  return ProcessResult(proc.pid, code, await out, await err);
}

class DesktopYtDlpRunner implements YtDlpRunner {
  DesktopYtDlpRunner({
    required File Function() binary,
    required YtDlpInstaller installer,
    String? systemBinary,
    YtDlpProcessStarter? start,
  }) : _binary = binary,
       _installer = installer,
       _system = systemBinary,
       _start = start ?? _defaultStart;

  final File Function() _binary;
  final YtDlpInstaller _installer;
  final String? _system;
  final YtDlpProcessStarter _start;

  @override
  Future<YtDlpRun> run(List<String> args, {Duration? timeout}) async {
    final String exe;
    if (_system != null) {
      exe = _system;
    } else {
      final f = _binary();
      if (!f.existsSync()) throw const YtDlpMissing();
      exe = f.path;
    }
    final ProcessResult r;
    try {
      r = await _start(exe, args, timeout);
    } on ProcessException catch (e) {
      throw YtDlpMissing(
        e.message.isEmpty ? 'yt-dlp could not be started' : e.message,
      );
    }
    return YtDlpRun(r.exitCode, '${r.stdout}', '${r.stderr}');
  }

  @override
  Future<String?> version() async {
    try {
      final r = await run(['--version'], timeout: const Duration(seconds: 15));
      final v = r.stdout.trim();
      return r.exitCode == 0 && v.isNotEmpty ? v : null;
    } on YtDlpMissing {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<Result<void>> update() async {
    if (_system != null) {
      return const Err(
        Failure(
          FailureKind.unsupported,
          'Using system yt-dlp — update it with your package manager',
        ),
      );
    }
    final r = await _installer.installOrUpdate();
    return switch (r) {
      Ok() => const Ok(null),
      Err(:final failure) => Err(failure),
    };
  }
}
