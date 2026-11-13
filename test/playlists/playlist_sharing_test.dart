import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/playlists/playlist_sharing.dart';
import 'package:songies/room/room_protocol.dart';

import '../helpers/fake_sharing_backend.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeSharingBackend backend;
  late PlaylistSharing sharing;
  late int tracksMade;

  /// Like YtTrackStore: one track per video id, reused when it exists.
  Future<List<Track?>> tracksFor(List<RoomSong> songs) async {
    final out = <Track?>[];
    for (final s in songs) {
      final vid = s.videoId;
      if (vid == null) {
        out.add(null);
        continue;
      }
      var t = await (db.select(
        db.tracks,
      )..where((t) => t.ytVideoId.equals(vid))).getSingleOrNull();
      if (t == null) {
        tracksMade++;
        await db.insertTrack(
          trackRow(
            id: 'yt-$vid',
            source: 'yt',
            ytVideoId: vid,
            title: s.title,
            artist: s.artist,
          ),
        );
        t = await repo.trackById('yt-$vid');
      }
      out.add(t);
    }
    return out;
  }

  setUp(() async {
    db = testDb();
    repo = LibraryRepository(db, await SyncStamp.load(db));
    backend = FakeSharingBackend()
      ..me = 'owner'
      ..names['owner'] = 'den';
    tracksMade = 0;
    await db.insertTrack(
      trackRow(id: 'y1', source: 'yt', ytVideoId: 'v1', title: 'Halo'),
    );
    await db.insertTrack(
      trackRow(id: 'y2', source: 'yt', ytVideoId: 'v2', title: 'Run'),
    );
    await db.insertTrack(trackRow(id: 'l1', title: 'My file'));
    sharing = PlaylistSharing(
      backend: backend,
      library: repo,
      tracksFor: tracksFor,
    );
  });
  tearDown(() async {
    sharing.dispose();
    await db.close();
  });

  T ok<T>(Result<T> r) => (r as Ok<T>).value;

  Future<String> playlist(String name, List<String> ids) async {
    final id = ok(await repo.createPlaylist(name));
    ok(await repo.addTracks(id, ids));
    return id;
  }

  Future<List<String>> idsOf(String id) async => [
    for (final e in await repo.watchPlaylistTracks(id).first) e.track.id,
  ];

  Future<Playlist> row(String id) async => (await repo.playlistById(id))!;

  test('share publishes YouTube songs only and stores the code', () async {
    final id = await playlist('Gym', const ['y1', 'l1', 'y2']);
    expect(await sharing.localCount(id), 1);
    final code = await sharing.share(id);
    expect((await row(id)).shareCode, code);
    final got = (await backend.get(code))!;
    expect(got.name, 'Gym');
    expect(got.songs.map((s) => s.videoId), ['v1', 'v2']);
    // Sharing again gives the same link.
    expect(await sharing.share(id), code);
  });

  test('an owner edit republishes once it settles', () async {
    sharing.dispose();
    sharing = PlaylistSharing(
      backend: backend,
      library: repo,
      tracksFor: tracksFor,
      settle: const Duration(milliseconds: 200),
    );
    final id = await playlist('Gym', const ['y1']);
    final code = await sharing.share(id);
    sharing.signedIn();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    backend.calls.clear();
    await repo.addTracks(id, const ['y2']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(backend.calls, isNot(contains('update')));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(backend.calls.where((c) => c == 'update'), hasLength(1));
    final got = (await backend.get(code))!;
    expect(got.songs.map((s) => s.videoId), ['v1', 'v2']);
  });

  test('the default wait before republishing is 3 s', () {
    expect(sharing.settle, const Duration(seconds: 3));
  });

  test('follow creates a followed playlist with the songs', () async {
    final code = await backend.share('Gym', const [
      RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
      RoomSong(videoId: 'v9', title: 'New', artist: 'C'),
    ]);
    backend.me = 'follower';
    final id = (await sharing.follow(code))!;
    final p = await row(id);
    expect(p.isFollowed, isTrue);
    expect(p.followOwner, 'den');
    expect(p.name, 'Gym');
    expect(await idsOf(id), ['y1', 'yt-v9']);
    // Following the same link again gives the same playlist.
    expect(await sharing.follow(code), id);
  });

  test('a song already in the library is reused', () async {
    final code = await backend.share('Gym', const [
      RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
    ]);
    backend.me = 'follower';
    await sharing.follow(code);
    expect(tracksMade, 0);
  });

  test(
    'a refresh applies a newer snapshot and skips an unchanged one',
    () async {
      final code = await backend.share('Gym', const [
        RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
      ]);
      backend.me = 'follower';
      final id = (await sharing.follow(code))!;
      // Nothing new: the playlist isn't written again.
      final before = (await row(id)).clock;
      await sharing.refresh();
      expect((await row(id)).clock, before);
      backend.me = 'owner';
      await backend.update(code, 'Gym', const [
        RoomSong(videoId: 'v2', title: 'Run', artist: 'B'),
        RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
      ]);
      backend.me = 'follower';
      await sharing.refresh();
      expect(await idsOf(id), ['y2', 'y1']);
    },
  );

  test('a stopped share ends the follow and keeps the songs', () async {
    final code = await backend.share('Gym', const [
      RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
    ]);
    backend.me = 'follower';
    final id = (await sharing.follow(code))!;
    backend.me = 'owner';
    await backend.stop(code);
    backend.me = 'follower';
    await sharing.refresh();
    final p = await row(id);
    expect(p.isFollowed, isFalse);
    expect(p.followEnded, isTrue);
    expect(await idsOf(id), ['y1']);
  });

  test('copy makes an editable playlist with the same songs', () async {
    final code = await backend.share('Gym', const [
      RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
      RoomSong(videoId: 'v2', title: 'Run', artist: 'B'),
    ]);
    backend.me = 'follower';
    final fromLink = await sharing.copy(code: code);
    expect((await row(fromLink)).isFollowed, isFalse);
    expect(await idsOf(fromLink), ['y1', 'y2']);
    final followed = (await sharing.follow(code))!;
    final fromFollowed = await sharing.copy(playlistId: followed);
    expect(await idsOf(fromFollowed), ['y1', 'y2']);
    ok(await repo.addTracks(fromFollowed, const ['l1']));
  });

  test('stop sharing ends the link and clears the code', () async {
    final id = await playlist('Gym', const ['y1']);
    final code = await sharing.share(id);
    await sharing.stopSharing(id);
    expect((await row(id)).shareCode, isNull);
    expect(await backend.get(code), isNull);
  });
}
