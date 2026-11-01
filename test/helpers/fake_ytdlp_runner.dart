import 'dart:async';

import 'package:songies/core/result.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

/// Canned yt-dlp runner. The first rule whose [match] substring appears in any
/// argument wins; unmatched calls return exit 1 with an unknown error.
///
/// A rule's stdout is replayed line by line to `onLine` before the run
/// completes. A rule added with [onHang] never completes until the process is
/// cancelled, after which it returns exit -1.
class FakeYtDlpRunner implements YtDlpRunner {
  final List<({String match, YtDlpRun? run})> _rules = [];
  final List<List<String>> calls = [];
  final List<Duration?> timeouts = [];
  final List<String?> processIds = [];
  final List<String> cancelled = [];
  final Map<String, Completer<void>> _hanging = {};

  /// When false, stdout is not replayed to `onLine` (lines lost in transit).
  bool replayLines = true;

  /// When set, [run] throws it.
  Object? throwOnRun;

  /// Called with each run's args before it answers (to look at files the
  /// args name while the run is still going).
  FutureOr<void> Function(List<String> args)? onRunStart;
  String? versionResult = '2026.10.21';
  Result<void> updateResult = const Ok(null);
  int updateCalls = 0;

  void on(String match, YtDlpRun run) => _rules.add((match: match, run: run));

  void onOk(String match, String stdout, {String stderr = ''}) =>
      on(match, YtDlpRun(0, stdout, stderr));

  void onFail(String match, String stderr) =>
      on(match, YtDlpRun(1, 'null', stderr));

  /// Matching runs print nothing and wait for [cancel].
  void onHang(String match) => _rules.add((match: match, run: null));

  @override
  Future<YtDlpRun> run(
    List<String> args, {
    Duration? timeout,
    void Function(String line)? onLine,
    String? processId,
  }) async {
    calls.add(List.of(args));
    timeouts.add(timeout);
    processIds.add(processId);
    await onRunStart?.call(args);
    final t = throwOnRun;
    if (t != null) throw t;
    for (final r in _rules) {
      if (!args.any((a) => a.contains(r.match))) continue;
      final run = r.run;
      if (run == null) {
        final c = _hanging[processId ?? ''] = Completer<void>();
        await c.future;
        return const YtDlpRun(-1, '', 'yt-dlp was cancelled');
      }
      if (onLine != null && replayLines) {
        for (final l in run.stdout.split(RegExp(r'\r?\n'))) {
          if (l.isNotEmpty) onLine(l);
        }
      }
      return run;
    }
    return const YtDlpRun(1, 'null', 'ERROR: no canned response');
  }

  @override
  Future<void> cancel(String processId) async {
    cancelled.add(processId);
    final c = _hanging.remove(processId);
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<String?> version() async => versionResult;

  @override
  Future<Result<void>> update() async {
    updateCalls++;
    return updateResult;
  }
}
