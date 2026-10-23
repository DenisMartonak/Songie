// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/result.dart';
import 'ytdlp_installer.dart';
import 'ytdlp_runner.dart';

/// Starts [executable] with [args]; throws [ProcessException] when it cannot.
typedef YtDlpProcessStarter = Future<Process> Function(
  String executable,
  List<String> args,
);

Future<Process> _defaultStart(String exe, List<String> args) =>
    Process.start(exe, args, runInShell: false);

/// Asks [proc] to stop, then force-kills it if it is still alive after 2 s.
void _kill(Process proc) {
  proc.kill();
  unawaited(
    proc.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    ),
  );
}

/// Forwards each complete line from a [LineSplitter] to a callback.
class _LineSink implements Sink<String> {
  _LineSink(this._onLine);
  final void Function(String line) _onLine;

  @override
  void add(String line) => _onLine(line);

  @override
  void close() {}
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

  /// Live runs by processId, for [cancel].
  final Map<String, Process> _running = {};

  @override
  Future<YtDlpRun> run(
    List<String> args, {
    Duration? timeout,
    void Function(String line)? onLine,
    String? processId,
  }) async {
    final String exe;
    if (_system != null) {
      exe = _system;
    } else {
      final f = _binary();
      if (!f.existsSync()) throw const YtDlpMissing();
      exe = f.path;
    }
    final Process proc;
    try {
      proc = await _start(exe, args);
    } on ProcessException catch (e) {
      throw YtDlpMissing(
        e.message.isEmpty ? 'yt-dlp could not be started' : e.message,
      );
    }
    if (processId != null) _running[processId] = proc;
    try {
      final out = StringBuffer();
      final lines = onLine == null
          ? null
          : const LineSplitter().startChunkedConversion(_LineSink(onLine));
      final outDone = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((chunk) {
            out.write(chunk);
            lines?.add(chunk);
          })
          .whenComplete(() => lines?.close());
      final err = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final code = timeout == null
          ? await proc.exitCode
          : await proc.exitCode.timeout(
              timeout,
              onTimeout: () {
                _kill(proc);
                throw TimeoutException('yt-dlp timed out', timeout);
              },
            );
      await outDone;
      return YtDlpRun(code, out.toString(), await err);
    } finally {
      if (processId != null && identical(_running[processId], proc)) {
        _running.remove(processId);
      }
    }
  }

  @override
  Future<void> cancel(String processId) async {
    final proc = _running[processId];
    if (proc != null) _kill(proc);
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
