import 'dart:async';

import 'package:flutter/services.dart';

import '../core/result.dart';
import 'ytdlp_runner.dart';

/// Runs yt-dlp through youtubedl-android behind the `songies/ytdlp` channel.
/// Stdout lines stream back on `songies/ytdlp_lines` as `{processId, line}`.
class AndroidYtDlpRunner implements YtDlpRunner {
  AndroidYtDlpRunner({MethodChannel? channel, EventChannel? lines})
    : _channel = channel ?? const MethodChannel('songies/ytdlp'),
      _linesChannel = lines ?? const EventChannel('songies/ytdlp_lines');

  final MethodChannel _channel;
  final EventChannel _linesChannel;
  int _seq = 0;

  /// One shared native subscription; it is open only while a run listens.
  late final Stream<({String processId, String line})> _lines = _linesChannel
      .receiveBroadcastStream()
      .map((e) {
        final m = e is Map ? e : const {};
        return (processId: '${m['processId']}', line: '${m['line'] ?? ''}');
      });

  @override
  Future<YtDlpRun> run(
    List<String> args, {
    Duration? timeout,
    void Function(String line)? onLine,
    String? processId,
  }) async {
    final id = processId ?? 'ytdlp-${_seq++}';
    // Subscribe before starting so no early line is missed.
    final sub = onLine == null
        ? null
        : _lines
              .where((e) => e.processId == id && e.line.isNotEmpty)
              .listen((e) => onLine(e.line), onError: (Object _) {});
    try {
      return await _runWith(id, args, timeout, streamLines: onLine != null);
    } finally {
      await sub?.cancel();
    }
  }

  Future<YtDlpRun> _runWith(
    String processId,
    List<String> args,
    Duration? timeout, {
    required bool streamLines,
  }) async {
    Future<YtDlpRun> call() async {
      try {
        final m = await _channel.invokeMapMethod<String, Object?>('run', {
          'args': args,
          'processId': processId,
          'streamLines': streamLines,
        });
        return YtDlpRun(
          (m?['exitCode'] as num?)?.toInt() ?? -1,
          '${m?['out'] ?? ''}',
          '${m?['err'] ?? ''}',
        );
      } on PlatformException catch (e) {
        if (e.code == 'init_failed') {
          throw YtDlpMissing(e.message ?? 'yt-dlp could not be initialised');
        }
        return YtDlpRun(-1, '', e.message ?? e.code);
      }
    }

    if (timeout == null) return call();
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      // Best effort: stop the native process.
      unawaited(cancel(processId));
      rethrow;
    }
  }

  @override
  Future<void> cancel(String processId) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'processId': processId});
    } catch (_) {
      // Best effort: the run may already be over.
    }
  }

  @override
  Future<String?> version() async {
    try {
      final v = await _channel.invokeMethod<String>('version');
      return v == null || v.trim().isEmpty ? null : v.trim();
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Result<void>> update() async {
    try {
      await _channel.invokeMethod<String>('update');
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err(
        Failure(FailureKind.unsupported, e.message ?? 'yt-dlp update failed'),
      );
    }
  }
}
