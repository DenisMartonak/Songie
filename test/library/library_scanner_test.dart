import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/library/file_hasher.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/library/tag_reader.dart';

import '../helpers/test_db.dart';

class FakeTagReader implements TagReader {
  final Map<String, TrackTags> tags = {};
  final Set<String> throwFor = {};

  @override
  Future<TrackTags> read(File f) async {
    final name = p.basename(f.path);
    if (throwFor.contains(name)) throw StateError('corrupt tags in $name');
    return tags[name] ?? const TrackTags();
  }
}

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late LibraryRepository repo;
  late FakeTagReader tags;
  late Directory tmp;
  late Directory music;
  late int hashCalls;
  late int inFlight;
  late int maxInFlight;
  late Set<String> hashFails;
  late LibraryScanner scanner;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    repo = LibraryRepository(db, stamp);
    tags = FakeTagReader();
    tmp = Directory.systemTemp.createTempSync('songies_scan_');
    music = Directory(p.join(tmp.path, 'music'))..createSync();
    hashCalls = 0;
    inFlight = 0;
    maxInFlight = 0;
    hashFails = {};
    scanner = LibraryScanner(
      db,
      stamp,
      tags,
      ArtCache(Directory(p.join(tmp.path, 'art'))),
      repo,
      hasher: (f) async {
        hashCalls++;
        inFlight++;
        maxInFlight = math.max(maxInFlight, inFlight);
        try {
          if (hashFails.contains(p.basename(f.path))) {
            throw FileSystemException('cannot read', f.path);
          }
          return await sha256File(f);
        } finally {
          inFlight--;
        }
      },
    );
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Writes [name] (relative to [dir]) with content derived from [content].
  File write(String name, {String? content, Directory? dir}) {
    final f = File(p.join((dir ?? music).path, name));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(utf8.encode(content ?? 'audio:$name'));
    return f;
  }

  void writeBasicFolder() {
    write('a.mp3');
    write('B.MP3');
    write('notes.txt');
    File(p.join(music.path, 'empty.mp3')).writeAsBytesSync([]);
    write('sub/c.mp3');
  }

  Future<ScanProgress> scan(
    Directory dir, {
    String? playlist,
    bool registerFolder = true,
  }) async {
    final events = await scanner
        .scanFolder(
          dir.path,
          createPlaylistNamed: playlist,
          registerFolder: registerFolder,
        )
        .toList();
    return events.last;
  }

  Future<List<Track>> allTracks() => db.select(db.tracks).get();

  Future<LocalFile> localFileFor(String trackId) => (db.select(
    db.localFiles,
  )..where((f) => f.trackId.equals(trackId))).getSingle();

  Uint8List pngBytes() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

  String numbered(int i) => 't${i.toString().padLeft(3, "0")}.mp3';

  group('scanFolder', () {
    test('matches .mp3 case-insensitively, skips empty files', () async {
      writeBasicFolder();
      final last = await scan(music);
      expect(last.done, isTrue);
      expect(last.found, 4);
      expect(last.added, 3);
      expect(last.skipped, 1);
      expect(last.unchanged, 0);
      expect(last.processed, 4);
      final rows = await allTracks();
      expect(rows, hasLength(3));
      expect(rows.every((t) => t.source == 'local'), isTrue);
      expect(rows.every((t) => t.fileHash != null), isTrue);
      final locals = await db.select(db.localFiles).get();
      expect(locals, hasLength(3));
      expect(locals.every((l) => l.state == 'done'), isTrue);
    });

    test('stores tags, duration, artwork and search text', () async {
      write('a.mp3');
      tags.tags['a.mp3'] = TrackTags(
        title: 'Song',
        artist: 'Band',
        album: 'LP',
        duration: const Duration(seconds: 200),
        picture: pngBytes(),
      );
      await scan(music);
      final t = (await allTracks()).single;
      expect(t.title, 'Song');
      expect(t.artist, 'Band');
      expect(t.album, 'LP');
      expect(t.durationMs, 200000);
      expect(t.artworkRef, isNotNull);
      expect(t.searchText, 'song band lp');
      expect(t.clock, isNotEmpty);
      expect(t.originDevice, stamp.deviceId);
      final local = await localFileFor(t.id);
      expect(local.path, p.join(music.path, 'a.mp3'));
      expect(local.bytes, utf8.encode('audio:a.mp3').length);
    });

    test('falls back to the filename when the tag read throws', () async {
      write('Daft Punk - One More Time.mp3');
      write('weird_名前.mp3');
      tags.throwFor
        ..add('Daft Punk - One More Time.mp3')
        ..add('weird_名前.mp3');
      final last = await scan(music);
      expect(last.added, 2);
      expect(last.skipped, 0);
      final byTitle = {for (final t in await allTracks()) t.title: t};
      expect(byTitle['One More Time']!.artist, 'Daft Punk');
      expect(byTitle['weird_名前']!.artist, 'Unknown artist');
    });

    test('falls back to the filename for blank tag fields', () async {
      write('Artist X - Title Y.mp3');
      tags.tags['Artist X - Title Y.mp3'] = const TrackTags(title: '  ');
      await scan(music);
      final t = (await allTracks()).single;
      expect(t.title, 'Title Y');
      expect(t.artist, 'Artist X');
    });

    test('rescan reports unchanged without hashing again', () async {
      writeBasicFolder();
      await scan(music);
      final hashesAfterFirst = hashCalls;
      expect(hashesAfterFirst, 3);
      final last = await scan(music);
      expect(last.unchanged, 3);
      expect(last.added, 0);
      expect(last.skipped, 1);
      expect(hashCalls, hashesAfterFirst);
      expect(await allTracks(), hasLength(3));
    });

    test('same bytes in a second folder do not create duplicates', () async {
      writeBasicFolder();
      await scan(music);
      final copy = Directory(p.join(tmp.path, 'copy'))..createSync();
      // Same content as the originals (write() derives it from the name).
      write('a.mp3', dir: copy);
      write('B.MP3', dir: copy);
      write('sub/c.mp3', dir: copy);
      final last = await scan(copy);
      expect(last.added, 0);
      expect(last.unchanged, 3);
      final rows = await allTracks();
      expect(rows, hasLength(3));
      expect(rows.map((t) => t.fileHash).toSet(), hasLength(3));
      // First path wins: the original LocalFiles rows are untouched.
      final locals = await db.select(db.localFiles).get();
      expect(locals.every((l) => l.path.startsWith(music.path)), isTrue);
    });

    test('a moved file keeps its track and repoints the local file', () async {
      final f = write('a.mp3');
      await scan(music);
      final trackId = (await allTracks()).single.id;
      final other = Directory(p.join(tmp.path, 'other'))..createSync();
      f.renameSync(p.join(other.path, 'a.mp3'));
      final last = await scan(other);
      expect(last.added, 0);
      expect(await allTracks(), hasLength(1));
      final local = await localFileFor(trackId);
      expect(local.path, p.join(other.path, 'a.mp3'));
      expect(local.state, 'done');
    });

    test('same path, new content keeps the track id, updates tags and hash, '
        'playlist entry not missing', () async {
      final f = write('a.mp3', content: 'old audio');
      tags.tags['a.mp3'] = const TrackTags(title: 'Old', artist: 'Band');
      await scan(music);
      final before = (await allTracks()).single;
      final playlistId =
          ((await repo.createPlaylist('Mix')) as Ok<String>).value;
      await repo.addTracks(playlistId, [before.id]);

      // A tagger rewrites the file: new bytes, new tags.
      f.writeAsBytesSync(utf8.encode('old audio with retagged header'));
      tags.tags['a.mp3'] = const TrackTags(
        title: 'New Title',
        artist: 'Beyoncé',
        album: 'Album',
        duration: Duration(seconds: 90),
      );
      final last = await scan(music);

      expect(last.added, 0);
      expect(last.unchanged, 1);
      final after = (await allTracks()).single;
      expect(after.id, before.id);
      expect(after.fileHash, isNot(before.fileHash));
      expect(after.title, 'New Title');
      expect(after.artist, 'Beyoncé');
      expect(after.album, 'Album');
      expect(after.durationMs, 90000);
      expect(after.searchText, contains('beyonce'));
      expect(after.clock.compareTo(before.clock), greaterThan(0));
      expect(after.localSeq, greaterThan(before.localSeq));
      final local = await localFileFor(before.id);
      expect(local.state, 'done');
      expect(local.bytes, f.lengthSync());
      expect(await db.select(db.localFiles).get(), hasLength(1));
      final entries = await repo.watchPlaylistTracks(playlistId).first;
      expect(entries.single.track.id, before.id);
      expect(entries.single.fileMissing, isFalse);
    });

    test('same path, content that is another track keeps deduping', () async {
      final a = write('a.mp3', content: 'first');
      write('b.mp3', content: 'second');
      await scan(music);
      final ids = {for (final t in await allTracks()) t.title: t.id};
      // a.mp3 now holds exactly what b.mp3 holds.
      a.writeAsBytesSync(utf8.encode('second'));
      final last = await scan(music);
      expect(last.added, 0);
      expect(await allTracks(), hasLength(2));
      expect((await localFileFor(ids['a']!)).state, 'missing');
      expect((await localFileFor(ids['b']!)).state, 'done');
    });

    test('files that disappear are marked missing, and come back', () async {
      writeBasicFolder();
      await scan(music);
      final gone = File(p.join(music.path, 'a.mp3'));
      final bytes = gone.readAsBytesSync();
      gone.deleteSync();
      await scan(music);
      final locals = await db.select(db.localFiles).get();
      final byPath = {for (final l in locals) l.path: l};
      expect(byPath[gone.path]!.state, 'missing');
      expect(locals.where((l) => l.state == 'missing'), hasLength(1));

      gone.writeAsBytesSync(bytes);
      final last = await scan(music);
      expect(last.added, 0);
      expect(await allTracks(), hasLength(3));
      final again = await db.select(db.localFiles).get();
      expect(again.every((l) => l.state == 'done'), isTrue);
    });

    test('only rows under the scanned folder are marked missing', () async {
      write('a.mp3');
      final elsewhere = Directory(p.join(tmp.path, 'elsewhere'))..createSync();
      final e = write('e.mp3', dir: elsewhere);
      await scan(music);
      await scan(elsewhere);
      e.deleteSync();
      await scan(music);
      final locals = await db.select(db.localFiles).get();
      expect(locals.every((l) => l.state == 'done'), isTrue);
    });

    test(
      'createPlaylistNamed adds every scanned track in path order',
      () async {
        writeBasicFolder();
        await scan(music);
        // Rescan: unchanged tracks are included too.
        await scan(music, playlist: 'My Folder');
        final lists = await repo.watchPlaylists().first;
        final mine = lists.singleWhere((l) => l.name == 'My Folder');
        expect(mine.trackCount, 3);
        final entries = await repo.watchPlaylistTracks(mine.id).first;
        final paths = [
          for (final e in entries) (await localFileFor(e.track.id)).path,
        ];
        expect(paths, hasLength(3));
        expect(paths, [...paths]..sort());
      },
    );

    test('a hasher failure counts as skipped and the scan completes', () async {
      write('a.mp3');
      write('bad.mp3');
      write('z.mp3');
      hashFails.add('bad.mp3');
      final last = await scan(music);
      expect(last.done, isTrue);
      expect(last.found, 3);
      expect(last.added, 2);
      expect(last.skipped, 1);
    });

    test('identical files in one folder yield one track', () async {
      write('a.mp3', content: 'same');
      write('b.mp3', content: 'same');
      write('c.mp3', content: 'same');
      final last = await scan(music);
      expect(last.added, 1);
      expect(last.unchanged, 2);
      expect(last.skipped, 0);
      expect(await allTracks(), hasLength(1));
    });

    test('hashes at most two files at a time', () async {
      for (var i = 0; i < 20; i++) {
        write(numbered(i));
      }
      await scan(music);
      expect(hashCalls, 20);
      expect(maxInFlight, 2);
    });

    test('registerFolder: false repairs files but keeps no folder row and '
        'marks nothing missing', () async {
      write('a.mp3');
      final other = Directory(p.join(tmp.path, 'other'))..createSync();
      final e = write('e.mp3', dir: other);
      await scan(other);
      final trackE = (await allTracks()).single.id;
      // e.mp3 moves into `music`; a stale 'done' row for a vanished file under
      // `music` must stay untouched by a non-registering scan.
      e.renameSync(p.join(music.path, 'e.mp3'));
      final ghost = write('ghost.mp3');
      await scan(music);
      ghost.deleteSync();
      await db.delete(db.libraryFolders).go();

      final last = await scan(music, registerFolder: false);

      expect(last.done, isTrue);
      expect(await db.select(db.libraryFolders).get(), isEmpty);
      expect((await localFileFor(trackE)).path, p.join(music.path, 'e.mp3'));
      final locals = await db.select(db.localFiles).get();
      expect(locals.every((l) => l.state == 'done'), isTrue);
    });

    test('upserts the folder with lastScanAt', () async {
      write('a.mp3');
      await scan(music);
      final folder = await db.select(db.libraryFolders).getSingle();
      expect(folder.path, music.path);
      expect(folder.lastScanAt, isNotNull);
    });

    test('emits progress every 25 files plus the final event', () async {
      for (var i = 0; i < 60; i++) {
        write(numbered(i));
      }
      final events = await scanner.scanFolder(music.path).toList();
      expect(events.map((e) => e.processed), [25, 50, 60]);
      expect(events.map((e) => e.done), [false, false, true]);
      expect(events.last.added, 60);
    });

    test('cancelling stops the scan and leaves lastScanAt unset', () async {
      for (var i = 0; i < 100; i++) {
        write(numbered(i));
      }
      final first = Completer<void>();
      final sub = scanner.scanFolder(music.path).listen((e) {
        if (!first.isCompleted) first.complete();
      });
      await first.future;
      await sub.cancel();
      final rows = await allTracks();
      expect(rows.length, lessThan(100));
      expect(rows, isNotEmpty);
      final folders = await db.select(db.libraryFolders).get();
      expect(folders.every((f) => f.lastScanAt == null), isTrue);
    });

    test('a missing folder reports an error', () async {
      await expectLater(
        scanner.scanFolder(p.join(tmp.path, 'nope')).toList(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('importFile', () {
    test('creates a track, then returns the same id without hashing', () async {
      final f = write('Band - Song.mp3');
      final first = await scanner.importFile(f.path);
      final id = (first as Ok<String>).value;
      expect(hashCalls, 1);
      final second = await scanner.importFile(f.path);
      expect((second as Ok<String>).value, id);
      expect(hashCalls, 1);
      final t = (await allTracks()).single;
      expect(t.id, id);
      expect(t.title, 'Song');
      expect(t.artist, 'Band');
    });

    test('returns the existing track for identical content', () async {
      final a = write('a.mp3', content: 'same');
      final b = write('b.mp3', content: 'same');
      final idA = ((await scanner.importFile(a.path)) as Ok<String>).value;
      final idB = ((await scanner.importFile(b.path)) as Ok<String>).value;
      expect(idB, idA);
      expect(await allTracks(), hasLength(1));
    });

    test('maps a missing or empty file to an error', () async {
      final missing = await scanner.importFile(p.join(music.path, 'x.mp3'));
      expect((missing as Err<String>).failure.kind, FailureKind.notFound);
      final empty = File(p.join(music.path, 'e.mp3'))..writeAsBytesSync([]);
      final r = await scanner.importFile(empty.path);
      expect(r, isA<Err<String>>());
      expect(await allTracks(), isEmpty);
    });

    test('maps an unreadable file to an io error', () async {
      final f = write('bad.mp3');
      hashFails.add('bad.mp3');
      final r = await scanner.importFile(f.path);
      expect((r as Err<String>).failure.kind, FailureKind.io);
    });
  });

  group('markMissing', () {
    test('flags the local file and ignores unknown tracks', () async {
      final f = write('a.mp3');
      final id = ((await scanner.importFile(f.path)) as Ok<String>).value;
      await scanner.markMissing(id);
      expect((await localFileFor(id)).state, 'missing');
      await scanner.markMissing('no-such-track');
    });
  });

  group('AudioMetadataTagReader', () {
    test('reads title and artist from an ID3v2 fixture', () async {
      final t = await AudioMetadataTagReader().read(
        File('test/fixtures/audio/tagged.mp3'),
      );
      expect(t.title, 'Fixture');
      expect(t.artist, 'Songies');
    });
  });
}
