import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/app_version.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/sync/change_feed.dart';
import 'package:songies/sync/device_identity.dart';
import 'package:songies/sync/merger.dart';
import 'package:songies/sync/peer_repository.dart';
import 'package:songies/sync/sync_auth.dart';
import 'package:songies/sync/sync_client.dart';
import 'package:songies/sync/sync_progress.dart';
import 'package:songies/sync/sync_responder.dart';
import 'package:songies/sync/sync_runner.dart';
import 'package:songies/sync/sync_server.dart';

import '../helpers/sync_devices.dart';
import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

/// Timers the responder starts, fired by hand.
class _Timers {
  final made = <_FakeTimer>[];

  Timer create(Duration d, void Function() callback) {
    final t = _FakeTimer(d, callback);
    made.add(t);
    return t;
  }

  /// Fires every active timer.
  void fire() {
    for (final t in made.where((t) => t.isActive).toList()) {
      t.fire();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

/// How far every device's stamps run ahead of real time; moved forward to
/// stand for time passing between edits.
var _stampAhead = Duration.zero;

/// One simulated device: database, stamp, server, responder and runner.
class _Dev {
  _Dev._(this.name, this.identity, this.db, this.stamp, this.peers);

  final String name;
  final DeviceIdentity identity;
  final AppDatabase db;
  final SyncStamp stamp;
  final PeerRepository peers;
  final timers = _Timers();
  late final SyncServer server;
  late final SyncResponder responder;
  late final SyncRunner runner;
  late final int port;
  final states = <ResponderState>[];

  String get id => stamp.deviceId;

  static Future<_Dev> create(
    Directory root,
    String name, {
    Duration skew = Duration.zero,
  }) async {
    final db = testDb();
    final d = _Dev._(
      name,
      await testIdentity(root, name),
      db,
      await SyncStamp.load(
        db,
        nowMs: () => DateTime.now().add(_stampAhead).millisecondsSinceEpoch,
      ),
      PeerRepository(db),
    );
    DateTime now() => DateTime.now().add(skew);
    d.runner = SyncRunner(
      db: db,
      stamp: d.stamp,
      peers: d.peers,
      myDeviceId: d.id,
      downloads: DownloadRepository(db),
    );
    d.responder = SyncResponder(
      db: db,
      stamp: d.stamp,
      peers: d.peers,
      myDeviceId: d.id,
      myName: () => name,
      downloads: DownloadRepository(db),
      runningLocally: () => d.runner.running,
      now: now,
      timer: d.timers.create,
    );
    d.responder.state.listen(d.states.add);
    d.server = SyncServer(d.identity, RequestVerifier(d.peers, now: now));
    d.responder.register(d.server);
    d.port = await serveLoopback(d.server);
    return d;
  }

  Future<void> dispose() async {
    await server.stop();
    await db.close();
  }

  Future<PeerRow> peer(_Dev other) async => (await peers.byId(other.id))!;

  Future<Map<String, String>> snap() => snapshot(db);

  Future<int> high() => ChangeFeed(db).highSeq();
}

Future<void> _pair(_Dev a, _Dev b) async {
  final rnd = Random.secure();
  final key = base64.encode([for (var i = 0; i < 32; i++) rnd.nextInt(256)]);
  PeerRow row(_Dev other) => PeerRow(
    deviceId: other.id,
    name: other.name,
    certFingerprint: other.identity.fingerprint,
    pairKey: key,
    lastSentSeq: 0,
    lastReceivedSeq: 0,
  );
  await a.peers.save(row(b));
  await b.peers.save(row(a));
}

Future<Map<String, Resolution>?> _noClashes(List<PlaylistClash> c) async {
  fail('unexpected clash: ${c.map((x) => x.playlistId)}');
}

/// Runs a sync from [a] to [b] and returns every progress event.
Future<List<SyncProgress>> _sync(
  _Dev a,
  _Dev b, {
  Future<Map<String, Resolution>?> Function(List<PlaylistClash>)? choose,
  SyncRunner? runner,
}) async => (runner ?? a.runner)
    .run(
      await a.peer(b),
      host: '127.0.0.1',
      port: b.port,
      choose: choose ?? _noClashes,
    )
    .toList();

SyncSummary _done(List<SyncProgress> events) {
  final last = events.last;
  if (last is! SyncDone) fail('sync did not finish: $last');
  return last.summary;
}

SyncFailure? _failure(List<SyncProgress> events) {
  final last = events.last;
  return last is SyncFailed ? last.failure : null;
}

// --- Writes, stamped like the app's ------------------------------------------

Future<String> _track(
  _Dev d, {
  String? id,
  String? video,
  String title = 'Title',
}) async {
  final st = await d.stamp.next(id: id);
  await d.db
      .into(d.db.tracks)
      .insert(
        trackRow(
          id: st.id,
          ytVideoId: video,
          source: video == null ? 'local' : 'yt',
          title: title,
          clock: st.clock,
          originDevice: st.originDevice,
          localSeq: st.localSeq,
        ),
      );
  return st.id;
}

Future<String> _playlist(_Dev d, String name) async {
  final st = await d.stamp.next();
  await d.db
      .into(d.db.playlists)
      .insert(
        PlaylistsCompanion.insert(
          id: st.id,
          clock: st.clock,
          originDevice: st.originDevice,
          localSeq: st.localSeq,
          name: name,
          source: 'local',
        ),
      );
  return st.id;
}

Future<String> _entry(_Dev d, String playlistId, String trackId) async {
  final st = await d.stamp.next();
  await d.db
      .into(d.db.playlistEntries)
      .insert(
        PlaylistEntriesCompanion.insert(
          id: st.id,
          clock: st.clock,
          originDevice: st.originDevice,
          localSeq: st.localSeq,
          playlistId: playlistId,
          trackId: trackId,
          position: 'a0',
          addedAt: DateTime.now(),
        ),
      );
  return st.id;
}

Future<String> _listen(_Dev d, String trackId) async {
  final st = await d.stamp.next();
  await d.db
      .into(d.db.listens)
      .insert(
        ListensCompanion.insert(
          id: st.id,
          clock: st.clock,
          originDevice: st.originDevice,
          localSeq: st.localSeq,
          trackId: trackId,
          startedAt: DateTime.now(),
          heardMs: 1000,
          counted: true,
          mainArtist: 'A',
          titleSnapshot: 'T',
          artistSnapshot: 'A',
        ),
      );
  return st.id;
}

Future<void> _rename(_Dev d, String playlistId, String name) async {
  final st = await d.stamp.next();
  await (d.db.update(
    d.db.playlists,
  )..where((p) => p.id.equals(playlistId))).write(
    PlaylistsCompanion(
      name: Value(name),
      clock: Value(st.clock),
      originDevice: Value(st.originDevice),
      localSeq: Value(st.localSeq),
    ),
  );
}

Future<void> _tombstone(_Dev d, String table, String id) async {
  final st = await d.stamp.next();
  await d.db.customUpdate(
    'UPDATE $table SET deleted = 1, clock = ?, origin_device = ?, '
    'local_seq = ? WHERE id = ?',
    variables: [
      Variable.withString(st.clock),
      Variable.withString(st.originDevice),
      Variable.withInt(st.localSeq),
      Variable.withString(id),
    ],
    updates: {d.db.playlists, d.db.playlistEntries},
  );
}

/// Deletes [playlistId] as the app does: its live entries, then itself.
Future<void> _deletePlaylist(_Dev d, String playlistId) async {
  final live =
      await (d.db.select(d.db.playlistEntries)..where(
            (e) => e.playlistId.equals(playlistId) & e.deleted.equals(false),
          ))
          .get();
  for (final e in live) {
    await _tombstone(d, 'playlist_entries', e.id);
  }
  await _tombstone(d, 'playlists', playlistId);
}

Future<List<Playlist>> _livePlaylists(_Dev d) =>
    (d.db.select(d.db.playlists)..where((p) => p.deleted.equals(false))).get();

void main() {
  final root = setUpSyncDevices('songies_sync_run');
  late _Dev a;
  late _Dev b;
  final extra = <_Dev>[];

  setUp(() async {
    _stampAhead = Duration.zero;
    a = await _Dev.create(root(), 'A');
    b = await _Dev.create(root(), 'B');
    await _pair(a, b);
  });
  tearDown(() async {
    for (final d in [a, b, ...extra]) {
      await d.dispose();
    }
    extra.clear();
  });

  /// A playlist both devices have, then renamed differently on each.
  Future<String> clashingRename() async {
    final p = await _playlist(a, 'Shared');
    await _entry(a, p, await _track(a));
    _done(await _sync(a, b));
    await _rename(a, p, 'From A');
    await _rename(b, p, 'From B');
    return p;
  }

  test('first sync makes both databases equal', () async {
    final pa = await _playlist(a, 'Mine');
    await _entry(a, pa, await _track(a, title: 'One'));
    final pb = await _playlist(b, 'Theirs');
    final tb = await _track(b, title: 'Two');
    await _entry(b, pb, tb);
    await _listen(b, tb);
    await _track(b, title: 'Three');
    final bDone = b.responder.state.firstWhere((s) => s is ResponderDone);

    final events = await _sync(a, b);

    final summary = _done(events);
    expect(summary.peerName, 'B');
    expect(summary.songsAdded, 2);
    expect(summary.playlistsChanged, 1);
    expect(summary.filesCopied, 0);
    final onB = (await bDone as ResponderDone).summary;
    expect(onB.peerName, 'A');
    expect(onB.songsAdded, 1);
    expect(onB.playlistsChanged, 1);
    expect(await a.snap(), await b.snap());
    expect(await a.snap(), hasLength(8));

    final stages = [
      for (final e in events)
        if (e is SyncStep) e.stage,
    ];
    expect(stages.first, SyncStage.hello);
    expect(
      stages.toSet(),
      containsAll([
        SyncStage.pulling,
        SyncStage.merging,
        SyncStage.applying,
        SyncStage.finishing,
      ]),
    );

    final onA = await a.peer(b);
    final mirror = await b.peer(a);
    expect(onA.lastSyncAt, isNotNull);
    expect(mirror.lastSyncAt, isNotNull);
    expect(onA.lastSentSeq, mirror.lastReceivedSeq);
    expect(onA.lastReceivedSeq, mirror.lastSentSeq);
    expect(onA.lastSentSeq, greaterThan(0));
    expect(onA.lastReceivedSeq, greaterThan(0));
    expect(b.states.last, isA<ResponderDone>());
  });

  test('second sync writes nothing', () async {
    await _track(a, title: 'One');
    await _track(b, title: 'Two');
    _done(await _sync(a, b));
    final before = [await a.snap(), await a.high(), await b.high()];

    final summary = _done(await _sync(a, b));

    expect(summary.songsAdded, 0);
    expect(summary.playlistsChanged, 0);
    expect([await a.snap(), await a.high(), await b.high()], before);
    expect(await b.snap(), before.first);
  });

  test('changes travel A to B to C', () async {
    final c = await _Dev.create(root(), 'C');
    extra.add(c);
    await _pair(b, c);
    final t = await _track(a, title: 'From A');

    _done(await _sync(a, b));
    _done(await _sync(b, c));

    expect((await c.snap()).keys, contains('tracks/$t'));
    expect(await c.snap(), await a.snap());
  });

  test('first sync dedupes shared songs', () async {
    // The same video found on both devices before they ever synced.
    final ta = await _track(a, id: 'aaaa-song', video: 'vid');
    final tb = await _track(b, id: 'bbbb-song', video: 'vid');
    final pa = await _playlist(a, 'On A');
    final pb = await _playlist(b, 'On B');
    await _entry(a, pa, ta);
    await _entry(b, pb, tb);
    final bDone = b.responder.state.firstWhere((s) => s is ResponderDone);

    final summary = _done(await _sync(a, b));

    expect(summary.songsAdded, 0);
    expect(((await bDone) as ResponderDone).summary.songsAdded, 0);
    expect(await a.snap(), await b.snap());
    for (final d in [a, b]) {
      final live = await (d.db.select(
        d.db.tracks,
      )..where((t) => t.deleted.equals(false))).get();
      expect(live.map((t) => t.id), ['aaaa-song'], reason: d.name);
      final entries = await d.db.select(d.db.playlistEntries).get();
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.trackId).toSet(), {'aaaa-song'});
    }
  });

  test(
    'clash goes to choose and keepBoth makes a copy on both sides',
    () async {
      final p = await clashingRename();
      List<PlaylistClash>? asked;

      final summary = _done(
        await _sync(
          a,
          b,
          choose: (clashes) async {
            asked = clashes;
            return {p: Resolution.keepBoth};
          },
        ),
      );

      expect(asked, hasLength(1));
      expect(asked!.single.playlistId, p);
      expect(asked!.single.name, 'From A');
      expect(summary.playlistsChanged, greaterThan(0));
      expect(await a.snap(), await b.snap());
      for (final d in [a, b]) {
        final names = (await _livePlaylists(d)).map((x) => x.name).toSet();
        expect(names, {'From A', 'From B (from B)'}, reason: d.name);
      }
    },
  );

  test('clash on entries only names the playlist from the local row', () async {
    final p = await _playlist(a, 'Shared');
    final e = await _entry(a, p, await _track(a));
    _done(await _sync(a, b));
    Future<void> move(_Dev d, String pos) async {
      final st = await d.stamp.next();
      await (d.db.update(
        d.db.playlistEntries,
      )..where((x) => x.id.equals(e))).write(
        PlaylistEntriesCompanion(
          position: Value(pos),
          clock: Value(st.clock),
          originDevice: Value(st.originDevice),
          localSeq: Value(st.localSeq),
        ),
      );
    }

    await move(a, 'b0');
    await move(b, 'c0');
    List<PlaylistClash>? asked;

    _done(
      await _sync(
        a,
        b,
        choose: (clashes) async {
          asked = clashes;
          return {p: Resolution.keepTheirs};
        },
      ),
    );

    expect(asked!.single.name, 'Shared');
    expect(await a.snap(), await b.snap());
  });

  group('edits after a sync do not clash with their own echo', () {
    late String p;
    late String e1;
    setUp(() async {
      p = await _playlist(a, 'Shared');
      e1 = await _entry(a, p, await _track(a, title: 'One'));
      await _entry(a, p, await _track(a, title: 'Two'));
      _done(await _sync(a, b));
    });

    test('rename on A lands on B without asking', () async {
      await _rename(a, p, 'Renamed');

      _done(await _sync(a, b));

      expect((await _livePlaylists(b)).single.name, 'Renamed');
      expect(await a.snap(), await b.snap());
    });

    test('rename on B, synced by A, lands on A without asking', () async {
      await _rename(b, p, 'Renamed');

      _done(await _sync(a, b));

      expect((await _livePlaylists(a)).single.name, 'Renamed');
      expect(await a.snap(), await b.snap());
    });

    test('rename on A, synced by B, lands on B without asking', () async {
      await _rename(a, p, 'Renamed');

      _done(await _sync(b, a));

      expect((await _livePlaylists(b)).single.name, 'Renamed');
      expect(await a.snap(), await b.snap());
    });

    test('removing a song on A syncs without asking', () async {
      await _tombstone(a, 'playlist_entries', e1);

      _done(await _sync(a, b));

      final onB = await (b.db.select(
        b.db.playlistEntries,
      )..where((x) => x.id.equals(e1))).getSingle();
      expect(onB.deleted, isTrue);
      expect(await a.snap(), await b.snap());
    });

    test('deleting the playlist on A deletes it on B without asking', () async {
      await _deletePlaylist(a, p);

      _done(await _sync(a, b));

      expect(await _livePlaylists(b), isEmpty);
      expect(await a.snap(), await b.snap());
    });

    test('edits on each side in turn never ask', () async {
      // A minute or more between edit-and-sync rounds, so no recent stamp
      // holds a watermark back (see the report's note on safeHigh).
      Future<void> edit(_Dev d, String name) async {
        _stampAhead += SyncStamp.pendingWindow + const Duration(seconds: 1);
        await _rename(d, p, name);
      }

      for (var i = 0; i < 3; i++) {
        await edit(a, 'A $i');
        _done(await _sync(a, b));
        await edit(b, 'B $i');
        _done(await _sync(b, a));
        await edit(a, 'A2 $i');
        _done(await _sync(b, a));
        await edit(b, 'B2 $i');
        _done(await _sync(a, b));
      }
      expect((await _livePlaylists(a)).single.name, 'B2 2');
      expect(await a.snap(), await b.snap());
    });

    test('a real concurrent edit on both sides still asks', () async {
      await _rename(a, p, 'From A');
      await _rename(b, p, 'From B');
      List<PlaylistClash>? asked;

      _done(
        await _sync(
          a,
          b,
          choose: (c) async {
            asked = c;
            return {p: Resolution.keepMine};
          },
        ),
      );

      expect(asked!.single.playlistId, p);
      expect((await _livePlaylists(b)).single.name, 'From A');
      expect(await a.snap(), await b.snap());
    });
  });

  test(
    'a slow apply on the peer outlasts the normal response timeout',
    () async {
      const normal = Duration(milliseconds: 300);
      final runner = SyncRunner(
        db: a.db,
        stamp: a.stamp,
        peers: a.peers,
        myDeviceId: a.id,
        downloads: DownloadRepository(a.db),
        responseTimeout: normal,
      );
      final t = await _track(a, title: 'Big library');
      // Once rows are staged on B, keep B's database busy so its apply
      // waits well past the normal timeout.
      final busy = Completer<void>();
      final sub = b.responder.state.listen((s) {
        if (s is Receiving &&
            s.stage == SyncStage.applying &&
            !busy.isCompleted) {
          busy.complete(
            b.db.transaction(() => Future<void>.delayed(normal * 4)),
          );
        }
      });
      addTearDown(sub.cancel);

      final events = await _sync(a, b, runner: runner);

      await busy.future;
      _done(events);
      expect((await b.snap()).keys, contains('tracks/$t'));
      expect(await a.snap(), await b.snap());
      expect(b.states.last, isA<ResponderDone>());
    },
  );

  test('choose returning null cancels and changes nothing', () async {
    await clashingRename();
    await _track(b, title: 'New on B');
    final before = [await a.snap(), await b.snap()];
    final peers = (await a.peer(b), await b.peer(a));

    final events = await _sync(a, b, choose: (_) async => null);

    expect(_failure(events), SyncFailure.cancelled);
    expect([await a.snap(), await b.snap()], before);
    expect((await a.peer(b), await b.peer(a)), peers);
    expect(b.states.last, isA<Idle>());
  });

  test('cancel before apply sends abort and changes nothing', () async {
    await _track(a);
    await _track(b);
    final before = [await a.snap(), await b.snap()];
    final cancel = SyncCancel();

    final events = await a.runner
        .run(
          await a.peer(b),
          host: '127.0.0.1',
          port: b.port,
          choose: _noClashes,
          cancel: cancel,
        )
        .map((e) {
          if (e is SyncStep && e.stage == SyncStage.merging) cancel.cancel();
          return e;
        })
        .toList();

    expect(_failure(events), SyncFailure.cancelled);
    expect([await a.snap(), await b.snap()], before);
    expect(b.states.last, isA<Idle>());
  });

  test(
    'failure after pull leaves both databases and watermarks unchanged',
    () async {
      await _track(a, title: 'One');
      await _track(b, title: 'Two');
      final before = [await a.snap(), await b.snap()];
      final peers = (await a.peer(b), await b.peer(a));
      b.server.route('POST', '/apply/part', (req, _) async {
        await sendJson(req, {'error': 'server'}, status: 500);
      });

      final events = await _sync(a, b);

      expect(_failure(events), SyncFailure.network);
      expect([await a.snap(), await b.snap()], before);
      expect((await a.peer(b), await b.peer(a)), peers);
      expect(b.states.last, isA<Idle>());
    },
  );

  test('failure after the initiator applies leaves watermarks unchanged, '
      'and a rerun converges', () async {
    final ta = await _track(a, title: 'One');
    final tb = await _track(b, title: 'Two');
    final beforeB = await b.snap();
    final peers = (await a.peer(b), await b.peer(a));
    b.server.route('POST', '/apply/commit', (req, _) async {
      await sendJson(req, {'error': 'server'}, status: 500);
    });

    final events = await _sync(a, b);

    expect(_failure(events), SyncFailure.network);
    expect((await a.snap()).keys, contains('tracks/$tb'));
    expect(await b.snap(), beforeB);
    expect((await a.peer(b), await b.peer(a)), peers);

    b.responder.register(b.server); // the peer recovers
    _done(await _sync(a, b));

    expect(await a.snap(), await b.snap());
    expect((await b.snap()).keys, containsAll(['tracks/$ta', 'tracks/$tb']));
    expect(await a.snap(), hasLength(2));
  });

  test('write between pull and apply survives', () async {
    final p = await clashingRename();
    final song = await _track(a);
    _done(await _sync(a, b, choose: (_) async => {p: Resolution.keepMine}));
    await _rename(a, p, 'Again A');
    await _rename(b, p, 'Again B');
    late String onA, onB;

    _done(
      await _sync(
        a,
        b,
        choose: (_) async {
          // Music plays on both devices while the user decides.
          onA = await _listen(a, song);
          onB = await _listen(b, song);
          return {p: Resolution.keepMine};
        },
      ),
    );

    expect((await a.snap()).keys, contains('listens/$onA'));
    expect((await b.snap()).keys, contains('listens/$onB'));

    _done(await _sync(a, b));

    expect(await a.snap(), await b.snap());
    expect(
      (await a.snap()).keys,
      containsAll(['listens/$onA', 'listens/$onB']),
    );
  });

  test('clock skew of 10 minutes still syncs', () async {
    final skewed = await _Dev.create(
      root(),
      'Skewed',
      skew: const Duration(minutes: 10),
    );
    extra.add(skewed);
    await _pair(a, skewed);
    await _track(a);
    await _track(skewed);

    _done(await _sync(a, skewed));

    expect(await a.snap(), await skewed.snap());
  });

  test('abandoned session times out', () async {
    final p = await clashingRename();
    final beforeB = await b.snap();
    final asked = Completer<void>();
    final answer = Completer<Map<String, Resolution>?>();

    final run = _sync(
      a,
      b,
      choose: (_) {
        asked.complete();
        return answer.future;
      },
    );
    await asked.future;
    expect(b.states.last, isA<WaitingFor>());
    expect((b.states.last as WaitingFor).peerName, 'A');
    final idle = b.timers.made.where((t) => t.isActive).toList();
    expect(idle.map((t) => t.duration), [const Duration(minutes: 15)]);

    b.timers.fire(); // 15 minutes pass
    await pumpEventQueue();

    expect(b.states.last, isA<Idle>());
    expect(await b.snap(), beforeB);
    // The initiator comes back too late: nothing is applied anywhere.
    final beforeA = await a.snap();
    answer.complete({p: Resolution.keepMine});
    expect(_failure(await run), SyncFailure.network);
    expect(await a.snap(), beforeA);
    expect(await b.snap(), beforeB);

    // The responder is unlocked.
    _done(await _sync(a, b, choose: (_) async => {p: Resolution.keepMine}));
    expect(await a.snap(), await b.snap());
  });

  test('schema mismatch fails cleanly', () async {
    await _track(a);
    await _track(b);
    final before = [await a.snap(), await b.snap()];
    b.server.route('GET', '/hello', (req, _) async {
      await sendJson(req, {
        'device_id': b.id,
        'name': b.name,
        'app_version': appVersion,
        'time_ms': DateTime.now().millisecondsSinceEpoch,
        'schema_version': syncSchemaVersion + 1,
      });
    }, open: true);

    final events = await _sync(a, b);

    expect(_failure(events), SyncFailure.schemaMismatch);
    expect([await a.snap(), await b.snap()], before);
  });

  test('busy peer fails as busy', () async {
    await clashingRename();
    final asked = Completer<void>();
    final answer = Completer<Map<String, Resolution>?>();
    final first = _sync(
      a,
      b,
      choose: (_) {
        asked.complete();
        return answer.future;
      },
    );
    await asked.future;

    // B has a session open with A, so another peer is refused.
    final c = await _Dev.create(root(), 'C');
    extra.add(c);
    await _pair(c, b);
    expect(_failure(await _sync(c, b)), SyncFailure.busy);
    // The same runner refuses a second run while one is going.
    expect(_failure(await _sync(a, b)), SyncFailure.busy);
    // A device running its own sync refuses to answer one: B, busy with A,
    // is asked by A (now a responder) - A's runner is running.
    expect(_failure(await _sync(b, a)), SyncFailure.busy);

    answer.complete(null);
    expect(_failure(await first), SyncFailure.cancelled);
  });

  test('unpaired peer fails as forgotten', () async {
    await _track(a);
    await b.peers.remove(a.id);
    final before = await a.snap();

    final events = await _sync(a, b);

    expect(_failure(events), SyncFailure.forgotten);
    expect(await a.snap(), before);
  });

  test('a peer that is not listening fails as notFound', () async {
    await b.server.stop();

    expect(_failure(await _sync(a, b)), SyncFailure.notFound);
  });

  test('unpair removes the peer on the other side', () async {
    final events = <SyncProgress>[];
    await a.runner.unpair(await a.peer(b), host: '127.0.0.1', port: b.port);
    events.addAll(await _sync(a, b));

    expect(await b.peers.byId(a.id), isNull);
    expect(_failure(events), SyncFailure.forgotten);
  });

  test('hello answers unsigned with time and versions', () async {
    final before = DateTime.now().millisecondsSinceEpoch;
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    addTearDown(() => client.close(force: true));
    final req = await client.getUrl(
      Uri.parse('https://127.0.0.1:${b.port}/hello'),
    );
    final res = await req.close();
    final body =
        jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;

    expect(res.statusCode, 200);
    expect(body['device_id'], b.id);
    expect(body['name'], 'B');
    expect(body['app_version'], appVersion);
    expect(body['schema_version'], syncSchemaVersion);
    expect(body['time_ms'] as int, greaterThanOrEqualTo(before));
  });

  test('a stamped row not yet written holds the watermark and is sent once '
      'it lands', () async {
    final pending = await a.stamp.next(); // the scanner, mid-write
    await _track(a, title: 'Lands first');

    _done(await _sync(a, b));

    expect((await a.peer(b)).lastSentSeq, lessThan(pending.localSeq));
    expect((await b.peer(a)).lastReceivedSeq, lessThan(pending.localSeq));
    await a.db
        .into(a.db.tracks)
        .insert(
          trackRow(
            id: pending.id,
            clock: pending.clock,
            originDevice: pending.originDevice,
            localSeq: pending.localSeq,
          ),
        );
    _done(await _sync(a, b));

    expect((await b.snap()).keys, contains('tracks/${pending.id}'));
    expect(await a.snap(), await b.snap());
  });

  group('sessions', () {
    late _Dev c;
    setUp(() async {
      c = await _Dev.create(root(), 'C');
      extra.add(c);
      await _pair(c, b);
    });

    Future<SyncClient> client(_Dev from) async {
      final p = await from.peer(b);
      final cl = SyncClient.pinned(
        host: '127.0.0.1',
        port: b.port,
        fingerprint: p.certFingerprint,
        pairKey: base64.decode(p.pairKey),
        myDeviceId: from.id,
      );
      addTearDown(cl.close);
      return cl;
    }

    Matcher refused(String code) => throwsA(
      isA<SyncNetError>()
          .having((e) => e.status, 'status', 409)
          .having((e) => e.message, 'message', code),
    );

    test('another peer or a stale or wrong sync_id gets no_session', () async {
      final fromA = await client(a);
      final fromC = await client(c);
      await fromA.postJson('/session/begin', {'sync_id': 's1'});
      final high = (await fromA.getJson('/changes?since=0'))['high'] as int;
      // A starts over: s1 is now stale.
      await fromA.postJson('/session/begin', {'sync_id': 's2'});

      final steps = <String, Map<String, Object?> Function(String)>{
        '/apply/part': (id) => {'sync_id': id, 'rows': <Object>[]},
        '/apply/commit': (id) => {'sync_id': id},
        '/commit': (id) => {
          'sync_id': id,
          'initiator_high': 0,
          'responder_high': high,
        },
      };
      for (final MapEntry(key: path, value: body) in steps.entries) {
        expect(fromC.postJson(path, body('s2')), refused('no_session'));
        expect(fromA.postJson(path, body('wrong')), refused('no_session'));
        expect(fromA.postJson(path, body('s1')), refused('no_session'));
      }
      // The live session still works.
      await fromA.postJson('/apply/commit', {'sync_id': 's2'});
    });

    test(
      'a begin from the session owner replaces it; another peer is busy',
      () async {
        final fromA = await client(a);
        await fromA.postJson('/session/begin', {'sync_id': 's1'});
        await fromA.postJson('/session/begin', {'sync_id': 's2'});

        await expectLater(
          (await client(c)).postJson('/session/begin', {'sync_id': 's3'}),
          refused('busy'),
        );
        await fromA.postJson('/apply/commit', {'sync_id': 's2'});
      },
    );

    test('commit is refused without a pull or with another high', () async {
      final fromA = await client(a);
      await fromA.postJson('/session/begin', {'sync_id': 's1'});
      Future<void> commit(int high) => fromA.postJson('/commit', {
        'sync_id': 's1',
        'initiator_high': 0,
        'responder_high': high,
      });

      await expectLater(commit(0), refused('high_mismatch'));
      final high = (await fromA.getJson('/changes?since=0'))['high'] as int;
      await expectLater(commit(high + 1), refused('high_mismatch'));
      expect((await b.peer(a)).lastSyncAt, isNull);

      await commit(high);
      expect((await b.peer(a)).lastSyncAt, isNotNull);
    });
  });

  test('cancelling the progress subscription cancels the run', () async {
    final p = await clashingRename();
    final before = [await a.snap(), await b.snap()];
    final asked = Completer<void>();
    final answer = Completer<Map<String, Resolution>?>();
    final idle = b.responder.state.firstWhere((s) => s is Idle);

    final sub = a.runner
        .run(
          await a.peer(b),
          host: '127.0.0.1',
          port: b.port,
          choose: (_) {
            asked.complete();
            return answer.future;
          },
        )
        .listen(null);
    await asked.future;
    await sub.cancel();
    answer.complete({p: Resolution.keepMine});

    await idle; // the run sent /session/abort
    expect([await a.snap(), await b.snap()], before);
    await pumpEventQueue();
    expect(a.runner.running, isFalse);
  });
}
