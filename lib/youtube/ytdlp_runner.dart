import '../core/result.dart';

/// Thrown by a runner when the yt-dlp binary cannot be found or started.
class YtDlpMissing implements Exception {
  const YtDlpMissing([this.message = 'yt-dlp is not installed']);
  final String message;

  @override
  String toString() => 'YtDlpMissing: $message';
}

class YtDlpRun {
  const YtDlpRun(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract class YtDlpRunner {
  /// Runs yt-dlp with [args]. May throw [YtDlpMissing]; a run that exceeds
  /// [timeout] throws a `TimeoutException`.
  ///
  /// [onLine] gets each stdout line (without its line break) as it arrives;
  /// the result's `stdout` still holds all of it. [processId] names the run
  /// for [cancel].
  Future<YtDlpRun> run(
    List<String> args, {
    Duration? timeout,
    void Function(String line)? onLine,
    String? processId,
  });

  /// Stops the run started with [processId], if it is still going. The run
  /// then completes with a non-zero exit code.
  Future<void> cancel(String processId);

  Future<String?> version();
  Future<Result<void>> update();
}
