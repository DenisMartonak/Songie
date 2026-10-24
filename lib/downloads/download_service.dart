import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../core/connectivity.dart';
import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/settings_repository.dart';
import '../youtube/yt_models.dart';
import '../youtube/ytdlp_client.dart';
import 'download_notifier.dart';
import 'download_repository.dart';

/// `throttled` is the backoff wait after an HTTP 429; `retrying` is the same
/// wait after a network error while the device still reports a connection.
/// Both carry a `resumesAt`. `offline` is only for a device that reports no
/// connection.
enum DownloadPauseReason { wifiOnly, offline, throttled, retrying, diskFull }

/// Why the queue is not starting downloads, and when it resumes by itself
/// (only for [DownloadPauseReason.throttled] and [DownloadPauseReason.retrying]).
class DownloadPause {
  const DownloadPause(this.reason, {this.resumesAt});

  final DownloadPauseReason reason;
  final DateTime? resumesAt;

  @override
  bool operator ==(Object other) =>
      other is DownloadPause &&
      other.reason == reason &&
      other.resumesAt == resumesAt;

  @override
  int get hashCode => Object.hash(reason, resumesAt);

  @override
  String toString() => 'DownloadPause($reason, resumesAt: $resumesAt)';
}

/// Bytes of one running download; [total] may be an estimate, or unknown.
class TrackProgress {
  const TrackProgress(this.downloaded, this.total);

  final int downloaded;
  final int? total;

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (downloaded / t).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is TrackProgress &&
      other.downloaded == downloaded &&
      other.total == total;

  @override
  int get hashCode => Object.hash(downloaded, total);

  @override
  String toString() => 'TrackProgress($downloaded / $total)';
}

/// The queue at one moment.
///
/// A run starts when the queue goes from empty to non-empty and ends when it
/// is empty again; the `…ThisRun` counts keep their values after a run ends
/// until the next one starts.
class DownloadSnapshot {
  const DownloadSnapshot({
    this.queued = 0,
    this.active = 0,
    this.completedThisRun = 0,
    this.failedThisRun = 0,
    this.totalThisRun = 0,
    this.progress = const {},
    this.pause,
    this.userPaused = false,
    this.extractorFailing = false,
    this.currentTitle,
  });

  final int queued;
  final int active;
  final int completedThisRun;
  final int failedThisRun;
  final int totalThisRun;

  /// Running downloads by track id.
  final Map<String, TrackProgress> progress;
  final DownloadPause? pause;

  /// The user paused downloads ([DownloadService.pauseByUser]): no new
  /// download starts, running ones finish.
  final bool userPaused;

  /// The last download failed in a way that suggests yt-dlp is outdated;
  /// cleared by the next success.
  final bool extractorFailing;

  /// The title of the most recently started running download.
  final String? currentTitle;

  static const _maps = MapEquality<String, TrackProgress>();

  @override
  bool operator ==(Object other) =>
      other is DownloadSnapshot &&
      other.queued == queued &&
      other.active == active &&
      other.completedThisRun == completedThisRun &&
      other.failedThisRun == failedThisRun &&
      other.totalThisRun == totalThisRun &&
      _maps.equals(other.progress, progress) &&
      other.pause == pause &&
      other.userPaused == userPaused &&
      other.extractorFailing == extractorFailing &&
      other.currentTitle == currentTitle;

  @override
  int get hashCode => Object.hash(
    queued,
    active,
    completedThisRun,
    failedThisRun,
    totalThisRun,
    _maps.hash(progress),
    pause,
    userPaused,
    extractorFailing,
    currentTitle,
  );

  @override
  String toString() =>
      'DownloadSnapshot(queued: $queued, active: $active, '
      'done: $completedThisRun, failed: $failedThisRun, '
      'total: $totalThisRun, pause: $pause, userPaused: $userPaused, '
      'extractorFailing: $extractorFailing, title: $currentTitle)';
}

/// Why the service cancelled a running download itself. Its result then
/// counts as cancelled whatever the runner reports: the runner can't tell a
/// cancel from a failure, and a cancel can be lost.
enum _Stop {
  /// The row is gone: delete what was downloaded.
  unwanted,

  /// The queue paused: back to the queue.
  paused,
}

class _Job {
  _Job(this.trackId, this.videoId, this.title);

  final String trackId;
  final String videoId;
  final String? title;
  String get processId => 'dl-$trackId';

  /// yt-dlp was asked to run.
  bool started = false;

  /// Its result is in.
  bool finished = false;

  /// A cancel was sent again after the run started (the first may be lost).
  bool recancelled = false;
}

/// The YouTube download queue: runs up to [concurrency] yt-dlp downloads at a
/// time, oldest request first, and pauses for Wi-Fi only, lost connectivity,
/// throttling and a full disk.
///
/// Driven by events only (repository watchers, network changes, results);
/// the one timer is the throttling backoff.
class DownloadService {
  DownloadService({
    required this._repo,
    required this._client,
    required this._network,
    required this._settings,
    required this._ytDir,
    required this._concurrency,
    required this._onDownloaded,
    required this._onUnavailable,
    DownloadNotifier? notifier,
    bool? wifiOnlyFallback,
    DateTime Function()? now,
  }) : _notifier = notifier ?? const NoopDownloadNotifier(),
       _wifiOnlyFallback = wifiOnlyFallback ?? wifiOnlyDefault(),
       _now = now ?? DateTime.now;

  final DownloadRepository _repo;
  final YtDlpClient _client;
  final NetworkStatus _network;
  final SettingsRepository _settings;
  final Directory _ytDir;
  final int _concurrency;
  final Future<void> Function(String trackId, YtDownload d) _onDownloaded;
  final Future<void> Function(String trackId) _onUnavailable;
  final DownloadNotifier _notifier;
  final bool _wifiOnlyFallback;
  final DateTime Function() _now;

  static const _firstBackoff = Duration(seconds: 30);
  static const _maxBackoff = Duration(minutes: 10);

  final _snapshots = StreamController<DownloadSnapshot>.broadcast();
  DownloadSnapshot _current = const DownloadSnapshot();
  final List<StreamSubscription<Object?>> _subs = [];

  /// Running downloads in start order.
  final Map<String, _Job> _jobs = {};
  final Map<String, TrackProgress> _progress = {};
  final Map<String, _Stop> _stopping = {};

  /// Queued rows, as last seen (plus rows this service just requeued).
  Set<String> _queuedIds = {};

  bool _started = false;
  bool _disposed = false;
  bool _pumping = false;
  bool _pumpAgain = false;

  NetworkKind _networkKind = NetworkKind.wifi;
  bool _wifiOnly = false;
  bool _offline = false;
  bool _diskFull = false;
  DateTime? _throttledUntil;
  DownloadPauseReason _throttleReason = DownloadPauseReason.throttled;
  int _backoffStep = 0;
  Timer? _backoff;
  bool _extractorFailing = false;
  bool _userPaused = false;

  bool _inRun = false;
  bool _checkingEnd = false;
  int _completed = 0;
  int _failed = 0;

  DownloadSnapshot get current => _current;

  /// The current snapshot, then every change.
  Stream<DownloadSnapshot> get snapshots => Stream<DownloadSnapshot>.multi((c) {
    final sub = _snapshots.stream.listen(
      c.addSync,
      onError: c.addErrorSync,
      onDone: c.closeSync,
    );
    c.addSync(_current);
    c.onCancel = sub.cancel;
  });

  // --- lifecycle -----------------------------------------------------------

  /// Puts rows left by a crash back in order, then starts downloading.
  Future<void> start() async {
    if (_started || _disposed) return;
    try {
      _networkKind = await _network.current();
      _offline = _networkKind == NetworkKind.offline;
      _wifiOnly = await _settings.getBool(
        kWifiOnly,
        fallback: _wifiOnlyFallback,
      );
      await _repo.resetInterrupted();
      await _repo.reconcileMissing();
      await _repo.dropUnwanted();
    } catch (e, s) {
      AppLog.e('Download queue start-up failed', e, s);
    }
    if (_disposed) return;
    _started = true;
    _subs
      ..add(_network.changes.listen(_onNetwork, onError: _logError))
      ..add(
        _settings
            .watchBool(kWifiOnly, fallback: _wifiOnlyFallback)
            .listen(_onWifiOnly, onError: _logError),
      )
      ..add(
        _repo.watchEnabledPlaylists().skip(1).listen((_) async {
          try {
            await _repo.dropUnwanted();
          } catch (e, s) {
            _logError(e, s);
          }
          await cancelUnwanted();
          kick();
        }, onError: _logError),
      )
      ..add(_repo.watchYtRows().listen(_onRows, onError: _logError));
    _update();
    kick();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _backoff?.cancel();
    _backoff = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    // Rows stay `downloading`; the next start() queues them again.
    for (final j in _jobs.values) {
      if (j.started && !j.finished) _cancel(j);
    }
    unawaited(_snapshots.close());
  }

  // --- public actions ------------------------------------------------------

  /// Fills free slots with the oldest queued rows.
  void kick() => unawaited(_pump());

  /// Cancels running downloads whose rows were removed; their partial files
  /// are deleted when the run ends.
  Future<void> cancelUnwanted() async {
    final running = [
      for (final j in _jobs.values)
        if (!j.finished) j,
    ];
    if (running.isEmpty) return;
    final Set<String> ids;
    try {
      ids = await _repo.rowIds([for (final j in running) j.trackId]);
    } catch (e, s) {
      _logError(e, s);
      return;
    }
    // Only the jobs that were read: one reserved meanwhile has its row.
    for (final j in running) {
      if (identical(_jobs[j.trackId], j) && !ids.contains(j.trackId)) {
        _stop(j, _Stop.unwanted);
      }
    }
  }

  /// Clears a disk-full or lost-network pause and ends a throttling wait now.
  Future<void> resume() async {
    if (_disposed) return;
    try {
      _networkKind = await _network.current();
    } catch (e, s) {
      _logError(e, s);
    }
    _offline = _networkKind == NetworkKind.offline;
    _diskFull = false;
    _clearThrottle();
    _update();
    kick();
  }

  /// The user's pause, held in memory only: no new download starts until
  /// [resumeByUser]; running ones finish. [resume] does not clear it.
  void pauseByUser() {
    if (_disposed || _userPaused) return;
    _userPaused = true;
    _update();
  }

  void resumeByUser() {
    if (_disposed || !_userPaused) return;
    _userPaused = false;
    _update();
    kick();
  }

  // --- events --------------------------------------------------------------

  void _onNetwork(NetworkKind k) {
    _networkKind = k;
    _offline = k == NetworkKind.offline;
    _update();
    kick();
  }

  void _onWifiOnly(bool v) {
    _wifiOnly = v;
    _update();
    kick();
  }

  void _onRows(List<LocalFile> rows) {
    _queuedIds = {
      for (final r in rows)
        if (r.state == 'queued') r.trackId,
    };
    final ids = {for (final r in rows) r.trackId};
    if (_jobs.values.any((j) => !j.finished && !ids.contains(j.trackId))) {
      // The emission may be stale; cancelUnwanted reads again.
      unawaited(cancelUnwanted());
    }
    _update();
    kick();
  }

  // --- the pump ------------------------------------------------------------

  DownloadPause? _pause() {
    if (_offline) return const DownloadPause(DownloadPauseReason.offline);
    if (_wifiOnly && _networkKind == NetworkKind.mobile) {
      return const DownloadPause(DownloadPauseReason.wifiOnly);
    }
    if (_diskFull) return const DownloadPause(DownloadPauseReason.diskFull);
    final until = _throttledUntil;
    if (until != null) {
      return DownloadPause(_throttleReason, resumesAt: until);
    }
    return null;
  }

  Future<void> _pump() async {
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        await _fill();
      } while (_pumpAgain && !_disposed);
    } catch (e, s) {
      // Logged and dropped: the next event pumps again.
      _logError(e, s);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _fill() async {
    while (_started && !_disposed && !_userPaused && _pause() == null) {
      // Starts the run (and zeroes its counts) before any job is counted.
      _update();
      final free = _concurrency - _jobs.length;
      if (free <= 0) return;
      final next = [
        for (final r in await _repo.nextQueued(_concurrency + _jobs.length))
          if (!_jobs.containsKey(r.trackId)) r,
      ].take(free).toList();
      if (next.isEmpty) return;
      for (final r in next) {
        if (_disposed || _userPaused || _pause() != null) return;
        await _startJob(r.trackId);
      }
    }
  }

  Future<void> _startJob(String trackId) async {
    final track = await _repo.ytTrack(trackId);
    final videoId = track?.ytVideoId;
    if (track == null || videoId == null || track.unavailable) {
      // Never retried in a loop: it waits for the user's Retry.
      if (await _repo.markFailed(
        trackId,
        ytErrorUserMessage(ytFailure(YtErrorKind.notFound, trackId)),
      )) {
        _failed++;
      }
      _update();
      return;
    }
    // Reserved before the row moves, so a cancel can find it.
    final job = _jobs[trackId] = _Job(trackId, videoId, track.title);
    _progress[trackId] = const TrackProgress(0, null);
    bool marked;
    try {
      marked = await _repo.markDownloading(trackId);
    } catch (_) {
      _release(job);
      _update();
      rethrow;
    }
    if (!marked || _disposed) {
      _release(job);
      _update();
      return;
    }
    _update();
    unawaited(_run(job));
  }

  Future<void> _run(_Job job) async {
    Result<YtDownload> r;
    if (_stopping.containsKey(job.trackId)) {
      r = Err(ytFailure(YtErrorKind.unknown, 'cancelled before start'));
    } else {
      try {
        final f = _client.download(
          job.videoId,
          _ytDir,
          processId: job.processId,
          onProgress: (d, t) => _onProgress(job, d, t),
        );
        job.started = true;
        // A cancel sent before the process existed may have been lost.
        _recancel(job);
        r = await f;
      } catch (e) {
        r = Err(ytFailure(YtErrorKind.unknown, '$e', cause: e));
      }
    }
    job.finished = true;
    if (_disposed) return;
    final stop = _stopping[job.trackId];
    try {
      await _finish(job, r, stop);
    } catch (e, s) {
      AppLog.w('Download of ${job.trackId} could not be recorded', e, s);
    } finally {
      _release(job);
    }
    if (_disposed) return;
    _update();
    kick();
  }

  void _onProgress(_Job job, int downloaded, int? total) {
    _recancel(job);
    if (_disposed || _stopping.containsKey(job.trackId)) return;
    _progress[job.trackId] = TrackProgress(downloaded, total);
    _update();
  }

  void _release(_Job job) {
    if (identical(_jobs[job.trackId], job)) {
      _jobs.remove(job.trackId);
      _progress.remove(job.trackId);
      _stopping.remove(job.trackId);
    }
  }

  Future<void> _finish(_Job job, Result<YtDownload> r, _Stop? stop) async {
    final id = job.trackId;
    if (stop == _Stop.unwanted) {
      if (r case Ok(:final value)) _deleteFile(value.path);
      _deleteParts(job.videoId);
      return;
    }
    switch (r) {
      case Ok(:final value):
        if (!await _repo.markDone(id, value.path, value.bytes)) {
          // Removed while it ran: nothing tracks the file.
          _deleteFile(value.path);
          _deleteParts(job.videoId);
          return;
        }
        _completed++;
        _backoffStep = 0;
        _extractorFailing = false;
        try {
          await _onDownloaded(id, value);
        } catch (e, s) {
          AppLog.w('After-download update of $id failed', e, s);
        }
      case Err(:final failure):
        if (stop == _Stop.paused) {
          await _requeue(id);
          return;
        }
        await _failure(job, failure);
    }
  }

  Future<void> _failure(_Job job, Failure f) async {
    final id = job.trackId;
    final kind = ytErrorKindOf(f);
    switch (kind) {
      case YtErrorKind.notFound:
        try {
          await _onUnavailable(id);
        } catch (e, s) {
          AppLog.w('Marking $id unavailable failed', e, s);
        }
        await _repo.removeFiles([id], _ytDir);
        _deleteParts(job.videoId);
      case YtErrorKind.throttled:
        _throttle(DownloadPauseReason.throttled);
        await _requeue(id);
      case YtErrorKind.network:
        // Really offline: wait for the connection. Otherwise (a blip, a
        // stall) retry on the backoff, as no connectivity event may come.
        if (await _isOffline()) {
          _offline = true;
          _update();
        } else {
          _throttle(DownloadPauseReason.retrying);
        }
        await _requeue(id);
      case YtErrorKind.diskFull:
        _diskFull = true;
        _update();
        await _requeue(id);
      default:
        if (await _repo.markFailed(id, ytErrorUserMessage(f))) _failed++;
        if (kind == YtErrorKind.extractor ||
            kind == YtErrorKind.unknown ||
            kind == null) {
          _extractorFailing = true;
        }
    }
  }

  Future<void> _requeue(String id) async {
    // A row that is gone must not keep the run open.
    if (await _repo.requeue(id)) _queuedIds = {..._queuedIds, id};
  }

  Future<bool> _isOffline() async {
    try {
      _networkKind = await _network.current();
    } catch (e, s) {
      _logError(e, s);
    }
    return _networkKind == NetworkKind.offline;
  }

  // --- cancelling ----------------------------------------------------------

  void _stop(_Job job, _Stop reason) {
    if (job.finished) return;
    final was = _stopping[job.trackId];
    if (was == _Stop.unwanted) return;
    _stopping[job.trackId] = reason;
    if (was == null && job.started) _cancel(job);
  }

  void _recancel(_Job job) {
    if (job.recancelled || !_stopping.containsKey(job.trackId)) return;
    job.recancelled = true;
    _cancel(job);
  }

  void _cancel(_Job job) => unawaited(
    _client.cancel(job.processId).catchError((Object e, StackTrace s) {
      _logError(e, s);
    }),
  );

  // --- throttling ----------------------------------------------------------

  void _throttle(DownloadPauseReason reason) {
    if (_throttledUntil != null) return; // already waiting
    _throttleReason = reason;
    final delay = Duration(
      seconds: math.min(
        _firstBackoff.inSeconds << _backoffStep,
        _maxBackoff.inSeconds,
      ),
    );
    if (delay < _maxBackoff) _backoffStep++;
    _throttledUntil = _now().add(delay);
    _backoff?.cancel();
    _backoff = Timer(delay, () {
      _backoff = null;
      _throttledUntil = null;
      _update();
      kick();
    });
    _update();
  }

  void _clearThrottle() {
    _backoff?.cancel();
    _backoff = null;
    _throttledUntil = null;
  }

  // --- files ---------------------------------------------------------------

  void _deleteFile(String path) {
    if (!p.isWithin(_ytDir.path, path)) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException catch (e, s) {
      AppLog.w('Could not delete $path', e, s);
    }
  }

  /// Deletes `<videoId>.*.part` (and fragment parts) left by yt-dlp.
  void _deleteParts(String videoId) {
    try {
      for (final f in _ytDir.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (name.startsWith('$videoId.') &&
            (name.endsWith('.part') || name.contains('.part-'))) {
          _deleteFile(f.path);
        }
      }
    } on FileSystemException catch (e, s) {
      AppLog.w('Could not list ${_ytDir.path}', e, s);
    }
  }

  // --- snapshots -----------------------------------------------------------

  void _update() {
    if (_disposed) return;
    final pause = _pause();
    if (pause != null) {
      for (final j in _jobs.values.toList()) {
        _stop(j, _Stop.paused);
      }
    }
    final queued = _queuedIds.where((id) => !_jobs.containsKey(id)).length;
    final hasWork = _jobs.isNotEmpty || queued > 0;
    if (hasWork && !_inRun) {
      _inRun = true;
      _completed = 0;
      _failed = 0;
    } else if (!hasWork && _inRun) {
      unawaited(_checkRunEnd());
    }
    final snap = DownloadSnapshot(
      queued: queued,
      active: _jobs.length,
      completedThisRun: _completed,
      failedThisRun: _failed,
      totalThisRun: _completed + _failed + _jobs.length + queued,
      progress: Map.unmodifiable(_progress),
      pause: pause,
      userPaused: _userPaused,
      extractorFailing: _extractorFailing,
      currentTitle: _jobs.isEmpty ? null : _jobs.values.last.title,
    );
    if (snap == _current) return;
    _current = snap;
    _snapshots.add(snap);
    _notify(() => _notifier.update(snap));
  }

  /// Ends the run once a fresh read confirms nothing is queued (the cached
  /// ids can lag behind the database).
  Future<void> _checkRunEnd() async {
    if (_checkingEnd) return;
    _checkingEnd = true;
    try {
      final next = await _repo.nextQueued(1);
      if (_disposed || !_inRun || _jobs.isNotEmpty || next.isNotEmpty) return;
      _inRun = false;
      _clearThrottle();
      _update();
      final completed = _completed, failed = _failed;
      _notify(() => _notifier.finished(completed, failed));
    } catch (e, s) {
      _logError(e, s);
    } finally {
      _checkingEnd = false;
    }
  }

  void _notify(Future<void> Function() call) => unawaited(
    Future.sync(call).catchError((Object e, StackTrace s) {
      AppLog.w('Download notification failed', e, s);
    }),
  );

  static void _logError(Object e, StackTrace s) =>
      AppLog.w('Download queue error', e, s);
}
