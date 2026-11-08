import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/yt_tracks.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_songs.dart';
import 'package:songies/youtube/thumbnail_fetcher.dart';

import '../helpers/test_db.dart';

class _FakeThumbs implements ThumbnailFetcher {
  final calls = <List<String>>[];

  @override
  Future<String?> fetchBest(List<String> urls) async {
    calls.add(urls);
    return 'yt2-abc.jpg';
  }

  @override
  Duration get timeout => const Duration(seconds: 1);
}

void main() {
  late AppDatabase db;
  late _FakeThumbs thumbs;
  late YtTrackStore store;

  setUp(() async {
    db = testDb();
    thumbs = _FakeThumbs();
    store = YtTrackStore(db, await SyncStamp.load(db), thumbs);
  });
  tearDown(() async {
    await store.coversSettled;
    await db.close();
  });

  test('roomSongOf keeps yt ids and drops local ones', () async {
    await db
        .into(db.tracks)
        .insert(trackRow(id: 'a', source: 'yt', ytVideoId: 'v1'));
    await db.into(db.tracks).insert(trackRow(id: 'b', fileHash: 'h'));
    final rows = await db.select(db.tracks).get();
    final yt = rows.firstWhere((t) => t.id == 'a');
    final local = rows.firstWhere((t) => t.id == 'b');
    expect(roomSongOf(yt).videoId, 'v1');
    expect(roomSongOf(yt).local, isFalse);
    expect(roomSongOf(local).local, isTrue);
  });

  test('tracksForSongs keeps positions and skips local songs', () async {
    final out = await tracksForSongs(const [
      RoomSong(
        videoId: 'v1',
        title: 'A',
        artist: 'X',
        album: 'Al',
        durationMs: 1000,
        artUrl: 'https://x/a.jpg',
      ),
      RoomSong(title: 'L', artist: 'Me'),
      RoomSong(videoId: 'v2', title: 'B', artist: 'Y'),
    ], store);
    expect(out, hasLength(3));
    expect(out[0]!.ytVideoId, 'v1');
    expect(out[0]!.artist, 'X');
    expect(out[1], isNull);
    expect(out[2]!.ytVideoId, 'v2');
    await store.coversSettled;
    expect(thumbs.calls, hasLength(2));
  });
}
