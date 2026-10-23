import 'package:songies/core/result.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

/// Canned yt-dlp runner. The first rule whose [match] substring appears in any
/// argument wins; unmatched calls return exit 1 with an unknown error.
class FakeYtDlpRunner implements YtDlpRunner {
  final List<({String match, YtDlpRun run})> _rules = [];
  final List<List<String>> calls = [];
  final List<Duration?> timeouts = [];

  /// When set, [run] throws it.
  Object? throwOnRun;
  String? versionResult = '2026.10.21';
  Result<void> updateResult = const Ok(null);
  int updateCalls = 0;

  void on(String match, YtDlpRun run) => _rules.add((match: match, run: run));

  void onOk(String match, String stdout, {String stderr = ''}) =>
      on(match, YtDlpRun(0, stdout, stderr));

  void onFail(String match, String stderr) =>
      on(match, YtDlpRun(1, 'null', stderr));

  @override
  Future<YtDlpRun> run(List<String> args, {Duration? timeout}) async {
    calls.add(List.of(args));
    timeouts.add(timeout);
    final t = throwOnRun;
    if (t != null) throw t;
    for (final r in _rules) {
      if (args.any((a) => a.contains(r.match))) return r.run;
    }
    return const YtDlpRun(1, 'null', 'ERROR: no canned response');
  }

  @override
  Future<String?> version() async => versionResult;

  @override
  Future<Result<void>> update() async {
    updateCalls++;
    return updateResult;
  }
}
