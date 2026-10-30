import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/sync/change_feed.dart';
import 'package:songies/sync/row_applier.dart';
import 'package:songies/sync/sync_row.dart';

import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

/// A canonical clock at [ms] for device [dev].
String clk(int ms, [String dev = 'peer']) =>
    '${ms.toString().padLeft(13, '0')}-00000-$dev';

final _at = DateTime.utc(2026, 10, 1);
final _now = DateTime.utc(2026, 10, 30);
const _nowMs = 1800000000000;

Future<void> addTrack(
  AppDatabase db,
  String id, {
  String? video,
  String? hash,
  String clock = '0000000000001-00000-dev',
  bool deleted = false,
  String? mergedInto,
  String title = 'Title',
}) => db
    .into(db.tracks)
    .insert(
      trackRow(
        id: id,
        ytVideoId: video,
        fileHash: hash,
        source: video != null ? 'yt' : 'local',
        clock: clock,
        title: title,
      ).copyWith(deleted: Value(deleted), mergedInto: Value(mergedInto)),
    );

Future<void> addPlaylist(
  AppDatabase db,
  String id, {
  String? url,
  String clock = '0000000000001-00000-dev',
}) => db
    .into(db.playlists)
    .insert(
      PlaylistsCompanion.insert(
        id: id,
        clock: clock,
        originDevice: 'dev',
        localSeq: 1,
        name: 'P $id',
        source: url == null ? 'local' : 'yt',
        ytPlaylistUrl: Value(url),
      ),
    );

Future<void> addEntry(
  AppDatabase db,
  String id,
  String playlistId,
  String trackId, {
  String clock = '0000000000001-00000-dev',
}) => db
    .into(db.playlistEntries)
    .insert(
      PlaylistEntriesCompanion.insert(
        id: id,
        clock: clock,
        originDevice: 'dev',
        localSeq: 1,
        playlistId: playlistId,
        trackId: trackId,
        position: 'a0',
        addedAt: _at,
      ),
    );

Future<void> addSeen(
  AppDatabase db,
  String id,
  String playlistId,
  String videoId,
) => db
    .into(db.ytSeen)
    .insert(
      YtSeenCompanion.insert(
        id: id,
        clock: '0000000000001-00000-dev',
        originDevice: 'dev',
        localSeq: 1,
        playlistId: playlistId,
        videoId: videoId,
      ),
    );

Future<void> addListen(
  AppDatabase db,
  String id,
  String trackId, {
  DateTime? startedAt,
}) => db
    .into(db.listens)
    .insert(
      ListensCompanion.insert(
        id: id,
        clock: '0000000000001-00000-dev',
        originDevice: 'dev',
        localSeq: 1,
        trackId: trackId,
        startedAt: startedAt ?? _at,
        heardMs: 1000,
        counted: true,
        mainArtist: 'A',
        titleSnapshot: 'T',
        artistSnapshot: 'A',
      ),
    );

Future<void> addLyrics(AppDatabase db, String trackId, String body) => db
    .into(db.lyrics)
    .insert(
      LyricsCompanion.insert(
        id: trackId,
        clock: '0000000000001-00000-dev',
        originDevice: 'dev',
        localSeq: 1,
        kind: 'plain',
        body: body,
        fetchedAt: _at,
      ),
    );

Future<void> addLocalFile(AppDatabase db, String trackId, String state) => db
    .into(db.localFiles)
    .insert(
      LocalFilesCompanion.insert(
        trackId: trackId,
        path: '/music/$trackId.mp3',
        state: state,
        bytes: 1,
        mtimeMs: 1,
      ),
    );

Future<List<SyncRow>> rowsOf(AppDatabase db) async =>
    (await ChangeFeed(db).since(0, limit: 1 << 30)).rows;

void main() {
  late AppDatabase db;
  late AppDatabase peer;
  late SyncStamp stamp;
  late RowApplier applier;

  setUpAll(() {
    // Two in-memory databases, one per device; silence drift's warning.
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous,
    );
  });

  setUp(() async {
    db = testDb();
    peer = testDb();
    stamp = await SyncStamp.load(db, nowMs: () => _nowMs);
    applier = RowApplier(db, stamp, now: () => _now);
  });
  tearDown(() async {
    await db.close();
    await peer.close();
  });

  Future<Track> track(String id) =>
      (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();
  Future<PlaylistEntry> entry(String id) => (db.select(
    db.playlistEntries,
  )..where((t) => t.id.equals(id))).getSingle();

  test('applies new rows with their clock and a fresh local_seq', () async {
    await seedOneOfEach(peer);
    final own = await stamp.next();
    await db
        .into(db.tracks)
        .insert(trackRow(id: 'mine', localSeq: own.localSeq));
    final before = await ChangeFeed(db).highSeq();
    final incoming = await rowsOf(peer);

    final report = await RowApplier(
      db,
      stamp,
      now: () => DateTime.utc(2024),
    ).apply(incoming);

    expect(report.written, 8);
    expect(report.tracksAdded, 1);
    expect(report.playlistIds, containsAll(['p2', 'p']));
    final mine = await snapshot(db);
    final theirs = await snapshot(peer);
    for (final k in theirs.keys) {
      expect(mine[k], theirs[k], reason: k);
    }
    final applied = (await rowsOf(db)).where((r) => r.id != 'mine').toList();
    expect(applied, hasLength(8));
    for (final r in applied) {
      expect(r.clock, '0000000000001-00000-dev');
      expect(r.originDevice, 'dev');
    }
    final seqs = applied.map((r) => r.localSeq).toSet();
    expect(seqs, hasLength(8));
    expect(seqs.every((s) => s > before), isTrue);
  });

  test('skips equal content and older clocks', () async {
    await addTrack(db, 'a', clock: clk(5, 'dev'));
    await addTrack(db, 'b', clock: clk(5, 'dev'));
    await addTrack(peer, 'a', clock: clk(9)); // same content, newer clock
    await addTrack(peer, 'b', clock: clk(3), title: 'Old'); // older clock
    await addTrack(peer, 'c', clock: clk(3), title: 'New');

    final report = await applier.apply(await rowsOf(peer));

    expect(report.written, 1);
    expect((await track('a')).clock, clk(5, 'dev'));
    expect((await track('b')).title, 'Title');
    expect((await track('c')).title, 'New');
  });

  test('same video under two ids merges onto the smaller id', () async {
    await addTrack(db, 'b', video: 'v');
    await addPlaylist(db, 'pl');
    await addEntry(db, 'eb', 'pl', 'b');
    await addListen(db, 'lb', 'b');
    await addLyrics(db, 'b', 'words');
    await addTrack(peer, 'a', video: 'v', clock: clk(9));

    final report = await applier.apply(await rowsOf(peer));

    final a = await track('a');
    final b = await track('b');
    expect(a.deleted, isFalse);
    expect(a.ytVideoId, 'v');
    expect(b.deleted, isTrue);
    expect(b.mergedInto, 'a');
    expect(b.ytVideoId, isNull);
    expect(b.originDevice, stamp.deviceId);
    final e = await entry('eb');
    expect(e.trackId, 'a');
    expect(e.originDevice, stamp.deviceId);
    expect((await db.select(db.listens).getSingle()).trackId, 'a');
    final lyrics = {for (final l in await db.select(db.lyrics).get()) l.id: l};
    expect(lyrics['a']!.body, 'words');
    expect(lyrics['a']!.deleted, isFalse);
    expect(lyrics['b']!.deleted, isTrue);
    expect(report.tracksAdded, 1);
  });

  test('same file hash merges and moves local_files', () async {
    await addTrack(db, 'b', hash: 'h');
    await addLocalFile(db, 'b', 'done');
    await addTrack(peer, 'a', hash: 'h', clock: clk(9));

    await applier.apply(await rowsOf(peer));

    expect((await track('b')).mergedInto, 'a');
    expect((await track('b')).fileHash, isNull);
    final files = await db.select(db.localFiles).get();
    expect(files.map((f) => (f.trackId, f.path, f.state)), [
      ('a', '/music/b.mp3', 'done'),
    ]);
  });

  test('a done file of the loser replaces a missing one', () async {
    await addTrack(db, 'a', hash: 'h');
    await addLocalFile(db, 'a', 'missing');
    await addTrack(db, 'b', hash: 'h2');
    await addLocalFile(db, 'b', 'done');
    // The peer changed b's file hash to the same as a's.
    await addTrack(peer, 'b', hash: 'h', clock: clk(9));

    await applier.apply(await rowsOf(peer));

    expect((await track('b')).mergedInto, 'a');
    final files = await db.select(db.localFiles).get();
    expect(files.map((f) => (f.trackId, f.path, f.state)), [
      ('a', '/music/b.mp3', 'done'),
    ]);
  });

  Future<void> sideOne(AppDatabase d) async {
    await addTrack(d, 't1', video: 'v1', clock: clk(9));
    await addPlaylist(d, 'p1', url: 'U', clock: clk(9));
    await addEntry(d, 'e1', 'p1', 't1', clock: clk(9));
    await addSeen(d, 's1', 'p1', 'v1');
  }

  Future<void> sideTwo(AppDatabase d) async {
    await addTrack(d, 't2', video: 'v1');
    await addTrack(d, 't4', video: 'v2');
    await addPlaylist(d, 'p2', url: 'U');
    await addEntry(d, 'e2', 'p2', 't2');
    await addEntry(d, 'e4', 'p2', 't4');
    await addSeen(d, 's2', 'p2', 'v1');
    await d
        .into(d.playlistDevicePrefs)
        .insert(
          PlaylistDevicePrefsCompanion.insert(
            playlistId: 'p2',
            downloadEnabled: const Value(true),
          ),
        );
  }

  test(
    'same YouTube playlist imported twice is joined, without doubled entries',
    () async {
      await sideTwo(db);
      await sideOne(peer);
      final fromPeer = await rowsOf(peer);
      final fromMe = await rowsOf(db);

      final report = await applier.apply(fromPeer);
      final peerStamp = await SyncStamp.load(peer, nowMs: () => _nowMs);
      await RowApplier(peer, peerStamp, now: () => _now).apply(fromMe);

      final p2 = await (db.select(
        db.playlists,
      )..where((p) => p.id.equals('p2'))).getSingle();
      expect(p2.deleted, isTrue);
      expect(p2.mergedInto, 'p1');
      final live = await (db.select(
        db.playlistEntries,
      )..where((e) => e.deleted.equals(false))).get();
      expect(live.map((e) => (e.id, e.playlistId, e.trackId)).toSet(), {
        ('e1', 'p1', 't1'),
        ('e4', 'p1', 't4'),
      });
      final seen = await (db.select(
        db.ytSeen,
      )..where((s) => s.deleted.equals(false))).get();
      expect(seen.map((s) => (s.id, s.playlistId, s.videoId)), [
        ('s1', 'p1', 'v1'),
      ]);
      final prefs = await db.select(db.playlistDevicePrefs).get();
      expect(prefs.map((p) => (p.playlistId, p.downloadEnabled)), [
        ('p1', true),
      ]);
      expect(report.playlistIds, contains('p1'));

      // Both sides end with the same content.
      expect(await snapshot(peer), await snapshot(db));
    },
  );

  test('lyrics on both sides of a merged pair end the same', () async {
    await addTrack(db, 'b', video: 'v');
    await addLyrics(db, 'b', 'Y');
    await addTrack(peer, 'a', video: 'v', clock: clk(9));
    await addLyrics(peer, 'a', 'X');
    final fromPeer = await rowsOf(peer);
    final fromMe = await rowsOf(db);

    await applier.apply(fromPeer);
    final peerStamp = await SyncStamp.load(peer, nowMs: () => _nowMs);
    await RowApplier(peer, peerStamp, now: () => _now).apply(fromMe);

    for (final d in [db, peer]) {
      final lyrics = {for (final l in await d.select(d.lyrics).get()) l.id: l};
      expect(lyrics['a']!.body, 'X');
      expect(lyrics['a']!.deleted, isFalse);
      expect(lyrics['b']!.deleted, isTrue);
    }
    expect(await snapshot(peer), await snapshot(db));
  });

  test('local playlist keeps the same song twice', () async {
    await addTrack(db, 't');
    await addPlaylist(db, 'pl');
    await addEntry(db, 'e2', 'pl', 't');
    await addEntry(peer, 'e1', 'pl', 't', clock: clk(9));

    await applier.apply(await rowsOf(peer));

    final live = await (db.select(
      db.playlistEntries,
    )..where((e) => e.deleted.equals(false))).get();
    expect(live.map((e) => e.id).toSet(), {'e1', 'e2'});
  });

  test('incoming reference to a merged track is rewritten', () async {
    await addTrack(db, 'a', video: 'v');
    await addTrack(db, 'c', deleted: true, mergedInto: 'a');
    await addTrack(db, 'b', deleted: true, mergedInto: 'c');
    await addPlaylist(db, 'pl');
    await addEntry(peer, 'e', 'pl', 'b', clock: clk(9));
    await addListen(peer, 'l', 'b');

    await applier.apply(await rowsOf(peer));

    final e = await entry('e');
    expect(e.trackId, 'a');
    expect(e.originDevice, stamp.deviceId);
    expect((await db.select(db.listens).getSingle()).trackId, 'a');
  });

  test('a merge tombstone from a peer rewrites local references', () async {
    await addTrack(db, 'b', video: 'v');
    await addPlaylist(db, 'pl');
    await addEntry(db, 'e', 'pl', 'b');
    await addTrack(peer, 'a', video: 'v', clock: clk(9));
    await addTrack(peer, 'b', deleted: true, mergedInto: 'a', clock: clk(9));

    await applier.apply(await rowsOf(peer));

    expect((await track('b')).mergedInto, 'a');
    expect((await entry('e')).trackId, 'a');
  });

  test('a deleted track holding the video id gives it up', () async {
    await addTrack(db, 'a', video: 'v', deleted: true);
    await addTrack(peer, 'b', video: 'v', clock: clk(9));

    await applier.apply(await rowsOf(peer));

    expect((await track('b')).ytVideoId, 'v');
    expect((await track('a')).ytVideoId, isNull);
    expect((await track('a')).mergedInto, isNull);
  });

  test('listen older than 730 days is skipped', () async {
    await addListen(
      peer,
      'old',
      't',
      startedAt: _now.subtract(const Duration(days: 731)),
    );
    await addListen(
      peer,
      'new',
      't',
      startedAt: _now.subtract(const Duration(days: 10)),
    );

    final report = await applier.apply(await rowsOf(peer));

    expect(report.written, 1);
    final ids = (await db.select(db.listens).get()).map((l) => l.id);
    expect(ids, ['new']);
  });

  test('applying the same rows twice writes nothing the second time', () async {
    await sideTwo(db);
    await sideOne(peer);
    final incoming = await rowsOf(peer);

    final first = await applier.apply(incoming);
    final after = await snapshot(db);
    final second = await applier.apply(incoming);

    expect(first.written, greaterThan(0));
    expect(second.written, 0);
    expect(await snapshot(db), after);
  });

  test('joins the caller transaction', () async {
    await addTrack(peer, 'a', clock: clk(9));
    final incoming = await rowsOf(peer);
    await expectLater(
      db.transaction(() async {
        await applier.apply(incoming);
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await db.select(db.tracks).get(), isEmpty);
  });
}
