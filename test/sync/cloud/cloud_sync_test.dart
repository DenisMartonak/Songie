import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/core/result.dart';
import 'package:songies/sync/cloud/cloud_sync.dart';
import 'package:songies/sync/cloud/sync_status.dart';

import '../../helpers/sync_fixtures.dart';
import '../../helpers/test_db.dart';
import 'fake_cloud.dart';

/// The wall clock every device's stamps read; tests move it to order edits.
var _nowMs = 1800000000000;

/// One simulated device.
class _Dev {
  _Dev._(this.db, this.stamp, this.settings, this.remote, this.sync)
    : lib = LibraryRepository(db, stamp),
      favorites = FavoritesRepository(db, stamp);

  final AppDatabase db;
  final SyncStamp stamp;
  final SettingsRepository settings;
  final FakeRemote remote;
  final CloudSync sync;
  final LibraryRepository lib;
  final FavoritesRepository favorites;

  static Future<_Dev> make(
    FakeServer server, {
    Future<bool> Function(Future<void> cancelled)? askMerge,
    Stream<NetworkKind>? network,
    Directory? fontsDir,
    Duration pushDelay = const Duration(hours: 1),
    int clockOffsetMs = 0,
    Duration stopWait = const Duration(seconds: 45),
  }) async {
    final db = testDb();
    final stamp = await SyncStamp.load(db, nowMs: () => _nowMs + clockOffsetMs);
    final settings = SettingsRepository(db);
    final remote = FakeRemote(server);
    final sync = CloudSync(
      db: db,
      stamp: stamp,
      remote: remote,
      settings: settings,
      network: network,
      askMerge: askMerge,
      fontsDir: fontsDir,
      pushDelay: pushDelay,
      now: () => DateTime.fromMillisecondsSinceEpoch(_nowMs + clockOffsetMs),
      stopWait: stopWait,
    );
    return _Dev._(db, stamp, settings, remote, sync);
  }

  Future<void> start(String user) {
    remote.user = user;
    return sync.start(user);
  }

  Future<String> newPlaylist(String name) async =>
      ((await lib.createPlaylist(name)) as Ok<String>).value;

  /// A YouTube playlist imported here, as the importer stores it.
  Future<String> importYt(String name, String url) async {
    final st = await stamp.next();
    await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: st.id,
            clock: st.clock,
            originDevice: st.originDevice,
            localSeq: st.localSeq,
            name: name,
            source: 'yt',
            ytPlaylistUrl: Value(url),
          ),
        );
    return st.id;
  }

  Future<List<Playlist>> livePlaylists() =>
      (db.select(db.playlists)..where((p) => p.deleted.equals(false))).get();

  Future<List<String>> liveNames() async =>
      [for (final p in await livePlaylists()) p.name]..sort();

  Future<void> dispose() async {
    await sync.dispose();
    await db.close();
  }
}

/// Every device syncs, twice round, so merges made on one reach the rest.
Future<void> _settle(List<_Dev> devs) async {
  for (var i = 0; i < 2; i++) {
    for (final d in devs) {
      await d.sync.syncNow();
    }
  }
}

void main() {
  late FakeServer server;
  final devs = <_Dev>[];

  Future<_Dev> dev({
    Future<bool> Function(Future<void> cancelled)? askMerge,
    Stream<NetworkKind>? network,
    Directory? fontsDir,
    Duration pushDelay = const Duration(hours: 1),
    int clockOffsetMs = 0,
    Duration stopWait = const Duration(seconds: 45),
  }) async {
    final d = await _Dev.make(
      server,
      askMerge: askMerge,
      network: network,
      fontsDir: fontsDir,
      pushDelay: pushDelay,
      clockOffsetMs: clockOffsetMs,
      stopWait: stopWait,
    );
    devs.add(d);
    return d;
  }

  // Two devices means two databases on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() {
    server = FakeServer();
    _nowMs = 1800000000000;
  });

  tearDown(() async {
    for (final d in devs) {
      await d.dispose();
    }
    devs.clear();
  });

  test(
    'a playlist made on device A appears on device B after both sync',
    () async {
      final a = await dev();
      final b = await dev();
      await a.start('u1');
      await b.start('u1');
      await a.newPlaylist('Road trip');
      await a.sync.syncNow();
      await b.sync.syncNow();
      expect(await b.liveNames(), ['Road trip']);
    },
  );

  test('offline edits on both devices converge, newer clock per row; '
      'a newer delete wins', () async {
    final a = await dev();
    final b = await dev();
    await a.start('u1');
    await b.start('u1');
    final p1 = await a.newPlaylist('One');
    final p2 = await a.newPlaylist('Two');
    await _settle([a, b]);
    expect(await b.liveNames(), ['One', 'Two']);

    // Both offline: no sync while they edit.
    _nowMs += 1000;
    await a.lib.renamePlaylist(p1, 'One by A');
    _nowMs += 1000;
    await b.lib.renamePlaylist(p1, 'One by B'); // newer
    _nowMs += 1000;
    await a.lib.renamePlaylist(p2, 'Two by A');
    _nowMs += 1000;
    await b.lib.deletePlaylist(p2); // newer
    _nowMs += 1000;

    await _settle([a, b]);
    expect(await a.liveNames(), ['One by B']);
    expect(await b.liveNames(), ['One by B']);
    expect(await snapshot(a.db), await snapshot(b.db));
  });

  test(
    'no duplicate playlist when both devices create "Chill" offline',
    () async {
      const url = 'https://www.youtube.com/playlist?list=PLchill';
      final a = await dev();
      final b = await dev();
      await a.importYt('Chill', url);
      await b.importYt('Chill', url);
      await a.start('u1');
      await b.start('u1');
      await _settle([a, b]);
      final onA = await a.livePlaylists();
      final onB = await b.livePlaylists();
      expect(onA.map((p) => p.name), ['Chill']);
      expect(onB.map((p) => p.id), [onA.single.id]);
      expect(await snapshot(a.db), await snapshot(b.db));
    },
  );

  test('pages of 500: 1200 rows push in 3 calls and pull in 3 calls', () async {
    final a = await dev();
    final b = await dev();
    final stamps = await a.stamp.nextMany(1200);
    await a.db.batch((batch) {
      batch.insertAll(a.db.tracks, [
        for (final s in stamps)
          trackRow(
            id: s.id,
            clock: s.clock,
            originDevice: s.originDevice,
            localSeq: s.localSeq,
          ),
      ]);
    });
    await a.start('u1');
    expect(a.remote.pushCalls, 3);
    expect([for (final p in a.remote.pushes) p.length], [500, 500, 200]);
    expect(server.rowsOf('u1'), hasLength(1200));

    await b.start('u1');
    expect(b.remote.pullCalls, 3);
    expect(b.remote.pushCalls, 0);
    expect(await b.db.select(b.db.tracks).get(), hasLength(1200));
  });

  test(
    'a failed push leaves the watermark; the retry sends the same rows',
    () async {
      final a = await dev();
      await a.start('u1');
      final before = await a.settings.getString('cloud_push_seq:u1');
      await a.newPlaylist('Kept');
      a.remote.failPushes = 1;
      await a.sync.syncNow();
      expect(a.sync.current.phase, SyncPhase.offline);
      expect(await a.settings.getString('cloud_push_seq:u1'), before);
      expect(server.rowsOf('u1'), isEmpty);

      await a.sync.syncNow();
      expect(a.sync.current.phase, SyncPhase.idle);
      final tries = a.remote.pushes;
      expect(tries, hasLength(2));
      expect(
        [for (final r in tries[1]) '${r.table.wire}/${r.id}@${r.clock}'],
        [for (final r in tries[0]) '${r.table.wire}/${r.id}@${r.clock}'],
      );
      expect(server.rowsOf('u1'), hasLength(1));
      expect(await a.sync.hasUnsent(), isFalse);
    },
  );

  test(
    'a Realtime change during a push triggers exactly one follow-up pull',
    () async {
      final a = await dev();
      await a.start('u1');
      a.remote.pullCalls = 0;
      a.remote.pushCalls = 0;
      await a.newPlaylist('Live');
      a.remote.duringPush = () async {
        server.broadcast('u1');
        server.broadcast('u1');
        await Future<void>.delayed(Duration.zero);
      };
      await a.sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.remote.pushCalls, 1);
      expect(a.remote.pullCalls, 2);
      expect(server.rowsOf('u1'), hasLength(1));
    },
  );

  test('applying pulled rows does not push them back (no echo)', () async {
    final a = await dev();
    final b = await dev();
    await a.start('u1');
    for (final n in ['A', 'B', 'C']) {
      await a.newPlaylist(n);
    }
    await a.sync.syncNow();
    await b.start('u1');
    expect(await b.liveNames(), ['A', 'B', 'C']);
    expect(b.remote.pushCalls, 0);
    await b.sync.syncNow();
    expect(b.remote.pushCalls, 0);
    expect(await b.sync.hasUnsent(), isFalse);

    final id = (await b.livePlaylists()).firstWhere((p) => p.name == 'B').id;
    _nowMs += 1000;
    await b.lib.renamePlaylist(id, 'B2');
    await b.sync.syncNow();
    expect(b.remote.pushCalls, 1);
    expect([for (final r in b.remote.pushes.single) r.id], [id]);
  });

  test('signed out: no remote calls', () async {
    final net = StreamController<NetworkKind>.broadcast(sync: true);
    addTearDown(net.close);
    final a = await dev(network: net.stream, pushDelay: Duration.zero);
    await a.newPlaylist('Local only');
    a.sync.localWrite();
    await a.sync.syncNow();
    net.add(NetworkKind.offline);
    net.add(NetworkKind.wifi);
    expect(await a.sync.hasUnsent(), isFalse);
    await a.sync.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.remote.calls, 0);

    // After a sign-out, nothing either.
    await a.start('u1');
    await a.sync.stop();
    final calls = a.remote.calls;
    await a.newPlaylist('After');
    a.sync.localWrite();
    await a.sync.syncNow();
    net.add(NetworkKind.wifi);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.remote.calls, calls);
    expect(a.sync.current.phase, SyncPhase.idle);
  });

  test(
    'hasUnsent is true after a local write and false after a push',
    () async {
      final a = await dev();
      await a.start('u1');
      expect(await a.sync.hasUnsent(), isFalse);
      await a.newPlaylist('New');
      expect(await a.sync.hasUnsent(), isTrue);
      await a.sync.syncNow();
      expect(await a.sync.hasUnsent(), isFalse);
    },
  );

  test('a local write pushes after the push delay', () async {
    final a = await dev(pushDelay: const Duration(milliseconds: 50));
    await a.start('u1');
    await a.newPlaylist('Soon');
    expect(server.rowsOf('u1'), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.rowsOf('u1'), hasLength(1));
  });

  test('switching to another account asks; Start empty wipes the synced '
      'tables but keeps tracks and local files', () async {
    final fontsDir = await Directory.systemTemp.createTemp('cloud_fonts');
    addTearDown(() => fontsDir.delete(recursive: true));
    final font = File('${fontsDir.path}/h.ttf')..writeAsStringSync('font');
    var asked = 0;
    final a = await dev(
      fontsDir: fontsDir,
      askMerge: (_) async {
        asked++;
        return false;
      },
    );
    await seedOneOfEach(a.db);
    await a.favorites.ensureFavorites();
    await a.favorites.star('t1');
    await a.db
        .into(a.db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: 't1',
            path: '/music/t1.mp3',
            state: 'done',
            bytes: 1,
            mtimeMs: 1,
          ),
        );
    await a.start('u1');
    expect(asked, 0); // first account on this device
    await a.sync.stop();

    await a.start('u2');
    expect(asked, 1);
    final db = a.db;
    expect(
      [for (final p in await db.select(db.playlists).get()) p.id],
      [kFavoritesPlaylistId],
    );
    expect(await db.select(db.playlistEntries).get(), isEmpty);
    expect(await db.select(db.themes).get(), isEmpty);
    expect(await db.select(db.fonts).get(), isEmpty);
    expect(await db.select(db.lyrics).get(), isEmpty);
    expect(await db.select(db.listens).get(), isEmpty);
    expect(await db.select(db.ytSeen).get(), isEmpty);
    expect(font.existsSync(), isFalse);
    expect(await db.select(db.tracks).get(), hasLength(1));
    expect(await db.select(db.localFiles).get(), hasLength(1));
    expect(await a.settings.getString('cloud_last_account'), 'u2');
    expect(server.rowsOf('u2').keys.toSet(), {
      'tracks/t1',
      'playlists/$kFavoritesPlaylistId',
    });

    // Back to u1: asked again; Merge keeps everything and sends it up.
    await a.sync.stop();
    final b = await dev(askMerge: (_) async => true);
    await b.newPlaylist('Mine');
    await b.settings.setString('cloud_last_account', 'u2');
    await b.start('u1');
    expect(await b.liveNames(), unorderedEquals(['Mine', 'P', 'Favorites']));
    expect(server.rowsOf('u1').values.map((d) => d['name']), contains('Mine'));
  });

  test('while the merge question is open the status is syncing; signing out '
      'or another sign-in cancels it, and its late answer changes '
      'nothing', () async {
    final answers = <Completer<bool>>[];
    final cancels = <Future<void>>[];
    final a = await dev(
      askMerge: (cancelled) {
        cancels.add(cancelled);
        answers.add(Completer<bool>());
        return answers.last.future;
      },
    );
    await a.newPlaylist('Mine');
    await a.settings.setString('cloud_last_account', 'other');
    final cancelled = <int>{};

    final first = a.start('u1');
    await pumpEventQueue();
    expect(cancels, hasLength(1));
    unawaited(cancels[0].then((_) => cancelled.add(0)));
    expect(a.sync.current.phase, SyncPhase.syncing);

    // Signing in as someone else meanwhile: the first question goes away.
    a.remote.user = 'u2';
    final second = a.sync.start('u2');
    await pumpEventQueue();
    expect(cancelled, {0});
    expect(cancels, hasLength(2));
    unawaited(cancels[1].then((_) => cancelled.add(1)));
    expect(a.sync.current.phase, SyncPhase.syncing);

    await a.sync.stop();
    await pumpEventQueue();
    expect(cancelled, {0, 1});
    expect(a.sync.current.phase, SyncPhase.idle);

    // Late "Start empty" answers wipe nothing and record no account.
    for (final c in answers) {
      c.complete(false);
    }
    await first;
    await second;
    expect(await a.liveNames(), contains('Mine'));
    expect(await a.settings.getString('cloud_last_account'), 'other');
    expect(a.remote.pushCalls, 0);
  });

  test(
    'status goes syncing -> idle with lastSynced; offline -> offline phase',
    () async {
      final net = StreamController<NetworkKind>.broadcast(sync: true);
      addTearDown(net.close);
      final a = await dev(network: net.stream);
      final seen = <SyncStatus>[];
      final sub = a.sync.status.listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [const SyncStatus(SyncPhase.idle)]);

      await a.start('u1');
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((s) => s.phase), [
        SyncPhase.idle,
        SyncPhase.syncing,
        SyncPhase.idle,
      ]);
      expect(seen.last.lastSynced, isNotNull);

      net.add(NetworkKind.offline);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.phase, SyncPhase.offline);
      expect(seen.last.lastSynced, isNotNull);

      net.add(NetworkKind.wifi); // back: pulls
      await a.sync.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.phase, SyncPhase.idle);

      a.remote.offline = true;
      await a.sync.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.phase, SyncPhase.offline);
    },
  );

  group('fix round 1', () {
    const day = 86400000;

    test('a refused push still pulls; the failure shows in status', () async {
      final a = await dev();
      final b = await dev();
      await a.start('u1');
      await a.newPlaylist('From A');
      await a.sync.syncNow();
      await b.newPlaylist('Stuck on B');
      b.remote.pushError = Exception('server error');
      await b.start('u1');
      expect(await b.liveNames(), ['From A', 'Stuck on B']);
      expect(b.sync.current.phase, SyncPhase.error);
      expect(await b.sync.hasUnsent(), isTrue);
    });

    test(
      'a row the server refuses is skipped; the rest of the page goes up',
      () async {
        final a = await dev();
        final ids = [for (var i = 0; i < 7; i++) await a.newPlaylist('P$i')];
        server.rejectIds.add(ids[3]);
        await a.start('u1');
        expect(server.rowsOf('u1').keys.toSet(), {
          for (final id in ids)
            if (id != ids[3]) 'playlists/$id',
        });
        expect(a.sync.current.phase, SyncPhase.idle);
        expect(await a.sync.hasUnsent(), isFalse);
      },
    );

    test('rows stamped with a clock a day ahead are restamped and go up on '
        'right after', () async {
      server.nowMs = () => _nowMs;
      final a = await dev();
      // The device's clock ran three days fast for a while, then was fixed.
      _nowMs += 3 * day;
      final ahead = await a.newPlaylist('From the future');
      _nowMs -= 3 * day;
      // A row from another device, with a sane clock.
      await a.db
          .into(a.db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'fine',
              clock: '${_nowMs.toString().padLeft(13, '0')}-00000-other',
              originDevice: 'other',
              localSeq: (await a.stamp.reserve(1)).single,
              name: 'Fine',
              source: 'local',
            ),
          );
      await a.start('u1');
      final row = await (a.db.select(
        a.db.playlists,
      )..where((p) => p.id.equals(ahead))).getSingle();
      expect(int.parse(row.clock.substring(0, 13)), lessThanOrEqualTo(_nowMs));
      expect(row.name, 'From the future');
      // The restamped row goes up after the refused page, in the same run.
      expect(server.rowsOf('u1').keys.toSet(), {
        'playlists/fine',
        'playlists/$ahead',
      });
      expect(server.rowsOf('u1')['playlists/$ahead']!['clock'], row.clock);
      expect(a.sync.current.phase, SyncPhase.idle);
      expect(await a.sync.hasUnsent(), isFalse);
    });

    test('an edit made during a refused push is not replaced by the '
        'restamp', () async {
      server.nowMs = () => _nowMs;
      final a = await dev();
      _nowMs += 3 * day;
      final id = await a.newPlaylist('Old name');
      _nowMs -= 3 * day;
      var edited = false;
      a.remote.duringPush = () async {
        if (edited) return;
        edited = true;
        await a.lib.renamePlaylist(id, 'Edited');
      };
      // Run 1: refused; the edited row is left alone. The edit itself was
      // stamped while the clock was still ahead, so run 2 restamps it and
      // run 3 sends it.
      await a.start('u1');
      await a.sync.syncNow();
      await a.sync.syncNow();
      final row = await (a.db.select(
        a.db.playlists,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(edited, isTrue);
      expect(row.name, 'Edited');
      expect(server.rowsOf('u1')['playlists/$id']!['name'], 'Edited');
      expect(await a.sync.hasUnsent(), isFalse);
    });

    test('a device whose clock is a day ahead shows clockWrong and keeps '
        'pulling', () async {
      server.nowMs = () => _nowMs;
      final a = await dev();
      await a.start('u1');
      await a.newPlaylist('From A');
      await a.sync.syncNow();
      final b = await dev(clockOffsetMs: 2 * day);
      await b.newPlaylist('On B');
      await b.start('u1');
      expect(b.sync.current.phase, SyncPhase.clockWrong);
      expect(await b.liveNames(), ['From A', 'On B']);
      expect(server.rowsOf('u1'), hasLength(1));
    });

    test('stop gives up on a hung sync after the stop wait', () async {
      final a = await dev(stopWait: const Duration(milliseconds: 50));
      await a.start('u1');
      await a.newPlaylist('Hangs');
      final never = Completer<void>();
      a.remote.duringPush = () => never.future;
      unawaited(a.sync.syncNow());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final watch = Stopwatch()..start();
      await a.sync.stop();
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(a.sync.current.phase, SyncPhase.idle);
    });

    test(
      'a start right after a stop is not undone by the stop finishing',
      () async {
        final a = await dev();
        await a.start('u1');
        final gate = Completer<void>();
        a.remote.duringClose = () => gate.future;
        final stopping = a.sync.stop();
        final starting = a.start('u1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        gate.complete();
        await stopping;
        await starting;
        expect(a.remote.live, isTrue);
        expect(a.sync.current.phase, SyncPhase.idle);
        expect(a.sync.current.lastSynced, isNotNull);
        final pulls = a.remote.pullCalls;
        server.broadcast('u1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(a.remote.pullCalls, pulls + 1);
      },
    );

    test('a row just over 240 KB is not sent', () async {
      final a = await dev();
      final st = await a.stamp.next(id: 't1');
      await a.db
          .into(a.db.tracks)
          .insert(
            trackRow(
              id: 't1',
              clock: st.clock,
              originDevice: st.originDevice,
              localSeq: st.localSeq,
              // Title and search text: about 242 KB, under the server's 256 KB.
              title: 'x' * (121 * 1024),
            ),
          );
      await a.start('u1');
      expect(a.remote.pushCalls, 0);
    });
  });
}
