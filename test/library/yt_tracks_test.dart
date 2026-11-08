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
  String thumbnailUrl = 'https://x/t.jpg',
  bool isVideo = false,
}) => YtmSong(
  videoId: id,
  title: title,
  artists: [YtmArtistRef(name: artist)],
  album: album,
  durationMs: durationMs,
  thumbnailUrl: thumbnailUrl,
  isVideo: isVideo,
);

/// The square album art YouTube Music gives a song.
const _albumArt = 'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj';

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

  group('album art (the cover the album page shows)', () {
    test('a song with YouTube Music art takes it before the video '
        'thumbnails', () async {
      await store.upsert(song(thumbnailUrl: _albumArt));
      await store.coversSettled;
      expect(thumbs.calls.single.first, _albumArt);
      expect(thumbs.calls.single.skip(1).first, contains('/v1/'));
    });

    test('a music video keeps its video thumbnail first', () async {
      await store.upsert(song(thumbnailUrl: _albumArt, isVideo: true));
      await store.coversSettled;
      expect(thumbs.calls.single.first, contains('/v1/'));
    });

    test('replaces a video-thumbnail cover the song already had, once a '
        'session', () async {
      await db
          .into(db.tracks)
          .insert(
            trackRow(
              id: 't1',
              source: 'yt',
              ytVideoId: 'v1',
            ).copyWith(artworkRef: const Value('yt2-video.jpg')),
          );
      thumbs.ref = 'yt2-album.jpg';
      await store.upsert(song(thumbnailUrl: _albumArt));
      await store.coversSettled;
      expect(thumbs.calls.single, [_albumArt]);
      expect((await rows()).single.artworkRef, 'yt2-album.jpg');

      await store.upsert(song(thumbnailUrl: _albumArt));
      await store.coversSettled;
      expect(thumbs.calls, hasLength(1));
    });

    test('the same cover again writes nothing', () async {
      await store.upsert(song());
      await store.coversSettled;
      final before = (await rows()).single.clock;
      await store.upsert(song(thumbnailUrl: _albumArt));
      await store.coversSettled;
      expect(thumbs.calls, hasLength(2));
      expect((await rows()).single.clock, before);
    });

    test('without YouTube Music art a sharp cover is left alone', () async {
      await db
          .into(db.tracks)
          .insert(
            trackRow(
              id: 't1',
              source: 'yt',
              ytVideoId: 'v1',
            ).copyWith(artworkRef: const Value('yt2-video.jpg')),
          );
      await store.upsert(song());
      await store.coversSettled;
      expect(thumbs.calls, isEmpty);
    });
  });

  test('changes announces the row once its cover is stored', () async {
    final seen = <Track>[];
    final sub = store.changes.listen(seen.add);
    addTearDown(sub.cancel);
    final a = (await store.upsert(song())) as Ok<Track>;
    expect(a.value.artworkRef, null);
    await store.coversSettled;
    await pumpEventQueue();
    expect(seen.last.id, a.value.id);
    expect(seen.last.artworkRef, 'yt2-abc.jpg');
  });

  test('changes announces an upgraded row', () async {
    final seen = <Track>[];
    final sub = store.changes.listen(seen.add);
    addTearDown(sub.cancel);
    await db
        .into(db.tracks)
        .insert(
          trackRow(
            id: 't1',
            source: 'yt',
            ytVideoId: 'v1',
            title: 'Halo',
            artist: 'BeyonceVEVO',
          ),
        );
    final t = (await rows()).single;
    await store.upgradeFrom(t, song());
    await pumpEventQueue();
    expect(seen.first.artist, 'Beyonce');
  });

  test('find returns the live row for a video, without writing', () async {
    expect(await store.find('v1'), equals(null));
    expect(await rows(), isEmpty);
    final a = (await store.upsert(song())) as Ok<Track>;
    expect((await store.find('v1'))?.id, a.value.id);
    await (db.update(db.tracks)..where((t) => t.id.equals(a.value.id))).write(
      const TracksCompanion(deleted: Value(true)),
    );
    expect(await store.find('v1'), equals(null));
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
