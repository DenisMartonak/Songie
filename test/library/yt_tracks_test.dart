import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/play_history_repository.dart';
import 'package:songies/library/search_repository.dart';
import 'package:songies/library/yt_tracks.dart';
import 'package:songies/youtube/thumbnail_fetcher.dart';

import '../helpers/test_db.dart';

class _FakeThumbs implements ThumbnailFetcher {
  final calls = <List<String>>[];
  String? ref = 'yt2-abc.jpg';

  @override
  Future<String?> fetchBest(List<String> urls) async {
    calls.add(urls);
    return ref;
  }

  @override
  Duration get timeout => const Duration(seconds: 1);
}

YtmSong song({
  String id = 'v1',
  String title = 'Halo',
  String artist = 'Beyonce',
  String? album = 'I Am',
  int? durationMs = 261000,
}) => YtmSong(
  videoId: id,
  title: title,
  artists: [YtmArtistRef(name: artist)],
  album: album,
  durationMs: durationMs,
  thumbnailUrl: 'https://x/t.jpg',
);

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late _FakeThumbs thumbs;
  late YtTrackStore store;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    thumbs = _FakeThumbs();
    store = YtTrackStore(db, stamp, thumbs);
  });
  tearDown(() async {
    await store.coversSettled;
    await db.close();
  });

  Future<List<Track>> rows() => db.select(db.tracks).get();

  test(
    'upsert creates one stamped row and is idempotent per videoId',
    () async {
      final a = (await store.upsert(song())) as Ok<Track>;
      final b = (await store.upsert(song())) as Ok<Track>;
      expect(b.value.id, a.value.id);
      final all = await rows();
      expect(all, hasLength(1));
      final t = all.single;
      expect(t.source, 'yt');
      expect(t.ytVideoId, 'v1');
      expect(t.artist, 'Beyonce');
      expect(t.album, 'I Am');
      expect(t.durationMs, 261000);
      expect(t.searchText, contains('halo'));
      expect(t.searchText, contains('beyonce'));
      expect(t.originDevice, stamp.deviceId);
    },
  );

  test('upsert queues the cover and stores the yt2 ref', () async {
    await store.upsert(song());
    await store.coversSettled;
    expect(thumbs.calls, hasLength(1));
    expect(thumbs.calls.single.first, contains('/v1/'));
    expect((await rows()).single.artworkRef, 'yt2-abc.jpg');
  });

  test('upsertAll returns tracks in order', () async {
    final r = await store.upsertAll([song(id: 'a'), song(id: 'b')]);
    expect([for (final t in r) t.ytVideoId], ['a', 'b']);
    expect(await rows(), hasLength(2));
  });

  Future<Track> imported({String? album}) async {
    await db
        .into(db.tracks)
        .insert(
          trackRow(
            id: 't1',
            source: 'yt',
            ytVideoId: 'v1',
            title: 'Halo',
            artist: 'BeyonceVEVO',
            album: album,
          ),
        );
    return (await rows()).single;
  }

  test('upgradeFrom fills an unenriched imported row', () async {
    final t = await imported();
    await store.upgradeFrom(t, song());
    final u = (await rows()).single;
    expect(u.artist, 'Beyonce');
    expect(u.album, 'I Am');
    expect(u.durationMs, 261000);
    expect(u.searchText, contains('beyonce'));
    expect(u.clock.compareTo(t.clock), greaterThan(0));
  });

  test('upgradeFrom keeps an album that is already set', () async {
    final t = await imported(album: 'Mine');
    await store.upgradeFrom(t, song(album: 'Other', artist: 'Someone'));
    final u = (await rows()).single;
    expect(u.album, 'Mine');
    expect(u.artist, 'BeyonceVEVO');
  });

  test('upgradeFrom with nothing new writes nothing', () async {
    final t = await imported();
    await store.upgradeFrom(t, song());
    await store.coversSettled;
    final once = (await rows()).single;
    await store.upgradeFrom(once, song());
    await store.coversSettled;
    final twice = (await rows()).single;
    expect(twice.clock, once.clock);
    expect(twice.localSeq, once.localSeq);
  });

  group('library reachability', () {
    late SearchRepository search;
    late LibraryRepository library;
    setUp(() {
      search = SearchRepository(db);
      library = LibraryRepository(db, stamp);
    });

    test('lists and search need an active playlist entry', () async {
      final orphan = ((await store.upsert(
        song(id: 'o', title: 'xorphan'),
      )) as Ok<Track>).value;
      final kept = ((await store.upsert(
        song(id: 'k', title: 'xkept'),
      )) as Ok<Track>).value;
      final gone = ((await store.upsert(
        song(id: 'g', title: 'xgone'),
      )) as Ok<Track>).value;
      final pid = ((await library.createPlaylist('P')) as Ok<String>).value;
      await library.addTracks(pid, [kept.id, gone.id]);
      final entry = await (db.select(
        db.playlistEntries,
      )..where((e) => e.trackId.equals(gone.id))).getSingle();
      await (db.update(db.playlistEntries)..where((e) => e.id.equals(entry.id)))
          .write(const PlaylistEntriesCompanion(deleted: Value(true)));

      final all = await search.allTracks().first;
      expect([for (final t in all) t.title], ['xkept']);
      final found = await search.searchTracks('x').first;
      expect([for (final t in found) t.title], ['xkept']);
      expect(orphan.id, isNotEmpty);
    });

    test('recents still include a playlist-less track', () async {
      final t = ((await store.upsert(song())) as Ok<Track>).value;
      await PlayHistoryRepository(db).record(t.id, null);
      final recent = await PlayHistoryRepository(db).recentTracks(10).first;
      expect([for (final r in recent) r.id], [t.id]);
    });

    test('a deleted playlist does not make a track reachable', () async {
      final t = ((await store.upsert(song(title: 'xsong'))) as Ok<Track>).value;
      final pid = ((await library.createPlaylist('P')) as Ok<String>).value;
      await library.addTracks(pid, [t.id]);
      await (db.update(db.playlists)..where((p) => p.id.equals(pid))).write(
        const PlaylistsCompanion(deleted: Value(true)),
      );
      expect(await search.allTracks().first, isEmpty);
    });
  });
}
