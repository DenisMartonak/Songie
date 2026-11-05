import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/search_repository.dart';

import '../helpers/test_db.dart';

/// Playlist entries whose track is a local file this device never had are
/// hidden: from the entries, the playlist's count and length, and so from
/// everything built on them (play-all and shuffle queues, Favorites).
void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late LibraryRepository repo;
  late FavoritesRepository favorites;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    repo = LibraryRepository(db, stamp);
    favorites = FavoritesRepository(db, stamp);
  });
  tearDown(() => db.close());

  /// A local track; [file] is this device's LocalFiles state, null for none
  /// (the track came from another device).
  Future<void> local(String id, {String? file = 'done', int ms = 60000}) async {
    await db
        .into(db.tracks)
        .insert(trackRow(id: id, title: 'Song $id', durationMs: ms));
    if (file == null) return;
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: id,
            path: '/music/$id.mp3',
            state: file,
            bytes: 1,
            mtimeMs: 1,
          ),
        );
  }

  Future<void> yt(String id, {int ms = 60000}) => db
      .into(db.tracks)
      .insert(trackRow(id: id, source: 'yt', ytVideoId: id, durationMs: ms));

  Future<String> playlist(List<String> ids) async {
    final id = (await repo.createPlaylist('P') as Ok<String>).value;
    await repo.addTracks(id, ids);
    return id;
  }

  Future<List<String>> idsOf(String playlistId) async => [
    for (final e in await repo.watchPlaylistTracks(playlistId).first)
      e.track.id,
  ];

  Future<PlaylistSummary> summaryOf(String playlistId) async =>
      (await repo.watchPlaylists().first).singleWhere(
        (p) => p.id == playlistId,
      );

  test('a local track with no LocalFiles row on this device is hidden from '
      'the playlist, its count and length', () async {
    await local('here', ms: 60000);
    await local('elsewhere', file: null, ms: 120000);
    final p = await playlist(['elsewhere', 'here']);

    expect(await idsOf(p), ['here']);
    final s = await summaryOf(p);
    expect(s.trackCount, 1);
    expect(s.durationMs, 60000);
  });

  test(
    'the cover falls back to the first song shown, not a hidden one',
    () async {
      await db.into(db.tracks).insert(trackRow(id: 'elsewhere', durationMs: 1));
      await (db.update(db.tracks)..where((t) => t.id.equals('elsewhere')))
          .write(const TracksCompanion(artworkRef: Value('art-elsewhere')));
      await local('here');
      await (db.update(db.tracks)..where((t) => t.id.equals('here'))).write(
        const TracksCompanion(artworkRef: Value('art-here')),
      );
      final p = await playlist(['elsewhere', 'here']);

      expect((await summaryOf(p)).coverRef, 'art-here');
    },
  );

  test('a local track marked missing on this device still shows (with '
      'Locate)', () async {
    await local('gone', file: 'missing');
    final p = await playlist(['gone']);

    final rows = await repo.watchPlaylistTracks(p).first;
    expect(rows.map((r) => r.track.id), ['gone']);
    expect(rows.single.fileMissing, isTrue);
    expect((await summaryOf(p)).trackCount, 1);
  });

  test('YouTube tracks always show; Favorites follows the same rule; '
      'play-all skips hidden', () async {
    await yt('v1');
    await local('here');
    await local('elsewhere', file: null);
    await favorites.ensureFavorites();
    for (final id in ['v1', 'here', 'elsewhere']) {
      await favorites.star(id);
    }
    final p = await playlist(['v1', 'elsewhere', 'here']);

    // Play-all and shuffle queue the playlist's rows as listed.
    expect(await idsOf(p), ['v1', 'here']);
    expect((await summaryOf(p)).trackCount, 2);
    expect((await idsOf(kFavoritesPlaylistId)).toSet(), {'v1', 'here'});
    expect((await summaryOf(kFavoritesPlaylistId)).trackCount, 2);
    // The star itself stays: it belongs to the song, not to this device.
    expect(await favorites.watchIds().first, contains('elsewhere'));

    // Once the file turns up here, the entry shows again.
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: 'elsewhere',
            path: '/music/elsewhere.mp3',
            state: 'done',
            bytes: 1,
            mtimeMs: 1,
          ),
        );
    expect(await idsOf(p), ['v1', 'elsewhere', 'here']);
  });

  test('songs this device has no file for are not in song search or the '
      'add-songs list', () async {
    final search = SearchRepository(db);
    await local('here');
    await local('elsewhere', file: null);
    // It came with a synced playlist: still not here.
    await playlist(['elsewhere', 'here']);

    expect((await search.allTracks().first).map((t) => t.id), ['here']);
    expect((await search.searchTracks('song').first).map((t) => t.id), [
      'here',
    ]);
  });
}
