import 'download_service.dart';

/// Tells the user about the download queue outside the app's own UI (the
/// Android notification). Implementations throttle [update] as they need.
abstract class DownloadNotifier {
  /// The queue changed.
  Future<void> update(DownloadSnapshot s);

  /// A run ended: the queue is empty again.
  Future<void> finished(int completed, int failed);
}

/// Shows nothing (desktop, tests).
class NoopDownloadNotifier implements DownloadNotifier {
  const NoopDownloadNotifier();

  @override
  Future<void> update(DownloadSnapshot s) async {}

  @override
  Future<void> finished(int completed, int failed) async {}
}

/// Why the queue is paused, as shown after "Paused — " in the notification
/// (and, capitalised, in the app): "waiting for Wi-Fi", "offline", …
String downloadPauseText(DownloadPause p, DateTime now) => switch (p.reason) {
  DownloadPauseReason.wifiOnly => 'waiting for Wi-Fi',
  DownloadPauseReason.offline => 'offline',
  DownloadPauseReason.diskFull => 'storage is full',
  DownloadPauseReason.throttled =>
    'YouTube is limiting downloads, retrying in ${_minutes(p, now)} min',
  DownloadPauseReason.retrying =>
    'connection problem, retrying in ${_minutes(p, now)} min',
  DownloadPauseReason.user => 'paused',
};

/// Whole minutes until the retry, rounded up, at least 1.
int _minutes(DownloadPause p, DateTime now) {
  final at = p.resumesAt;
  if (at == null) return 1;
  final ms = at.difference(now).inMilliseconds;
  return ms <= 0 ? 1 : (ms / Duration.millisecondsPerMinute).ceil();
}
