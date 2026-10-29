import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/downloads/download_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late DownloadRepository repo;
  late Directory tmp;
  late Directory ytDir;
  var seq = 0;

  setUp(() async {
    db = testDb();
    repo = DownloadRepository(db);
    tmp = await Directory.systemTemp.createTemp('dl_repo_test');
    ytDir = Directory('${tmp.path}/yt')..createSync();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> track(
    String id, {
    String source = 'yt',
    bool unavailable = false,
  }) => db
      .into(db.tracks)
      .insert(
        trackRow(
          id: id,
          source: source,
          ytVideoId: source == 'yt' ? 'v$id' : null,
          fileHash: source == 'yt' ? null : 'h$id',
        ).copyWith(unavailable: Value(unavailable)),
      );

  Future<void> entry(
    String playlist,
    String trackId, {
    String status = 'active',
    bool deleted = false,
  }) {
    seq++;
    return db
        .into(db.playlistEntries)
        .insert(
          PlaylistEntriesCompanion.insert(
            id: 'e$seq',
            clock: 'c',
            originDevice: 'dev',
            localSeq: seq,
            playlistId: playlist,
            trackId: trackId,
            position: 'a$seq',
            addedAt: DateTime(2026),
            status: Value(status),
            deleted: Value(deleted),
          ),
        );
  }

  Future<LocalFile?> row(String id) => (db.select(
    db.localFiles,
  )..where((f) => f.trackId.equals(id))).getSingleOrNull();

  Future<void> setRow(
    String id,
    String state, {
    String path = '',
    int bytes = 0,
    bool manual = false,
    int? requestedAt,
  }) => db
      .into(db.localFiles)
      .insertOnConflictUpdate(
        LocalFilesCompanion.insert(
          trackId: id,
          path: path,
          state: state,
          bytes: bytes,
          mtimeMs: 0,
          requestedAt: Value(requestedAt),
          manual: Value(manual),
        ),
      );

  Future<void> threeYtOneLocal(String playlist) async {
    await track('y1');
    await track('y2');
    await track('y3', unavailable: true);
    await track('l1', source: 'local');
    for (final id in ['y1', 'y2', 'y3', 'l1']) {
      await entry(playlist, id);
    }
  }

  test('enabling queues available yt tracks once', () async {
    await threeYtOneLocal('A');
    expect(await repo.setPlaylistDownload('A', true), 2);
    final rows = await db.select(db.localFiles).get();
    expect(rows.map((r) => r.trackId).toSet(), {'y1', 'y2'});
    expect(rows.every((r) => r.state == 'queued' && r.path == ''), isTrue);
    expect(rows.every((r) => r.requestedAt != null && !r.manual), isTrue);
    expect(await repo.setPlaylistDownload('A', true), 0);
  });

  test(
    'removed or deleted entries are not queued; failed ones are retried',
    () async {
      await track('y1');
      await track('y2');
      await track('y3');
      await entry('A', 'y1');
      await entry('A', 'y2', status: 'removed');
      await entry('A', 'y3', deleted: true);
      await setRow('y1', 'failed');
      expect(await repo.setPlaylistDownload('A', true), 1);
      expect((await row('y1'))!.state, 'queued');
      expect(await row('y2'), isNull);
      expect(await row('y3'), isNull);
    },
  );

  test('disabling only clears the preference', () async {
    await threeYtOneLocal('A');
    await repo.setPlaylistDownload('A', true);
    expect(await repo.setPlaylistDownload('A', false), 0);
    expect(await db.select(db.localFiles).get(), hasLength(2));
    expect(await repo.watchEnabledPlaylists().first, isEmpty);
  });

  test(
    'a track in two enabled playlists has one row and is exclusive to neither',
    () async {
      await track('y1');
      await entry('A', 'y1');
      await entry('B', 'y1');
      await repo.setPlaylistDownload('A', true);
      await repo.setPlaylistDownload('B', true);
      expect(await db.select(db.localFiles).get(), hasLength(1));
      await setRow('y1', 'done', path: '${ytDir.path}/v.opus', bytes: 5);
      expect(await repo.exclusiveFiles('A'), isEmpty);
      await repo.setPlaylistDownload('B', false);
      expect(await repo.exclusiveFiles('A'), ['y1']);
    },
  );

  test('a manual row is never exclusive', () async {
    await track('y1');
    await entry('A', 'y1');
    await repo.setPlaylistDownload('A', true);
    await setRow(
      'y1',
      'done',
      path: '${ytDir.path}/v.opus',
      bytes: 5,
      manual: true,
    );
    expect(await repo.exclusiveFiles('A'), isEmpty);
  });

  test('nextQueued is FIFO by requestedAt and limited', () async {
    for (final id in ['y1', 'y2', 'y3']) {
      await track(id);
    }
    await setRow('y1', 'queued', requestedAt: 30);
    await setRow('y2', 'queued', requestedAt: 10);
    await setRow('y3', 'queued', requestedAt: 20);
    expect([for (final r in await repo.nextQueued(2)) r.trackId], ['y2', 'y3']);
  });

  test('requests made together keep their order', () async {
    for (final id in ['y1', 'y2', 'y3']) {
      await track(id);
      await entry('A', id);
    }
    await repo.setPlaylistDownload('A', true);
    final times = [for (final r in await repo.nextQueued(9)) r.requestedAt!];
    expect(times.toSet(), hasLength(3));
    expect(times, [...times]..sort());
  });

  test('resetInterrupted moves downloading back to queued', () async {
    await track('y1');
    await track('y2');
    await setRow('y1', 'downloading');
    await setRow('y2', 'done', path: 'x');
    await repo.resetInterrupted();
    expect((await row('y1'))!.state, 'queued');
    expect((await row('y2'))!.state, 'done');
  });

  group('reconcileMissing', () {
    test('requeues a wanted done row whose file is gone', () async {
      await track('y1');
      await entry('A', 'y1');
      await repo.setPlaylistDownload('A', true);
      await setRow('y1', 'done', path: '${ytDir.path}/gone.opus', bytes: 9);
      await repo.reconcileMissing();
      final r = (await row('y1'))!;
      expect((r.state, r.path, r.bytes), ('queued', '', 0));
    });

    test('deletes an unwanted one and keeps one whose file exists', () async {
      await track('y1');
      await track('y2');
      final f = File('${ytDir.path}/ok.opus')..writeAsStringSync('x');
      await setRow('y1', 'done', path: '${ytDir.path}/gone.opus');
      await setRow('y2', 'done', path: f.path, bytes: 1);
      await repo.reconcileMissing();
      expect(await row('y1'), isNull);
      expect((await row('y2'))!.state, 'done');
    });
  });

  test('queueAdded is a no-op unless the playlist is enabled', () async {
    await track('y1');
    await entry('A', 'y1');
    expect(await repo.queueAdded('A', ['y1']), 0);
    await repo.setPlaylistDownload('A', true);
    await db.delete(db.localFiles).go();
    expect(await repo.queueAdded('A', ['y1']), 1);
  });

  test(
    'queueNewInEnabled queues only enabled-playlist songs with no row',
    () async {
      await track('y1');
      await track('y2');
      await track('y3');
      await track('l1', source: 'local');
      await entry('A', 'y1');
      await entry('B', 'y3');
      expect(await repo.queueNewInEnabled(), 0);
      await repo.setPlaylistDownload('A', true);
      await setRow('y1', 'failed');
      await entry('A', 'y2');
      await entry('A', 'l1');
      expect(await repo.queueNewInEnabled(), 1);
      expect((await row('y2'))!.state, 'queued');
      expect((await row('y1'))!.state, 'failed', reason: 'left for Retry');
      expect(await row('y3'), null);
      expect(await row('l1'), null);
    },
  );

  test('downloadTrack: manual queue, false for local or unavailable', () async {
    await track('y1');
    await track('y2', unavailable: true);
    await track('l1', source: 'local');
    expect(await repo.downloadTrack('y1'), isTrue);
    final r = (await row('y1'))!;
    expect((r.state, r.manual), ('queued', true));
    expect(await repo.downloadTrack('y2'), isFalse);
    expect(await repo.downloadTrack('l1'), isFalse);
    expect(await row('l1'), isNull);
  });

  test(
    'removeTrackDownload keeps the file while an enabled playlist has it',
    () async {
      await track('y1');
      await track('y2');
      final f1 = File('${ytDir.path}/1.opus')..writeAsStringSync('x');
      final f2 = File('${ytDir.path}/2.opus')..writeAsStringSync('x');
      await entry('A', 'y1');
      await repo.setPlaylistDownload('A', true);
      await setRow('y1', 'done', path: f1.path, bytes: 1, manual: true);
      await setRow('y2', 'done', path: f2.path, bytes: 1, manual: true);
      await repo.removeTrackDownload('y1', ytDir);
      await repo.removeTrackDownload('y2', ytDir);
      expect((await row('y1'))!.manual, isFalse);
      expect(f1.existsSync(), isTrue);
      expect(await row('y2'), isNull);
      expect(f2.existsSync(), isFalse);
    },
  );

  test(
    'removeFiles deletes files and rows, frees bytes, spares outside files',
    () async {
      await track('y1');
      await track('y2');
      await track('y3');
      final f1 = File('${ytDir.path}/1.opus')..writeAsStringSync('x');
      final outside = File('${tmp.path}/keep.opus')..writeAsStringSync('x');
      await setRow('y1', 'done', path: f1.path, bytes: 40);
      await setRow('y2', 'done', path: outside.path, bytes: 2);
      await setRow('y3', 'queued');
      expect(await repo.removeFiles(['y1', 'y2', 'y3'], ytDir), 42);
      expect(f1.existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
      expect(await db.select(db.localFiles).get(), isEmpty);
    },
  );

  test('removeFiles ignores local tracks', () async {
    await track('l1', source: 'local');
    final f = File('${ytDir.path}/l.mp3')..writeAsStringSync('x');
    await setRow('l1', 'done', path: f.path, bytes: 1);
    expect(await repo.removeFiles(['l1'], ytDir), 0);
    expect(await row('l1'), isNotNull);
    expect(f.existsSync(), isTrue);
  });

  test(
    'dropUnwanted deletes unwanted queued/downloading/failed rows',
    () async {
      for (final id in ['y1', 'y2', 'y3', 'y4', 'y5', 'y6']) {
        await track(id);
      }
      await entry('A', 'y1');
      await repo.setPlaylistDownload('A', true); // y1 queued, wanted
      await setRow('y2', 'queued');
      await setRow('y3', 'failed');
      await setRow('y4', 'queued', manual: true);
      await setRow('y5', 'done', path: 'x');
      await setRow('y6', 'downloading');
      await repo.dropUnwanted();
      expect(await row('y1'), isNotNull);
      expect(await row('y2'), isNull);
      expect(await row('y3'), isNull);
      expect(await row('y4'), isNotNull);
      expect(await row('y5'), isNotNull);
      expect(await row('y6'), isNull);
    },
  );

  test('retryFailed requeues failed rows, optionally per playlist', () async {
    await track('y1');
    await track('y2');
    await entry('A', 'y1');
    await setRow('y1', 'failed');
    await setRow('y2', 'failed');
    await repo.retryFailed(playlistId: 'A');
    expect((await row('y1'))!.state, 'queued');
    expect((await row('y2'))!.state, 'failed');
    await repo.retryFailed();
    expect((await row('y2'))!.state, 'queued');
    expect((await row('y2'))!.error, isNull);
  });

  test('retryFailed can retry one track', () async {
    await track('y1');
    await track('y2');
    await setRow('y1', 'failed');
    await setRow('y2', 'failed');
    await repo.retryFailed(trackId: 'y2');
    expect((await row('y1'))!.state, 'failed');
    expect((await row('y2'))!.state, 'queued');
  });

  test('downloadError and doneBytes read single rows', () async {
    await track('y1');
    await track('y2');
    await track('y3');
    await setRow('y1', 'done', bytes: 100);
    await setRow('y2', 'done', bytes: 50);
    await setRow('y3', 'queued', bytes: 7);
    await repo.markFailed('y3', 'This video is private');
    expect(await repo.downloadError('y3'), 'This video is private');
    expect(await repo.downloadError('y1'), isNull);
    expect(await repo.downloadError('nope'), isNull);
    expect(await repo.doneBytes(['y1', 'y2', 'y3', 'nope']), 150);
  });

  test('queue moves update state, path, bytes and error', () async {
    await track('y1');
    await setRow('y1', 'queued', requestedAt: 1);
    await repo.markDownloading('y1');
    expect((await row('y1'))!.state, 'downloading');
    await repo.markFailed('y1', 'nope');
    expect(
      ((await row('y1'))!.state, (await row('y1'))!.error),
      ('failed', 'nope'),
    );
    await repo.requeue('y1');
    expect((await row('y1'))!.error, isNull);
    await repo.markDone('y1', '/p/y.opus', 77);
    final r = (await row('y1'))!;
    expect((r.state, r.path, r.bytes, r.mtimeMs), ('done', '/p/y.opus', 77, 0));
  });

  test('watchPlaylist emits a new status after markDone', () async {
    await threeYtOneLocal('A');
    await repo.setPlaylistDownload('A', true);
    final emitted = <PlaylistDownloadStatus>[];
    final sub = repo.watchPlaylist('A').listen(emitted.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emitted.last.total, 2); // the unavailable and local ones excluded
    expect(emitted.last.queued, 2);
    expect(emitted.last.enabled, isTrue);
    await repo.markDone('y1', '/p/y.opus', 10);
    await pumpEventQueue();
    expect(emitted.last.done, 1);
    expect(emitted.last.queued, 1);
    expect(emitted.last.bytes, 10);
  });

  test(
    'watchYtRows lists yt rows only; totals and per-playlist bytes follow',
    () async {
      await track('y1');
      await track('l1', source: 'local');
      await entry('A', 'y1');
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'A',
              clock: 'c',
              originDevice: 'dev',
              localSeq: 99,
              name: 'A',
              source: 'local',
            ),
          );
      await setRow('l1', 'done', path: '/m/l.mp3', bytes: 100);
      final rows = <List<LocalFile>>[];
      final totals = <int>[];
      final per = <List<(String, int)>>[];
      final subs = [
        repo.watchYtRows().listen(rows.add),
        repo.watchTotalBytes().listen(totals.add),
        repo.watchBytesPerPlaylist().listen(per.add),
      ];
      addTearDown(() => Future.wait(subs.map((s) => s.cancel())));
      await pumpEventQueue();
      expect(rows.last, isEmpty);
      expect(totals.last, 0);
      await repo.downloadTrack('y1');
      await repo.markDone('y1', '/p/y.opus', 30);
      await pumpEventQueue();
      expect([for (final r in rows.last) r.trackId], ['y1']);
      expect(totals.last, 30);
      expect(per.last, [('A', 30)]);
    },
  );

  test('watchTrackStates maps track ids to states', () async {
    await track('y1');
    await track('y2');
    await setRow('y1', 'downloading');
    final s = <Map<String, String>>[];
    final sub = repo.watchTrackStates(['y1', 'y2']).listen(s.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(s.last, {'y1': 'downloading'});
    await repo.markDone('y1', 'p', 1);
    await pumpEventQueue();
    expect(s.last, {'y1': 'done'});
  });

  test('mark moves report false when the row was removed meanwhile', () async {
    await track('y1');
    await setRow('y1', 'downloading');
    await repo.removeFiles(['y1'], ytDir);
    expect(await repo.markDone('y1', '${ytDir.path}/v.opus', 5), isFalse);
    expect(await repo.markDownloading('y1'), isFalse);
    expect(await repo.markFailed('y1', 'x'), isFalse);
    expect(await repo.requeue('y1'), isFalse);
    await setRow('y1', 'queued');
    expect(await repo.markDownloading('y1'), isTrue);
    expect(await repo.markDone('y1', 'p', 5), isTrue);
  });

  test('watchTrackStates ignores local-library rows', () async {
    await track('y1');
    await track('l1', source: 'local');
    await setRow('y1', 'queued');
    await setRow('l1', 'done', path: '/m/l.mp3', bytes: 1);
    final s = <Map<String, String>>[];
    final sub = repo.watchTrackStates(['y1', 'l1']).listen(s.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(s.last, {'y1': 'queued'});
  });

  test(
    'yt watchers and reconcileMissing work past the SQL variable limit',
    () async {
      // More local-library rows than SQLite binds variables in one query
      // (32766), so a query binding every row's track id would fail.
      const n = 33000;
      await db.batch((b) {
        b.insertAll(db.tracks, [
          for (var i = 0; i < n; i++)
            trackRow(id: 'l$i', source: 'local', fileHash: 'h$i'),
        ]);
        b.insertAll(db.localFiles, [
          for (var i = 0; i < n; i++)
            LocalFilesCompanion.insert(
              trackId: 'l$i',
              path: '/m/l$i.mp3',
              state: 'done',
              bytes: 1,
              mtimeMs: 0,
            ),
        ]);
      });
      await track('y1');
      await track('y2');
      await entry('A', 'y1');
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'A',
              clock: 'c',
              originDevice: 'dev',
              localSeq: 99,
              name: 'A',
              source: 'local',
            ),
          );
      final f = File('${ytDir.path}/y1.opus')..writeAsStringSync('x');
      await setRow('y1', 'done', path: f.path, bytes: 30);
      await setRow('y2', 'done', path: '${ytDir.path}/gone.opus', bytes: 5);

      await repo.reconcileMissing();
      expect(await row('y2'), isNull);
      expect((await row('l0'))!.state, 'done');

      expect(
        [for (final r in await repo.watchYtRows().first) r.trackId],
        ['y1'],
      );
      expect(await repo.watchTotalBytes().first, 30);
      expect(await repo.watchBytesPerPlaylist().first, [('A', 30)]);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
