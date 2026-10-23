import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/youtube/thumbnail_fetcher.dart';
import 'package:songies/youtube/yt_import_service.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';

import '../helpers/fake_ytdlp_runner.dart';
import '../helpers/test_db.dart';

const link = 'https://music.youtube.com/playlist?list=PLx';
const link2 = 'https://music.youtube.com/playlist?list=PLy';

String listJson(List<String> ids, {String title = 'Mix', List<String>? bad}) =>
    jsonEncode({
      '_type': 'playlist',
      'id': 'PLx',
      'title': title,
      'entries': [
        for (final id in ids)
          {
            'id': id,
            'title': 'Song $id',
            'duration': 100,
            'channel': 'Chan',
            'thumbnails': [
              {'url': 'https://img/$id.jpg', 'width': 100, 'height': 100},
            ],
          },
      ],
    });

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late FakeYtDlpRunner runner;
  late YtImportService service;
  late LibraryRepository repo;
  late Directory tmp;
  late List<Uri> downloads;
  var failDownload = false;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    runner = FakeYtDlpRunner();
    repo = LibraryRepository(db, stamp);
    tmp = Directory.systemTemp.createTempSync('songies_yt_');
    downloads = [];
    failDownload = false;
    final png = img.encodePng(img.Image(width: 16, height: 9));
    service = YtImportService(
      db,
      stamp,
      YtDlpClient(runner),
      ThumbnailFetcher(ArtCache(Directory('${tmp.path}/art')), (u) async {
        downloads.add(u);
        if (failDownload) throw const SocketException('offline');
        return png;
      }),
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  void serve(List<String> ids, {String to = 'list=PLx'}) {
    runner = FakeYtDlpRunner()..onOk(to, listJson(ids));
    service = YtImportService(
      db,
      stamp,
      YtDlpClient(runner),
      ThumbnailFetcher(ArtCache(Directory('${tmp.path}/art')), (u) async {
        downloads.add(u);
        if (failDownload) throw const SocketException('offline');
        return img.encodePng(img.Image(width: 16, height: 9));
      }),
    );
  }

  Future<List<int>> counts() async => [
    (await db.select(db.playlists).get()).length,
    (await db.select(db.tracks).get()).length,
    (await db.select(db.playlistEntries).get()).length,
    (await db.select(db.ytSeen).get()).length,
  ];

  Future<List<String>> order(String playlistId) async {
    final rows = await repo.watchPlaylistTracks(playlistId).first;
    return [for (final r in rows) r.track.ytVideoId!];
  }

  Future<PlaylistEntry> entryOf(String playlistId, String video) async {
    final q =
        db.select(db.playlistEntries).join([
          innerJoin(
            db.tracks,
            db.tracks.id.equalsExp(db.playlistEntries.trackId),
          ),
        ])..where(
          db.playlistEntries.playlistId.equals(playlistId) &
              db.tracks.ytVideoId.equals(video),
        );
    return (await q.getSingle()).readTable(db.playlistEntries);
  }

  group('import', () {
    test(
      'creates playlist, tracks, entries in order and yt_seen, stamped',
      () async {
        serve(['a', 'b', 'c']);
        final r = await service.importPlaylist(link);
        final res = (r as Ok<ImportResult>).value;
        expect(res.alreadyExisted, false);
        expect(res.added, 3);
        expect(await counts(), [1, 3, 3, 3]);
        expect(await order(res.playlistId), ['a', 'b', 'c']);
        final pl = await db.select(db.playlists).getSingle();
        expect(pl.source, 'yt');
        expect(pl.name, 'Mix');
        expect(pl.ytPlaylistUrl, link);
        expect(pl.lastYtSyncAt, isNotNull);
        final seqs = <int>[
          for (final t in await db.select(db.tracks).get()) t.localSeq,
          for (final t in await db.select(db.playlistEntries).get()) t.localSeq,
          for (final t in await db.select(db.ytSeen).get()) t.localSeq,
          pl.localSeq,
        ];
        expect(seqs.toSet(), hasLength(seqs.length));
        final t = (await db.select(db.tracks).get()).first;
        expect(t.source, 'yt');
        expect(t.searchText, contains('chan'));
        expect(t.artworkRef, isNotNull);
      },
    );

    test('invalid link writes nothing', () async {
      serve(['a']);
      final r = await service.importPlaylist('https://example.com/x');
      final f = (r as Err<ImportResult>).failure;
      expect(f.kind, FailureKind.invalidInput);
      expect(f.message, 'Not a YouTube playlist link');
      expect(await counts(), [0, 0, 0, 0]);
    });

    test('fetch error is returned and nothing is written', () async {
      runner.onFail('list=PLx', 'ERROR: The playlist does not exist.');
      final r = await service.importPlaylist(link);
      expect(ytErrorKindOf((r as Err).failure), YtErrorKind.notFound);
      expect(await counts(), [0, 0, 0, 0]);
    });

    test('re-import returns the existing playlist, nothing changes', () async {
      serve(['a', 'b']);
      final first =
          (await service.importPlaylist(link) as Ok<ImportResult>).value;
      final before = await counts();
      final again =
          (await service.importPlaylist(link) as Ok<ImportResult>).value;
      expect(again.alreadyExisted, true);
      expect(again.playlistId, first.playlistId);
      expect(await counts(), before);
    });

    test('the same video in two playlists is one track row', () async {
      serve(['a', 'b']);
      await service.importPlaylist(link);
      runner.onOk('list=PLy', listJson(['b', 'c']));
      await service.importPlaylist(link2);
      expect(await counts(), [2, 3, 4, 4]);
    });

    test('a tombstoned track is resurrected', () async {
      serve(['a']);
      await service.importPlaylist(link);
      final old = await db.select(db.tracks).getSingle();
      await (db.update(db.tracks)..where((t) => t.id.equals(old.id))).write(
        const TracksCompanion(deleted: Value(true)),
      );
      runner.onOk('list=PLy', listJson(['a']));
      final r = await service.importPlaylist(link2);
      expect(r, isA<Ok<ImportResult>>());
      final t = await db.select(db.tracks).getSingle();
      expect(t.id, old.id);
      expect(t.deleted, false);
      expect(t.localSeq, greaterThan(old.localSeq));
    });

    test('unavailable entries are imported as unavailable', () async {
      runner.onOk(
        'list=PLx',
        jsonEncode({
          'id': 'PLx',
          'title': 'M',
          'entries': [
            {'id': 'p', 'title': '[Private video]'},
          ],
        }),
      );
      await service.importPlaylist(link);
      final t = await db.select(db.tracks).getSingle();
      expect(t.unavailable, true);
    });

    test('duplicate ids in one response are imported once', () async {
      serve(['a', 'b', 'a']);
      final r = (await service.importPlaylist(link) as Ok<ImportResult>).value;
      expect(r.added, 2);
      expect(await order(r.playlistId), ['a', 'b']);
    });

    test('thumbnail failures do not fail the import', () async {
      failDownload = true;
      serve(['a']);
      final r = await service.importPlaylist(link);
      expect(r, isA<Ok<ImportResult>>());
      expect((await db.select(db.tracks).getSingle()).artworkRef, isNull);
    });

    test('1,500 entries import in order', () async {
      final ids = [
        for (var i = 0; i < 1500; i++) 'v${i.toString().padLeft(4, '0')}',
      ];
      runner.onOk('list=PLx', listJson(ids));
      // No thumbnails: keep the test about the database.
      final sw = Stopwatch()..start();
      final r = (await service.importPlaylist(link) as Ok<ImportResult>).value;
      expect(r.added, 1500);
      expect(await order(r.playlistId), ids);
      expect((await counts())[2], 1500);
      expect(sw.elapsed.inSeconds, lessThan(60));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('sync', () {
    late String pid;
    setUp(() async {
      serve(['a', 'b', 'c']);
      pid = ((await service.importPlaylist(
        link,
      )) as Ok<ImportResult>).value.playlistId;
      // user deletes b and moves c first
      await repo.removeEntry((await entryOf(pid, 'b')).id);
      await repo.moveEntry(
        (await entryOf(pid, 'c')).id,
        beforeEntryId: (await entryOf(pid, 'a')).id,
      );
    });

    test('appends only new ids after the last entry', () async {
      serve(['a', 'b', 'c', 'd']);
      final r = (await service.syncPlaylist(pid) as Ok<SyncResult>).value;
      expect(r.added, 1);
      expect(r.flaggedRemoved, 0);
      expect(r.addedTrackIds, hasLength(1));
      expect(await order(pid), ['c', 'a', 'd']);
      final d = await (db.select(
        db.tracks,
      )..where((t) => t.ytVideoId.equals('d'))).getSingle();
      expect(r.addedTrackIds.single, d.id);
    });

    test('flags removed entries, keeps others active', () async {
      serve(['a', 'd']);
      final r = (await service.syncPlaylist(pid) as Ok<SyncResult>).value;
      expect(r.flaggedRemoved, 1);
      expect((await entryOf(pid, 'c')).status, 'removed_on_yt');
      expect((await entryOf(pid, 'a')).status, 'active');
      expect(await order(pid), ['c', 'a', 'd']);
    });

    test('kept entries are not flagged', () async {
      serve(['a', 'd']);
      await service.syncPlaylist(pid);
      await repo.keepEntry((await entryOf(pid, 'c')).id);
      final kept = await entryOf(pid, 'c');
      expect(kept.status, 'active');
      expect(kept.kept, true);
      final r = (await service.syncPlaylist(pid) as Ok<SyncResult>).value;
      expect(r.flaggedRemoved, 0);
      expect((await entryOf(pid, 'c')).status, 'active');
    });

    test('flagged entries come back when YouTube has them again', () async {
      serve(['a', 'd']);
      await service.syncPlaylist(pid);
      serve(['a', 'c', 'd']);
      final r = (await service.syncPlaylist(pid) as Ok<SyncResult>).value;
      expect(r.restored, 1);
      expect(r.added, 0);
      expect((await entryOf(pid, 'c')).status, 'active');
    });

    test('lastYtSyncAt is updated', () async {
      final before = DateTime(2020);
      await db
          .update(db.playlists)
          .write(PlaylistsCompanion(lastYtSyncAt: Value(before)));
      serve(['a', 'b', 'c']);
      await service.syncPlaylist(pid);
      final after = (await db.select(db.playlists).getSingle()).lastYtSyncAt!;
      expect(after.isAfter(before), true);
    });

    test('fetch failure writes nothing', () async {
      runner = FakeYtDlpRunner()
        ..onFail('list=PLx', 'ERROR: Unable to connect to proxy');
      service = YtImportService(
        db,
        stamp,
        YtDlpClient(runner),
        ThumbnailFetcher(
          ArtCache(Directory('${tmp.path}/art')),
          (u) async => [],
        ),
      );
      final before = await counts();
      final r = await service.syncPlaylist(pid);
      expect(ytErrorKindOf((r as Err).failure), YtErrorKind.network);
      expect(await counts(), before);
    });

    test('non-yt playlist is invalidInput', () async {
      final local = (await repo.createPlaylist('Mine') as Ok<String>).value;
      final r = await service.syncPlaylist(local);
      expect((r as Err).failure.kind, FailureKind.invalidInput);
    });
  });
}
