import 'dart:async';

import 'package:flutter/services.dart';

import '../core/result.dart';
import 'ytdlp_runner.dart';

/// Runs yt-dlp through youtubedl-android behind the `songies/ytdlp` channel.
class AndroidYtDlpRunner implements YtDlpRunner {
  AndroidYtDlpRunner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('songies/ytdlp');

  final MethodChannel _channel;
  int _seq = 0;

  @override
  Future<YtDlpRun> run(List<String> args, {Duration? timeout}) async {
    final processId = 'ytdlp-${_seq++}';
    Future<YtDlpRun> call() async {
      try {
        final m = await _channel.invokeMapMethod<String, Object?>('run', {
          'args': args,
          'processId': processId,
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
      unawaited(
        _channel
            .invokeMethod<void>('cancel', {'processId': processId})
            .catchError((Object _) {}),
      );
      rethrow;
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
