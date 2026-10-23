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
