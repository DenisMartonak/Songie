import 'dart:async';

import '../core/log.dart';
import 'library_scanner.dart';

/// Starts a folder scan; matches [LibraryScanner.scanFolder].
typedef ScanFolder = Stream<ScanProgress> Function(
  String folder, {
  String? createPlaylistNamed,
});

/// Runs folder scans one at a time: overlapping scans of the same library are
/// not safe, so a second request waits for the first to finish.
class ScanQueue {
  ScanQueue(this._scan);

  final ScanFolder _scan;
  final StreamController<ScanProgress?> _changes =
      StreamController<ScanProgress?>.broadcast(sync: true);

  Future<void> _tail = Future<void>.value();
  int _waiting = 0;
  ScanProgress? _latest;

  /// The running scan's progress; null when the queue is idle. A new listener
  /// first gets the current value.
  Stream<ScanProgress?> get current => Stream<ScanProgress?>.multi((out) {
    final sub = _changes.stream.listen(
      out.addSync,
      onError: out.addErrorSync,
      onDone: out.closeSync,
    );
    out.addSync(_latest);
    out.onCancel = sub.cancel;
  });

  /// Scans [folder] after every earlier request has finished. Completes with
  /// the last progress (null if the scan reported none). A scan that fails is
  /// logged and rethrown to its caller; the queue carries on with the next.
  Future<ScanProgress?> enqueue(String folder, {String? createPlaylistNamed}) {
    _waiting++;
    final result = _tail.then((_) => _run(folder, createPlaylistNamed));
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<ScanProgress?> _run(String folder, String? playlistName) async {
    try {
      _publish(
        const ScanProgress(
          found: 0,
          processed: 0,
          added: 0,
          unchanged: 0,
          skipped: 0,
          done: false,
        ),
      );
      ScanProgress? last;
      await for (final progress in _scan(
        folder,
        createPlaylistNamed: playlistName,
      )) {
        last = progress;
        _publish(progress);
      }
      return last;
    } catch (e, s) {
      AppLog.e('Scan of $folder failed', e, s);
      rethrow;
    } finally {
      if (--_waiting == 0) _publish(null);
    }
  }

  void _publish(ScanProgress? progress) {
    _latest = progress;
    _changes.add(progress);
  }
}
