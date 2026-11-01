import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/downloads/download_notifier.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/player/age_restricted_stream_source.dart';
import 'package:songies/youtube/js_runtime.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

import '../helpers/fake_network_status.dart';
import '../helpers/test_db.dart';

/// A yt-dlp runner whose runs the test finishes one by one.
///
/// A cancel ends the run with exit -1 (like a killed process, which the client
/// reports as an unknown error) unless [loseCancels] is set, as on desktop
/// when the cancel comes before the process exists.
class GateRunner implements YtDlpRunner {
  final List<String> started = [];
  final List<List<String>> calls = [];
  final List<String> cancelled = [];
  final Map<String, Completer<YtDlpRun>> _runs = {};
  final Map<String, void Function(String)?> _onLine = {};
  bool loseCancels = false;
  int maxRunning = 0;

  int get running => _runs.length;
  bool isRunning(String processId) => _runs.containsKey(processId);

  @override
  Future<YtDlpRun> run(
    List<String> args, {
    Duration? timeout,
    void Function(String line)? onLine,
    String? processId,
  }) {
    final id = processId!;
    started.add(id);
    calls.add(List.of(args));
    final c = _runs[id] = Completer<YtDlpRun>();
    _onLine[id] = onLine;
    if (_runs.length > maxRunning) maxRunning = _runs.length;
    return c.future;
  }

  void line(String processId, String l) => _onLine[processId]?.call(l);

  void finish(String processId, YtDlpRun r) {
    final c = _runs.remove(processId)!;
    for (final l in const LineSplitter().convert(r.stdout)) {
      _onLine[processId]?.call(l);
    }
    c.complete(r);
  }

  @override
  Future<void> cancel(String processId) async {
    cancelled.add(processId);
    if (loseCancels) return;
    _runs.remove(processId)?.complete(const YtDlpRun(-1, '', 'killed'));
  }

  @override
  Future<String?> version() async => '2026.10.21';

  @override
  Future<Result<void>> update() async => const Ok(null);
}

/// A repository whose [rowIds] can be held open by the test.
class GatedRepository extends DownloadRepository {
  GatedRepository(super.db);

  Completer<void>? rowIdsGate;

  @override
  Future<Set<String>> rowIds(Iterable<String> trackIds) async {
    final ids = trackIds.toList();
    final gate = rowIdsGate;
    if (gate != null) await gate.future;
    return super.rowIds(ids);
  }
}

class RecordingNotifier implements DownloadNotifier {
  final List<DownloadSnapshot> updates = [];
  final List<(int, int)> finishes = [];

  @override
  Future<void> update(DownloadSnapshot s) async => updates.add(s);

  @override
  Future<void> finished(int completed, int failed) async =>
      finishes.add((completed, failed));
}

const _throttled =
    'ERROR: [youtube] abc: Unable to download webpage: HTTP Error 429: '
    'Too Many Requests';
const _private =
    'ERROR: [youtube] abc: Private video. Sign in if you are '
    'authorized';
const _extractor = 'ERROR: [youtube] abc: Unable to extract player response';
const _noSpace =
    'ERROR: unable to write data: [Errno 28] No space left on '
    'device';

/// One test's world: an in-memory db, a gate runner, a fake network and the
/// service, all on [async]'s fake clock.
class Env {
  Env(this.async, {this.concurrency = 3, bool wifiOnly = false})
    : db = testDb(),
      tmp = Directory.systemTemp.createTempSync('dl_service_test') {
    ytDir = Directory('${tmp.path}/yt')..createSync();
    repo = GatedRepository(db);
    settings = SettingsRepository(db);
    wait(settings.setBool(kWifiOnly, wifiOnly));
  }

  final FakeAsync async;
  final int concurrency;
  final AppDatabase db;
  final Directory tmp;
  late final Directory ytDir;
  late final GatedRepository repo;
  late final SettingsRepository settings;
  final runner = GateRunner();
  final network = FakeNetworkStatus();
  final notifier = RecordingNotifier();
  final unavailable = <String>[];
  final downloaded = <String, YtDownload>{};
  final base = DateTime(2026, 10, 23, 12);

  /// Signed-in retries of age-restricted songs; none when null.
  AgeRestrictedAuth? ageAuth;
  DownloadService? _service;
  int _seq = 0;

  DownloadService get service => _service ??= DownloadService(
    repo: repo,
    client: YtDlpClient(runner),
    network: network,
    settings: settings,
    ytDir: ytDir,
    concurrency: concurrency,
    onDownloaded: (id, d) async => downloaded[id] = d,
    onUnavailable: (id) async => unavailable.add(id),
    notifier: notifier,
    wifiOnlyFallback: false,
    now: () => base.add(async.elapsed),
    ageAuth: ageAuth,
  );

  DownloadSnapshot get snap => service.current;

  T wait<T>(Future<T> f) {
    late T value;
    var done = false;
    Object? error;
    f.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = '$e\n$s';
      },
    );
    settle();
    expect(error, isNull);
    expect(done, isTrue, reason: 'future did not complete');
    return value;
  }

  void settle() {
    for (var i = 0; i < 5; i++) {
      async.elapse(Duration.zero);
    }
  }

  void elapse(Duration d) {
    async.elapse(d);
    settle();
  }

  Future<void> track(String id) => db
      .into(db.tracks)
      .insert(
        trackRow(id: id, source: 'yt', ytVideoId: 'v$id', title: 'Song $id'),
      );

  /// YouTube tracks [ids], in an enabled playlist [playlist], queued in
  /// order.
  void queued(List<String> ids, {String playlist = 'A'}) {
    inPlaylist(ids, playlist: playlist);
    wait(repo.setPlaylistDownload(playlist, true));
  }

  /// New YouTube tracks [ids] added to [playlist].
  void inPlaylist(List<String> ids, {String playlist = 'A'}) {
    for (final id in ids) {
      wait(track(id));
      _seq++;
      wait(
        db
            .into(db.playlistEntries)
            .insert(
              PlaylistEntriesCompanion.insert(
                id: 'e$_seq',
                clock: 'c',
                originDevice: 'dev',
                localSeq: _seq,
                playlistId: playlist,
                trackId: id,
                position: 'a$_seq',
                addedAt: DateTime(2026),
              ),
            ),
      );
    }
  }

  LocalFile? row(String id) => wait(
    (db.select(
      db.localFiles,
    )..where((f) => f.trackId.equals(id))).getSingleOrNull(),
  );

  String pid(String id) => 'dl-$id';

  File file(String id) => File('${ytDir.path}/v$id.webm');
  File part(String id) => File('${ytDir.path}/v$id.webm.part');

  /// Finishes [id]'s run with a downloaded file.
  void succeed(String id) {
    file(id).writeAsBytesSync(List.filled(100, 1));
    final done = jsonEncode({
      'filepath': file(id).path,
      'title': 'T $id',
      'artist': 'A',
      'track': 'NA',
      'album': 'NA',
      'duration': 200,
    });
    runner.finish(pid(id), YtDlpRun(0, 'songies-done $done\n', ''));
    settle();
  }

  void fail(String id, String stderr) {
    runner.finish(pid(id), YtDlpRun(1, '', stderr));
    settle();
  }

  void dispose() {
    wait(service.dispose());
    wait(db.close());
    settle();
    tmp.deleteSync(recursive: true);
  }
}

void run(
  String name,
  void Function(Env e) body, {
  int concurrency = 3,
  bool wifiOnly = false,
}) {
  test(name, () {
    fakeAsync((async) {
      final e = Env(async, concurrency: concurrency, wifiOnly: wifiOnly);
      try {
        body(e);
      } finally {
        e.dispose();
      }
    });
  });
}

void main() {
  run('desktop runs 3 at once, FIFO, until all 5 are done', (e) {
    e.queued(['y1', 'y2', 'y3', 'y4', 'y5']);
    e.wait(e.service.start());
    expect(e.runner.started, ['dl-y1', 'dl-y2', 'dl-y3']);
    expect(e.snap.active, 3);
    expect(e.snap.queued, 2);
    expect(e.snap.totalThisRun, 5);
    expect(e.row('y1')!.state, 'downloading');

    e.succeed('y2');
    expect(e.runner.started.last, 'dl-y4');
    e.succeed('y1');
    expect(e.runner.started.last, 'dl-y5');
    for (final id in ['y3', 'y4', 'y5']) {
      e.succeed(id);
    }

    expect(e.runner.maxRunning, 3);
    for (final id in ['y1', 'y2', 'y3', 'y4', 'y5']) {
      final r = e.row(id)!;
      expect(r.state, 'done');
      expect(r.path, e.file(id).path);
      expect(r.bytes, 100);
    }
    expect(e.downloaded.keys, unorderedEquals(['y1', 'y2', 'y3', 'y4', 'y5']));
    expect(e.downloaded['y1']!.title, 'T y1');
    expect(e.snap.completedThisRun, 5);
    expect(e.snap.totalThisRun, 5);
    expect(e.snap.active, 0);
    expect(e.snap.queued, 0);
    expect(e.notifier.finishes, [(5, 0)]);
    expect(e.notifier.updates, isNotEmpty);
  });

  run('a song added to an enabled playlist downloads', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.succeed('y1');
    e.inPlaylist(['y2']);
    e.settle();
    expect(e.runner.started, ['dl-y1', 'dl-y2']);
    e.succeed('y2');
    expect(e.row('y2')!.state, 'done');
  });

  run('a song added to a playlist that is not downloading stays put', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.succeed('y1');
    e.inPlaylist(['y2'], playlist: 'B');
    e.settle();
    expect(e.runner.started, ['dl-y1']);
    expect(e.row('y2'), null);
  });

  run('Android runs 2 at once', concurrency: 2, (e) {
    e.queued(['y1', 'y2', 'y3']);
    e.wait(e.service.start());
    expect(e.runner.started, ['dl-y1', 'dl-y2']);
    e.succeed('y1');
    expect(e.runner.started, ['dl-y1', 'dl-y2', 'dl-y3']);
    expect(e.runner.maxRunning, 2);
  });

  run('progress lines raise the fraction; the title is the latest one', (e) {
    e.queued(['y1', 'y2']);
    final seen = <DownloadSnapshot>[];
    final sub = e.service.snapshots.listen(seen.add);
    e.settle();
    expect(seen, hasLength(1), reason: 'a listener gets the current value');
    e.wait(e.service.start());
    expect(e.snap.currentTitle, 'Song y2');
    expect(e.snap.progress['y1']!.fraction, isNull);

    e.runner.line('dl-y1', 'songies-progress 100 1000 NA');
    e.settle();
    expect(e.snap.progress['y1']!.fraction, closeTo(0.1, 1e-9));
    e.runner.line('dl-y1', 'songies-progress 500 NA 1000');
    e.settle();
    expect(e.snap.progress['y1']!.fraction, closeTo(0.5, 1e-9));
    expect(seen.last.progress['y1']!.downloaded, 500);

    e.succeed('y2');
    expect(e.snap.currentTitle, 'Song y1');
    expect(e.snap.progress.containsKey('y2'), isFalse);
    sub.cancel();
  });

  run('429 pauses every slot with an exponential backoff', (e) {
    e.queued(['y1', 'y2']);
    e.wait(e.service.start());
    e.fail('y1', _throttled);

    expect(e.snap.pause?.reason, DownloadPauseReason.throttled);
    expect(e.snap.pause?.resumesAt, e.base.add(const Duration(seconds: 30)));
    expect(e.runner.cancelled, ['dl-y2']);
    expect(e.row('y1')!.state, 'queued');
    expect(e.row('y2')!.state, 'queued');
    expect(e.snap.failedThisRun, 0);
    expect(e.snap.extractorFailing, isFalse);

    e.elapse(const Duration(seconds: 29));
    expect(e.runner.running, 0);
    e.elapse(const Duration(seconds: 1));
    expect(e.snap.pause, isNull);
    expect(e.runner.running, 2);

    // Each further 429 doubles the wait, up to 10 min.
    for (final s in [60, 120, 240, 480, 600, 600]) {
      final at = e.base.add(e.async.elapsed);
      e.fail('y1', _throttled);
      expect(e.snap.pause?.resumesAt, at.add(Duration(seconds: s)));
      e.elapse(Duration(seconds: s));
      expect(e.runner.running, 2);
    }

    // A success resets it.
    e.succeed('y2');
    final at = e.base.add(e.async.elapsed);
    e.fail('y1', _throttled);
    expect(e.snap.pause?.resumesAt, at.add(const Duration(seconds: 30)));
    e.elapse(const Duration(seconds: 30));
    e.succeed('y1');
    expect(e.row('y1')!.state, 'done');
    expect(e.async.pendingTimers, isEmpty, reason: 'no timer when idle');
  });

  run(
    'mobile with Wi-Fi only cancels, requeues and resumes on Wi-Fi',
    wifiOnly: true,
    (e) {
      e.queued(['y1', 'y2']);
      e.wait(e.service.start());
      expect(e.runner.running, 2);

      e.network.set(NetworkKind.mobile);
      e.settle();
      expect(e.runner.cancelled, unorderedEquals(['dl-y1', 'dl-y2']));
      expect(e.row('y1')!.state, 'queued');
      expect(e.row('y2')!.state, 'queued');
      expect(e.snap.pause?.reason, DownloadPauseReason.wifiOnly);
      expect(e.snap.failedThisRun, 0);
      expect(e.snap.extractorFailing, isFalse);
      expect(e.notifier.finishes, isEmpty, reason: 'the run goes on');

      e.network.set(NetworkKind.wifi);
      e.settle();
      expect(e.snap.pause, isNull);
      expect(e.runner.running, 2);

      // Back on mobile, then the setting is turned off.
      e.network.set(NetworkKind.mobile);
      e.settle();
      expect(e.runner.running, 0);
      e.wait(e.settings.setBool(kWifiOnly, false));
      e.settle();
      expect(e.snap.pause, isNull);
      expect(e.runner.running, 2);
    },
  );

  run('mobile without Wi-Fi only keeps downloading', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.network.set(NetworkKind.mobile);
    e.settle();
    expect(e.runner.cancelled, isEmpty);
    expect(e.snap.pause, isNull);
  });

  run('offline mid-download pauses; back online resumes', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.network.set(NetworkKind.offline);
    e.settle();
    expect(e.snap.pause?.reason, DownloadPauseReason.offline);
    expect(e.row('y1')!.state, 'queued');
    expect(e.runner.running, 0);

    e.network.set(NetworkKind.other);
    e.settle();
    expect(e.snap.pause, isNull);
    expect(e.runner.started, ['dl-y1', 'dl-y1']);
  });

  const networkError =
      'ERROR: [youtube] abc: Unable to download webpage: '
      '<urlopen error [Errno -3] getaddrinfo failed>';

  run('a network error on a working network retries with the backoff', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.fail('y1', networkError);
    expect(e.snap.pause?.reason, DownloadPauseReason.retrying);
    expect(e.snap.pause?.resumesAt, e.base.add(const Duration(seconds: 30)));
    expect(e.row('y1')!.state, 'queued');
    e.elapse(const Duration(seconds: 29));
    expect(e.runner.running, 0);
    e.elapse(const Duration(seconds: 1));
    expect(e.runner.started, ['dl-y1', 'dl-y1'], reason: 'no network event');

    final at = e.base.add(e.async.elapsed);
    e.fail('y1', networkError);
    expect(e.snap.pause?.resumesAt, at.add(const Duration(seconds: 60)));
  });

  run('a network error while really offline pauses as offline', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.network.kind = NetworkKind.offline; // no event yet
    e.fail('y1', networkError);
    expect(e.snap.pause, const DownloadPause(DownloadPauseReason.offline));
    expect(e.row('y1')!.state, 'queued');
    e.elapse(const Duration(minutes: 30));
    expect(e.runner.running, 0);
    e.network.set(NetworkKind.wifi);
    e.settle();
    expect(e.runner.running, 1);
  });

  run('a full disk pauses until resume()', (e) {
    e.queued(['y1', 'y2']);
    e.wait(e.service.start());
    e.fail('y1', _noSpace);
    expect(e.snap.pause?.reason, DownloadPauseReason.diskFull);
    expect(e.row('y1')!.state, 'queued');
    expect(e.row('y2')!.state, 'queued');
    e.elapse(const Duration(hours: 1));
    expect(e.runner.running, 0);

    e.wait(e.service.resume());
    expect(e.snap.pause, isNull);
    expect(e.runner.running, 2);
  });

  run('notFound marks the track unavailable and moves on', concurrency: 1, (e) {
    e.queued(['y1', 'y2']);
    e.wait(e.service.start());
    e.fail('y1', _private);
    expect(e.unavailable, ['y1']);
    expect(e.row('y1'), isNull);
    expect(e.runner.started, ['dl-y1', 'dl-y2']);
    expect(e.snap.pause, isNull);
  });

  run(
    'an age-restricted song fails its row, never unavailable',
    concurrency: 1,
    (e) {
      e.queued(['y1', 'y2']);
      e.wait(e.service.start());
      e.fail('y1', 'ERROR: [youtube] abc: Sign in to confirm your age');
      expect(e.unavailable, isEmpty);
      final r = e.row('y1')!;
      expect(r.state, 'failed');
      expect(
        r.error,
        ytErrorUserMessage(ytFailure(YtErrorKind.ageRestricted, '')),
      );
      expect(e.snap.extractorFailing, isFalse);
      expect(e.runner.started, ['dl-y1', 'dl-y2']);
    },
  );

  run(
    'signed in, an age-restricted song is retried with the cookies',
    concurrency: 1,
    (e) {
      e.ageAuth = AgeRestrictedAuth(
        () async => YtSession({'SID': 'sid-value'}),
        _NodeFinder(),
      );
      e.queued(['y1']);
      e.wait(e.service.start());
      e.fail('y1', 'ERROR: [youtube] abc: Sign in to confirm your age');
      expect(e.runner.calls.last, contains('--cookies'));
      e.succeed('y1');
      expect(e.unavailable, isEmpty);
      expect(e.downloaded.keys, ['y1']);
    },
  );

  run(
    'an extractor error fails the row until a success clears the flag',
    concurrency: 1,
    (e) {
      e.queued(['y1', 'y2']);
      e.wait(e.service.start());
      e.fail('y1', _extractor);
      final r = e.row('y1')!;
      expect(r.state, 'failed');
      expect(r.error, ytErrorUserMessage(ytFailure(YtErrorKind.extractor, '')));
      expect(e.snap.extractorFailing, isTrue);
      expect(e.snap.failedThisRun, 1);

      e.succeed('y2');
      expect(e.snap.extractorFailing, isFalse);
      expect(e.notifier.finishes, [(1, 1)]);
    },
  );

  run('disabling the playlist cancels and never marks the row done', (e) {
    e.queued(['y1', 'y2']);
    e.wait(e.service.start());
    e.part('y1').writeAsBytesSync([1, 2, 3]);
    e.runner.loseCancels = true; // the runner still reports success below

    e.wait(e.repo.setPlaylistDownload('A', false));
    e.settle();
    expect(e.runner.cancelled, unorderedEquals(['dl-y1', 'dl-y2']));
    e.succeed('y1');
    e.fail('y2', 'killed');

    expect(e.row('y1'), isNull);
    expect(e.row('y2'), isNull);
    expect(e.part('y1').existsSync(), isFalse);
    expect(e.file('y1').existsSync(), isFalse);
    expect(e.downloaded, isEmpty);
    expect(e.snap.failedThisRun, 0);
    expect(e.snap.extractorFailing, isFalse);
  });

  run('removing a single download cancels it and deletes its .part', (e) {
    e.wait(e.track('y1'));
    expect(e.wait(e.repo.downloadTrack('y1')), isTrue);
    e.wait(e.service.start());
    e.part('y1').writeAsBytesSync([1]);
    e.wait(e.repo.removeTrackDownload('y1', e.ytDir));
    e.settle();
    expect(e.runner.cancelled, ['dl-y1']);
    expect(e.part('y1').existsSync(), isFalse);
    expect(e.row('y1'), isNull);
  });

  run('a row removed as its run finishes: the file is deleted', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.runner.loseCancels = true;
    // Removed and finished at once: markDone finds no row.
    final removed = e.db.delete(e.db.localFiles).go();
    e.succeed('y1');
    e.wait(removed);
    expect(e.file('y1').existsSync(), isFalse);
    expect(e.row('y1'), isNull);
  });

  run(
    'a job started while cancelUnwanted reads is not cancelled',
    concurrency: 1,
    (e) {
      e.queued(['y1', 'y2']);
      e.wait(e.service.start());
      e.repo.rowIdsGate = Completer<void>();
      final cancelling = e.service.cancelUnwanted();
      e.succeed('y1'); // y2 is reserved and started meanwhile
      expect(e.runner.started, ['dl-y1', 'dl-y2']);
      e.repo.rowIdsGate!.complete();
      e.wait(cancelling);
      expect(e.runner.cancelled, isEmpty);
      e.succeed('y2');
      expect(e.row('y2')!.state, 'done');
    },
  );

  run('a requeue of a row that is gone still ends the run', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    // The row goes; the watcher sees it but its cancel is held up, so the
    // 429 that follows is handled normally and its requeue finds no row.
    e.repo.rowIdsGate = Completer<void>();
    e.wait(e.db.delete(e.db.localFiles).go());
    e.fail('y1', _throttled);
    e.repo.rowIdsGate!.complete();
    e.settle();
    expect(e.row('y1'), isNull);
    expect(e.snap.queued, 0);
    expect(e.snap.active, 0);
    expect(e.notifier.finishes, [(0, 0)]);
    expect(e.async.pendingTimers, isEmpty);
  });

  run('start() runs a row left downloading by a crash again', (e) {
    e.queued(['y1']);
    e.wait(e.repo.markDownloading('y1'));
    e.wait(e.service.start());
    expect(e.runner.started, ['dl-y1']);
    e.succeed('y1');
    expect(e.row('y1')!.state, 'done');
  });

  run('songs added by a sync to an enabled playlist are downloaded', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.succeed('y1');
    e.inPlaylist(['y2', 'y3']);
    e.settle();
    // The sync hook's own call then finds them already queued.
    expect(e.wait(e.repo.queueAdded('A', ['y2', 'y3'])), 0);
    expect(e.runner.started, ['dl-y1', 'dl-y2', 'dl-y3']);
  });

  run('dispose cancels running downloads and leaves rows for next start', (e) {
    e.queued(['y1']);
    e.wait(e.service.start());
    e.wait(e.service.dispose());
    expect(e.runner.cancelled, ['dl-y1']);
    expect(e.row('y1')!.state, 'downloading');
    expect(e.network.hasListeners, isFalse);
  });

  run('a user pause lets running downloads finish but starts no new ones', (e) {
    e.queued(['y1', 'y2', 'y3', 'y4']);
    e.wait(e.service.start());
    expect(e.runner.started, ['dl-y1', 'dl-y2', 'dl-y3']);

    e.service.pauseByUser();
    e.settle();
    expect(e.snap.userPaused, isTrue);
    expect(e.snap.pause, const DownloadPause(DownloadPauseReason.user));
    expect(e.runner.cancelled, isEmpty, reason: 'running ones finish');

    e.succeed('y1');
    expect(e.row('y1')!.state, 'done');
    expect(e.runner.started, hasLength(3), reason: 'no new slot while paused');
    expect(e.snap.queued, 1);

    e.service.resumeByUser();
    e.settle();
    expect(e.snap.userPaused, isFalse);
    expect(e.snap.pause, isNull);
    expect(e.runner.started.last, 'dl-y4');
  });

  run('another pause takes precedence over the user pause', (e) {
    e.queued(['y1']);
    e.service.pauseByUser();
    e.wait(e.service.start());
    expect(e.snap.pause?.reason, DownloadPauseReason.user);

    e.network.set(NetworkKind.offline);
    e.settle();
    expect(e.snap.pause?.reason, DownloadPauseReason.offline);
    expect(e.snap.userPaused, isTrue);

    e.network.set(NetworkKind.wifi);
    e.settle();
    expect(e.snap.pause?.reason, DownloadPauseReason.user);
    expect(e.runner.started, isEmpty);
  });

  run('a user pause outlasts other pauses and does not end the run', (e) {
    e.queued(['y1']);
    e.service.pauseByUser();
    e.wait(e.service.start());
    expect(e.runner.started, isEmpty);
    expect(e.snap.queued, 1);
    expect(e.snap.userPaused, isTrue);

    e.wait(e.service.resume());
    expect(e.runner.started, isEmpty, reason: 'resume() keeps a user pause');
    expect(e.notifier.finishes, isEmpty);

    e.service.resumeByUser();
    e.settle();
    expect(e.runner.started, ['dl-y1']);
  });
}

class _NodeFinder implements JsRuntimeFinder {
  @override
  Future<JsRuntime?> find() async =>
      const JsRuntime(JsRuntimeKind.systemNode, ['--js-runtimes', 'node']);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
