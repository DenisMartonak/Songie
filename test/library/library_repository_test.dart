import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late LibraryRepository repo;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    repo = LibraryRepository(db, stamp);
  });
  tearDown(() => db.close());

  Future<void> insertTracks(List<String> ids) async {
    for (final id in ids) {
      await db.insertTrack(trackRow(id: id, durationMs: 1000));
    }
  }

  String ok(Result<String> r) => (r as Ok<String>).value;

  FailureKind failureOf(Result<Object?> r) => (r as Err<Object?>).failure.kind;

  Future<String> newPlaylist([String name = 'P']) async =>
      ok(await repo.createPlaylist(name));

  Future<List<PlaylistTrack>> tracksOf(String playlistId) =>
      repo.watchPlaylistTracks(playlistId).first;

  Future<List<String>> trackIdsOf(String playlistId) async => [
    for (final e in await tracksOf(playlistId)) e.track.id,
  ];

  Future<PlaylistEntry> entryRow(String id) => (db.select(
    db.playlistEntries,
  )..where((e) => e.id.equals(id))).getSingle();

  group('createPlaylist', () {
    test('trims the name and starts empty with source local', () async {
      final result = await repo.createPlaylist('  Gym Mix ');
      expect(result, isA<Ok<String>>());
      final list = await repo.watchPlaylists().first;
      expect(list, hasLength(1));
      expect(list.single.id, ok(result));
      expect(list.single.name, 'Gym Mix');
      expect(list.single.trackCount, 0);
      expect(list.single.durationMs, 0);
      expect(list.single.source, 'local');
      expect(list.single.coverRef, isNull);
    });

    test('rejects empty, blank and over-long names', () async {
      expect(
        failureOf(await repo.createPlaylist('')),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.createPlaylist('   ')),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.createPlaylist('x' * 101)),
        FailureKind.invalidInput,
      );
      expect(await repo.watchPlaylists().first, isEmpty);
    });

    test('accepts a 100 character name', () async {
      expect(await repo.createPlaylist('x' * 100), isA<Ok<String>>());
    });

    test('stamps the new row', () async {
      final id = await newPlaylist();
      final row = await (db.select(
        db.playlists,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.originDevice, stamp.deviceId);
      expect(row.localSeq, greaterThan(0));
      expect(row.clock, isNotEmpty);
      expect(row.deleted, isFalse);
    });
  });

  group('watchPlaylists', () {
    test('a burst of writes re-runs the summaries a few times, not once per '
        'write, and ends on the last state', () async {
      final seen = <int>[];
      final sub = watchPlaylistSummaries(
        db,
        every: const Duration(milliseconds: 100),
      ).listen((l) => seen.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, [0]);
      // A scan: a write per file, quickly.
      for (var i = 0; i < 40; i++) {
        await db.insertTrack(trackRow(id: 't$i'));
        await newPlaylist('P$i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await sub.cancel();
      expect(seen.length, lessThan(10));
      expect(seen.last, 40);
    });

    test('a single write still shows at once', () async {
      final seen = <int>[];
      final sub = watchPlaylistSummaries(
        db,
        every: const Duration(seconds: 10),
      ).listen((l) => seen.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await newPlaylist('P');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen, [0, 1]);
    });

    test('sorts by name case-insensitively and hides deleted', () async {
      await newPlaylist('banana');
      await newPlaylist('Apple');
      final gone = await newPlaylist('cherry');
      await newPlaylist('Date');
      await repo.deletePlaylist(gone);
      final names = [for (final p in await repo.watchPlaylists().first) p.name];
      expect(names, ['Apple', 'banana', 'Date']);
    });

    test('counts live entries with live tracks and sums duration', () async {
      await db.insertTrack(trackRow(id: 'a', durationMs: 1000));
      await db.insertTrack(trackRow(id: 'b', durationMs: 2500));
      await db.insertTrack(trackRow(id: 'c', durationMs: 4000));
      final p = await newPlaylist();
      await repo.addTracks(p, ['a', 'b', 'c', 'a']);
      var s = (await repo.watchPlaylists().first).single;
      expect(s.trackCount, 4);
      expect(s.durationMs, 1000 + 2500 + 4000 + 1000);

      final entries = await tracksOf(p);
      await repo.removeEntry(entries[1].entryId); // b
      await (db.update(db.tracks)..where((t) => t.id.equals('c'))).write(
        const TracksCompanion(deleted: Value(true)),
      );
      s = (await repo.watchPlaylists().first).single;
      expect(s.trackCount, 2);
      expect(s.durationMs, 2000);
    });

    test('coverRef falls back to the first track artworkRef', () async {
      await db.insertTrack(trackRow(id: 'a'));
      await db.insertTrack(trackRow(id: 'b'));
      await (db.update(db.tracks)..where((t) => t.id.equals('a'))).write(
        const TracksCompanion(artworkRef: Value('art/a.jpg')),
      );
      final p = await newPlaylist();
      await repo.addTracks(p, ['a', 'b']);
      expect((await repo.watchPlaylists().first).single.coverRef, 'art/a.jpg');

      await (db.update(db.playlists)..where((r) => r.id.equals(p))).write(
        const PlaylistsCompanion(coverRef: Value('art/own.jpg')),
      );
      expect(
        (await repo.watchPlaylists().first).single.coverRef,
        'art/own.jpg',
      );
    });

    test('emits again when playlists change', () async {
      final emissions = <List<String>>[];
      final sub = repo.watchPlaylists().listen(
        (l) => emissions.add([for (final p in l) p.name]),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await newPlaylist('One');
      await pumpEventQueue();
      expect(emissions.last, ['One']);
    });
  });

  group('setPlaylistCover', () {
    test('sets and clears the cover, re-stamping each time', () async {
      final p = await newPlaylist('Mix');
      final before = await (db.select(db.playlists)).getSingle();
      expect(
        await repo.setPlaylistCover(p, 'yt2-${'a' * 64}.jpg'),
        isA<Ok<void>>(),
      );
      final set = await (db.select(db.playlists)).getSingle();
      expect(set.coverRef, 'yt2-${'a' * 64}.jpg');
      expect(set.localSeq, greaterThan(before.localSeq));

      expect(await repo.setPlaylistCover(p, null), isA<Ok<void>>());
      final cleared = await (db.select(db.playlists)).getSingle();
      expect(cleared.coverRef, isNull);
      expect(cleared.localSeq, greaterThan(set.localSeq));
    });

    test('the summary shows the own cover and says so', () async {
      final p = await newPlaylist('Mix');
      expect((await repo.watchPlaylists().first).single.hasOwnCover, isFalse);
      await repo.setPlaylistCover(p, 'yt2-${'b' * 64}.jpg');
      final summary = (await repo.watchPlaylists().first).single;
      expect(summary.coverRef, 'yt2-${'b' * 64}.jpg');
      expect(summary.hasOwnCover, isTrue);
    });

    test('unknown or deleted playlists are notFound', () async {
      expect(
        failureOf(await repo.setPlaylistCover('nope', null)),
        FailureKind.notFound,
      );
      final p = await newPlaylist();
      await repo.deletePlaylist(p);
      expect(
        failureOf(await repo.setPlaylistCover(p, null)),
        FailureKind.notFound,
      );
    });
  });

  group('renamePlaylist', () {
    test('renames, trims and re-stamps', () async {
      final p = await newPlaylist('Old');
      final before = await (db.select(db.playlists)).getSingle();
      expect(await repo.renamePlaylist(p, ' New '), isA<Ok<void>>());
      final after = await (db.select(db.playlists)).getSingle();
      expect(after.name, 'New');
      expect(after.localSeq, greaterThan(before.localSeq));
      expect(after.clock.compareTo(before.clock), greaterThan(0));
      expect(after.originDevice, stamp.deviceId);
    });

    test('unknown id is notFound; bad name is invalidInput', () async {
      expect(
        failureOf(await repo.renamePlaylist('nope', 'x')),
        FailureKind.notFound,
      );
      final p = await newPlaylist();
      expect(
        failureOf(await repo.renamePlaylist(p, '')),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.renamePlaylist(p, 'x' * 101)),
        FailureKind.invalidInput,
      );
    });

    test('a deleted playlist cannot be renamed', () async {
      final p = await newPlaylist();
      await repo.deletePlaylist(p);
      expect(
        failureOf(await repo.renamePlaylist(p, 'x')),
        FailureKind.notFound,
      );
    });
  });

  group('addTracks', () {
    test('appends in order with strictly ascending positions', () async {
      await insertTracks(['t1', 't2', 't3', 't4']);
      final p = await newPlaylist();
      expect(await repo.addTracks(p, ['t1', 't2', 't3']), isA<Ok<void>>());
      var entries = await tracksOf(p);
      expect([for (final e in entries) e.track.id], ['t1', 't2', 't3']);
      for (var i = 1; i < entries.length; i++) {
        expect(entries[i].position.compareTo(entries[i - 1].position), 1);
      }
      expect(entries.every((e) => e.status == 'active'), isTrue);

      await repo.addTracks(p, ['t4']);
      entries = await tracksOf(p);
      expect([for (final e in entries) e.track.id], ['t1', 't2', 't3', 't4']);
      expect(entries[3].position.compareTo(entries[2].position), 1);
    });

    test('allows the same track twice', () async {
      await insertTracks(['t1']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't1']);
      await repo.addTracks(p, ['t1']);
      final entries = await tracksOf(p);
      expect(entries, hasLength(3));
      expect({for (final e in entries) e.entryId}, hasLength(3));
    });

    test('each inserted row has its own stamp', () async {
      await insertTracks(['t1', 't2', 't3']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2', 't3']);
      final rows = await db.select(db.playlistEntries).get();
      expect({for (final r in rows) r.localSeq}, hasLength(3));
      expect({for (final r in rows) r.clock}, hasLength(3));
      expect(rows.every((r) => r.originDevice == stamp.deviceId), isTrue);
    });

    test('unknown playlist is notFound', () async {
      await insertTracks(['t1']);
      expect(
        failureOf(await repo.addTracks('nope', ['t1'])),
        FailureKind.notFound,
      );
    });

    test('unknown track writes nothing', () async {
      await insertTracks(['t1']);
      final p = await newPlaylist();
      expect(
        failureOf(await repo.addTracks(p, ['t1', 'ghost'])),
        FailureKind.notFound,
      );
      expect(await db.select(db.playlistEntries).get(), isEmpty);
    });

    test('empty list is a no-op', () async {
      final p = await newPlaylist();
      expect(await repo.addTracks(p, const []), isA<Ok<void>>());
      expect(await db.select(db.playlistEntries).get(), isEmpty);
    });

    test(
      'appends after the last live entry only in its own playlist',
      () async {
        await insertTracks(['t1', 't2']);
        final p = await newPlaylist('P');
        final q = await newPlaylist('Q');
        await repo.addTracks(p, ['t1']);
        await repo.addTracks(q, ['t2']);
        await repo.addTracks(p, ['t2']);
        expect(await trackIdsOf(p), ['t1', 't2']);
        expect(await trackIdsOf(q), ['t2']);
      },
    );
  });

  group('watchPlaylistTracks', () {
    test('flags tracks whose local file is missing', () async {
      await insertTracks(['t1', 't2', 't3']);
      Future<void> file(String id, String state) => db
          .into(db.localFiles)
          .insertOnConflictUpdate(
            LocalFilesCompanion.insert(
              trackId: id,
              path: '/music/$id.mp3',
              state: state,
              bytes: 1,
              mtimeMs: 1,
            ),
          );
      await file('t1', 'done');
      await file('t2', 'missing');
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2', 't3']);
      final entries = await tracksOf(p);
      expect([for (final e in entries) e.fileMissing], [false, true, false]);
    });

    test('reacts to writes', () async {
      await insertTracks(['t1', 't2']);
      final p = await newPlaylist();
      final seen = <int>[];
      final sub = repo.watchPlaylistTracks(p).listen((l) => seen.add(l.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await repo.addTracks(p, ['t1', 't2']);
      await pumpEventQueue();
      expect(seen.last, 2);
    });
  });

  group('moveEntry', () {
    late String p;
    late List<String> e;

    setUp(() async {
      await insertTracks(['t1', 't2', 't3']);
      p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2', 't3']);
      e = [for (final x in await tracksOf(p)) x.entryId];
    });

    test('moves to the start and only touches the moved row', () async {
      final before1 = await entryRow(e[0]);
      final before2 = await entryRow(e[1]);
      final before3 = await entryRow(e[2]);

      final r = await repo.moveEntry(
        e[2],
        afterEntryId: null,
        beforeEntryId: e[0],
      );
      expect(r, isA<Ok<void>>());
      expect(await trackIdsOf(p), ['t3', 't1', 't2']);

      final after1 = await entryRow(e[0]);
      final after2 = await entryRow(e[1]);
      final after3 = await entryRow(e[2]);
      expect(after1.localSeq, before1.localSeq);
      expect(after2.localSeq, before2.localSeq);
      expect(after1.position, before1.position);
      expect(after2.position, before2.position);
      expect(after3.localSeq, greaterThan(before3.localSeq));
      expect(after3.clock.compareTo(before3.clock), greaterThan(0));
      expect(after3.originDevice, stamp.deviceId);
    });

    test('moves between two neighbours', () async {
      await repo.moveEntry(e[0], afterEntryId: e[1], beforeEntryId: e[2]);
      expect(await trackIdsOf(p), ['t2', 't1', 't3']);
    });

    test('moves to the end', () async {
      await repo.moveEntry(e[0], afterEntryId: e[2]);
      expect(await trackIdsOf(p), ['t2', 't3', 't1']);
    });

    test('unknown or removed entry is notFound', () async {
      expect(
        failureOf(await repo.moveEntry('nope', beforeEntryId: e[0])),
        FailureKind.notFound,
      );
      await repo.removeEntry(e[0]);
      expect(
        failureOf(await repo.moveEntry(e[0], afterEntryId: e[1])),
        FailureKind.notFound,
      );
    });

    test('neighbours must be live entries of the same playlist', () async {
      await insertTracks(['t9']);
      final other = await newPlaylist('Other');
      await repo.addTracks(other, ['t9']);
      final otherEntry = (await tracksOf(other)).single.entryId;

      expect(
        failureOf(await repo.moveEntry(e[0], afterEntryId: otherEntry)),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.moveEntry(e[0], beforeEntryId: 'nope')),
        FailureKind.invalidInput,
      );
      await repo.removeEntry(e[1]);
      expect(
        failureOf(await repo.moveEntry(e[0], afterEntryId: e[1])),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.moveEntry(e[0], afterEntryId: e[0])),
        FailureKind.invalidInput,
      );
      expect(await trackIdsOf(p), ['t1', 't3']);
    });

    test('neighbours in the wrong order are invalidInput', () async {
      expect(
        failureOf(
          await repo.moveEntry(e[0], afterEntryId: e[2], beforeEntryId: e[1]),
        ),
        FailureKind.invalidInput,
      );
      expect(await trackIdsOf(p), ['t1', 't2', 't3']);
    });
  });

  group('trackIdsIn', () {
    test('the tracks a playlist holds now, not removed ones', () async {
      await insertTracks(['t1', 't2', 't3']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2', 't3']);
      final e = [for (final x in await tracksOf(p)) x.entryId];
      await repo.removeEntry(e[1]);
      expect(await repo.trackIdsIn(p), {'t1', 't3'});
      expect(await repo.trackIdsIn('nope'), isEmpty);
    });
  });

  group('removeEntry', () {
    test('tombstones the row and hides it', () async {
      await insertTracks(['t1', 't2', 't3']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2', 't3']);
      final e = [for (final x in await tracksOf(p)) x.entryId];
      final before = await entryRow(e[1]);

      expect(await repo.removeEntry(e[1]), isA<Ok<void>>());

      final row = await entryRow(e[1]);
      expect(row.deleted, isTrue);
      expect(row.localSeq, greaterThan(before.localSeq));
      expect(row.originDevice, stamp.deviceId);
      expect(row.clock.compareTo(before.clock), greaterThan(0));
      expect(await trackIdsOf(p), ['t1', 't3']);
    });

    test('unknown or already removed id is notFound', () async {
      expect(failureOf(await repo.removeEntry('nope')), FailureKind.notFound);
      await insertTracks(['t1']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1']);
      final e = (await tracksOf(p)).single.entryId;
      await repo.removeEntry(e);
      expect(failureOf(await repo.removeEntry(e)), FailureKind.notFound);
    });
  });

  group('deletePlaylist', () {
    test('tombstones the playlist and all its entries, each stamped', () async {
      await insertTracks(['t1', 't2', 't3']);
      final p = await newPlaylist('Doomed');
      final keep = await newPlaylist('Keep');
      await repo.addTracks(p, ['t1', 't2', 't3']);
      await repo.addTracks(keep, ['t1']);
      final e = [for (final x in await tracksOf(p)) x.entryId];
      await repo.removeEntry(e[0]);
      final seqBefore = {
        for (final r in await db.select(db.playlistEntries).get())
          r.id: r.localSeq,
      };
      final playlistSeqBefore = (await (db.select(
        db.playlists,
      )..where((r) => r.id.equals(p))).getSingle()).localSeq;

      expect(await repo.deletePlaylist(p), isA<Ok<void>>());

      final playlist = await (db.select(
        db.playlists,
      )..where((r) => r.id.equals(p))).getSingle();
      expect(playlist.deleted, isTrue);
      expect(playlist.originDevice, stamp.deviceId);
      expect(playlist.localSeq, greaterThan(playlistSeqBefore));

      final entries = await (db.select(
        db.playlistEntries,
      )..where((r) => r.playlistId.equals(p))).get();
      expect(entries, hasLength(3));
      expect(entries.every((r) => r.deleted), isTrue);
      // The already-removed entry was not touched again.
      expect(entries.firstWhere((r) => r.id == e[0]).localSeq, seqBefore[e[0]]);
      final touched = entries.where((r) => r.id != e[0]).toList();
      for (final r in touched) {
        expect(r.localSeq, greaterThan(seqBefore[r.id]!));
        expect(r.originDevice, stamp.deviceId);
      }
      expect({for (final r in touched) r.localSeq}, hasLength(2));

      final names = [for (final s in await repo.watchPlaylists().first) s.name];
      expect(names, ['Keep']);
      expect(await trackIdsOf(keep), ['t1']);
      expect(await trackIdsOf(p), isEmpty);
    });

    test('unknown id is notFound', () async {
      expect(
        failureOf(await repo.deletePlaylist('nope')),
        FailureKind.notFound,
      );
    });
  });

  group('replaceEntryTrack', () {
    test('points the entry at the new track and re-stamps only it', () async {
      await insertTracks(['t1', 't2', 't3']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1', 't2']);
      final before = await tracksOf(p);
      final untouchedBefore = await entryRow(before[1].entryId);
      final movedBefore = await entryRow(before[0].entryId);

      expect(
        await repo.replaceEntryTrack(before[0].entryId, 't3'),
        isA<Ok<void>>(),
      );

      expect(await trackIdsOf(p), ['t3', 't2']);
      final after = await tracksOf(p);
      expect(after[0].entryId, before[0].entryId);
      expect(after[0].position, before[0].position);
      final moved = await entryRow(before[0].entryId);
      expect(moved.localSeq, greaterThan(movedBefore.localSeq));
      expect(moved.clock.compareTo(movedBefore.clock), greaterThan(0));
      expect(moved.originDevice, stamp.deviceId);
      expect(
        (await entryRow(before[1].entryId)).localSeq,
        untouchedBefore.localSeq,
      );
    });

    test('unknown or deleted entry is notFound', () async {
      await insertTracks(['t1', 't2']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1']);
      final entry = (await tracksOf(p)).single.entryId;
      expect(
        failureOf(await repo.replaceEntryTrack('nope', 't2')),
        FailureKind.notFound,
      );
      await repo.removeEntry(entry);
      expect(
        failureOf(await repo.replaceEntryTrack(entry, 't2')),
        FailureKind.notFound,
      );
    });

    test('unknown or deleted track is notFound and changes nothing', () async {
      await insertTracks(['t1', 't2']);
      final p = await newPlaylist();
      await repo.addTracks(p, ['t1']);
      final entry = (await tracksOf(p)).single.entryId;
      expect(
        failureOf(await repo.replaceEntryTrack(entry, 'nope')),
        FailureKind.notFound,
      );
      await (db.update(db.tracks)..where((t) => t.id.equals('t2'))).write(
        const TracksCompanion(deleted: Value(true)),
      );
      expect(
        failureOf(await repo.replaceEntryTrack(entry, 't2')),
        FailureKind.notFound,
      );
      expect(await trackIdsOf(p), ['t1']);
    });
  });

  group('trackById', () {
    test('returns the track or null', () async {
      await insertTracks(['t1']);
      expect((await repo.trackById('t1'))?.id, 't1');
      expect(await repo.trackById('nope'), isNull);
    });
  });

  group('tracksByIds', () {
    test('returns live rows only', () async {
      await insertTracks(['t1', 't2', 't3']);
      await (db.update(db.tracks)..where((t) => t.id.equals('t2'))).write(
        const TracksCompanion(deleted: Value(true)),
      );
      final found = await repo.tracksByIds(['t1', 't2', 't3', 'nope', 't1']);
      expect(found.keys.toSet(), {'t1', 't3'});
      expect(found['t3']?.id, 't3');
      expect(await repo.tracksByIds(const []), isEmpty);
    });
  });

  test('database errors become Err(io) instead of throwing', () async {
    await db.customStatement('DROP TABLE playlists');
    final r = await repo.createPlaylist('x');
    expect(failureOf(r), FailureKind.io);
  });

  test('database errors from a background isolate become Err(io)', () async {
    // AppDatabase.open runs sqlite in a drift isolate, where failures reach
    // the caller wrapped in DriftRemoteException instead of SqliteException.
    // The shared in-memory db from setUp is open too; silence drift's warning.
    final previousWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarn,
    );
    final dir = await Directory.systemTemp.createTemp('songies_repo_test');
    final bgDb = AppDatabase.open(File('${dir.path}/test.db'));
    addTearDown(() async {
      await bgDb.close();
      await dir.delete(recursive: true);
    });
    final bgRepo = LibraryRepository(bgDb, await SyncStamp.load(bgDb));
    await bgDb.customStatement('DROP TABLE playlists');
    final r = await bgRepo.createPlaylist('x');
    expect(failureOf(r), FailureKind.io);
  });

  group('markUnavailable', () {
    Future<Track> row(String id) =>
        (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();

    test('flags the track, stamped; a second call is a no-op', () async {
      await db.insertTrack(trackRow(id: 't', localSeq: 99));
      final before = await row('t');
      expect(await repo.markUnavailable('t'), isA<Ok<void>>());
      final after = await row('t');
      expect(after.unavailable, isTrue);
      expect(after.localSeq, isNot(before.localSeq));
      expect(after.clock, isNot(before.clock));
      expect(after.originDevice, stamp.deviceId);

      await repo.markUnavailable('t');
      expect((await row('t')).localSeq, after.localSeq);
    });

    test('unknown track is notFound', () async {
      final r = await repo.markUnavailable('nope');
      expect(r, isA<Err<void>>());
    });
  });

  group('clearUnavailableYtTracks', () {
    Future<Track> row(String id) =>
        (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();

    test('unflags YouTube tracks only, stamped; then a no-op', () async {
      for (final (id, source) in [
        ('y1', 'yt'),
        ('y2', 'yt'),
        ('l1', 'local'),
      ]) {
        await db
            .into(db.tracks)
            .insert(
              trackRow(
                id: id,
                source: source,
                localSeq: 99,
              ).copyWith(unavailable: const Value(true)),
            );
      }
      final before = await row('y1');

      expect(await repo.clearUnavailableYtTracks(), _okCount(2));
      final y1 = await row('y1');
      expect(y1.unavailable, isFalse);
      expect(y1.clock, isNot(before.clock));
      expect(y1.originDevice, stamp.deviceId);
      expect((await row('y2')).unavailable, isFalse);
      expect((await row('l1')).unavailable, isTrue);

      expect(await repo.clearUnavailableYtTracks(), _okCount(0));
      expect((await row('y1')).clock, y1.clock);
    });
  });

  group('updateTrackMetadata', () {
    Future<Track> row(String id) =>
        (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();

    test('writes only changed non-null fields, stamped', () async {
      await db
          .into(db.tracks)
          .insert(
            trackRow(
              id: 't',
              title: 'Old',
              artist: 'A',
              album: 'Al',
              durationMs: 5,
              localSeq: 99,
            ),
          );
      final before = await row('t');
      final r = await repo.updateTrackMetadata(
        't',
        title: 'New',
        artist: 'A',
        album: null,
        durationMs: 5,
      );
      expect(r, isA<Ok<void>>());
      final after = await row('t');
      expect(after.title, 'New');
      expect(after.artist, 'A');
      expect(after.album, 'Al');
      expect(after.durationMs, 5);
      expect(after.searchText, contains('new'));
      expect(after.localSeq, isNot(before.localSeq));
      expect(after.clock, isNot(before.clock));
      expect(after.originDevice, stamp.deviceId);
    });

    test('does nothing when nothing changed', () async {
      await db
          .into(db.tracks)
          .insert(trackRow(id: 't', title: 'Old', artist: 'A', durationMs: 5));
      final before = await row('t');
      final seqBefore = (await stamp.next()).localSeq;
      await repo.updateTrackMetadata(
        't',
        title: 'Old',
        artist: null,
        album: null,
        durationMs: 5,
      );
      final after = await row('t');
      expect(after.clock, before.clock);
      expect(after.localSeq, before.localSeq);
      expect((await stamp.next()).localSeq, seqBefore + 1);
    });

    test('unknown track is notFound', () async {
      final r = await repo.updateTrackMetadata('nope', title: 'x');
      expect(failureOf(r), FailureKind.notFound);
    });
  });

  test('a yt track is never flagged missing (no Locate offered)', () async {
    await db
        .into(db.tracks)
        .insert(trackRow(id: 'y1', source: 'yt', ytVideoId: 'v1'));
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: 'y1',
            path: '',
            state: 'missing',
            bytes: 0,
            mtimeMs: 0,
          ),
        );
    final p = await newPlaylist();
    await repo.addTracks(p, ['y1']);
    expect((await tracksOf(p)).single.fileMissing, isFalse);
  });
}

Matcher _okCount(int n) => isA<Ok<int>>().having((r) => r.value, 'value', n);
