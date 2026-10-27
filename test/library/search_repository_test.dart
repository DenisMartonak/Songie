import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/text_normalize.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/search_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SearchRepository repo;

  setUp(() {
    db = testDb();
    repo = SearchRepository(db);
  });
  tearDown(() => db.close());

  Future<void> addTrack(
    String id,
    String title,
    String artist, {
    String? album,
    String source = 'local',
    bool deleted = false,
  }) {
    return db
        .into(db.tracks)
        .insert(
          trackRow(
            id: id,
            title: title,
            artist: artist,
            album: album,
            source: source,
          ).copyWith(
            deleted: Value(deleted),
            searchText: Value(
              normalizeForSearch('$title $artist ${album ?? ''}'),
            ),
          ),
        );
  }

  Future<void> addPlaylist(String id, String name, {bool deleted = false}) {
    return db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: id,
            clock: '0000000000001-00000-dev',
            originDevice: 'dev',
            localSeq: 1,
            name: name,
            source: 'local',
            deleted: Value(deleted),
          ),
        );
  }

  Future<List<String>> titles(String query, {int limit = 50}) async => [
    for (final t in await repo.searchTracks(query, limit: limit).first) t.title,
  ];

  group('searchTracks', () {
    setUp(() => addTrack('1', 'Halo', 'Beyoncé'));

    test('finds a track by an unaccented token', () async {
      expect(await titles('beyonce'), ['Halo']);
    });

    test('ANDs tokens case-insensitively', () async {
      expect(await titles('HALO bey'), ['Halo']);
    });

    test('finds a track with an accented query', () async {
      expect(await titles('é'), ['Halo']);
    });

    test('returns nothing when one token does not match', () async {
      expect(await titles('halo zzz'), isEmpty);
    });

    test('matches album text', () async {
      await addTrack('2', 'Other', 'Someone', album: 'Lemonade');
      expect(await titles('lemon'), ['Other']);
    });

    test('empty or whitespace query returns an empty list', () async {
      expect(await titles(''), isEmpty);
      expect(await titles('   '), isEmpty);
    });

    test('excludes deleted tracks', () async {
      await addTrack('2', 'Halo Gone', 'Beyoncé', deleted: true);
      expect(await titles('halo'), ['Halo']);
    });

    test('finds a track whose title was stored decomposed', () async {
      await addTrack('2', 'Café Song', 'Nobody');
      expect(await titles('cafe'), ['Café Song']);
      expect(await titles('café'), ['Café Song']);
    });

    test('percent, underscore and backslash are literal', () async {
      await addTrack('2', '100% Pure', 'X');
      await addTrack('3', 'Some_Thing', 'Y');
      await addTrack('4', 'SomeXThing', 'Y');
      expect(await titles('100%'), ['100% Pure']);
      expect(await titles('%'), ['100% Pure']);
      expect(await titles('some_thing'), ['Some_Thing']);
    });

    test('backslash is matched literally', () async {
      await addTrack('2', r'AC\DC', 'Band');
      await addTrack('3', 'ACDC', 'Band');
      await addTrack('4', '100% Pure', 'Ends With %');
      await addTrack('5', 'ab', 'Z');
      expect(await titles(r'ac\dc'), [r'AC\DC']);
      expect(await titles('\\'), [r'AC\DC']);
      expect(await titles(r'a\b'), isEmpty);
    });

    test('orders by title case-insensitively', () async {
      await addTrack('2', 'beta', 'Zed');
      await addTrack('3', 'Alpha', 'Zed');
      await addTrack('4', 'Charlie', 'Zed');
      expect(await titles('zed'), ['Alpha', 'beta', 'Charlie']);
    });

    test('honours the limit', () async {
      await addTrack('2', 'B', 'Zed');
      await addTrack('3', 'A', 'Zed');
      await addTrack('4', 'C', 'Zed');
      expect(await titles('zed', limit: 2), ['A', 'B']);
    });

    test('is reactive', () async {
      final emissions = <List<String>>[];
      final sub = repo
          .searchTracks('halo')
          .listen((l) => emissions.add([for (final t in l) t.title]));
      await pumpEventQueue();
      await addTrack('2', 'Halo Two', 'Z');
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.first, ['Halo']);
      expect(emissions.last, ['Halo', 'Halo Two']);
    });
  });

  group('searchPlaylists', () {
    test('finds a playlist by name, case-insensitively', () async {
      await addPlaylist('p1', 'Gym Mix');
      await addPlaylist('p2', 'Chill');
      final found = await repo.searchPlaylists('gym').first;
      expect([for (final p in found) p.name], ['Gym Mix']);
    });

    test('ANDs tokens and folds diacritics', () async {
      await addPlaylist('p1', 'Café del Mar');
      await addPlaylist('p2', 'Café Racer');
      final found = await repo.searchPlaylists('cafe mar').first;
      expect([for (final p in found) p.name], ['Café del Mar']);
    });

    test('percent is treated literally', () async {
      await addPlaylist('p1', '100% Hits');
      await addPlaylist('p2', 'Other');
      final found = await repo.searchPlaylists('%').first;
      expect([for (final p in found) p.name], ['100% Hits']);
    });

    test('excludes deleted playlists and returns summaries', () async {
      await addPlaylist('p1', 'Gym A');
      await addPlaylist('p2', 'Gym B', deleted: true);
      final found = await repo.searchPlaylists('gym').first;
      expect(found.single.id, 'p1');
      expect(found.single.trackCount, 0);
    });

    test('orders by name case-insensitively', () async {
      await addPlaylist('p1', 'mix b');
      await addPlaylist('p2', 'Mix A');
      final found = await repo.searchPlaylists('mix').first;
      expect([for (final p in found) p.name], ['Mix A', 'mix b']);
    });

    test('empty or whitespace query returns an empty list', () async {
      await addPlaylist('p1', 'Gym Mix');
      expect(await repo.searchPlaylists('').first, isEmpty);
      expect(await repo.searchPlaylists('  ').first, isEmpty);
    });
  });

  Future<void> addEntry(
    String id,
    String playlistId,
    String trackId, {
    String status = 'active',
    bool deleted = false,
  }) {
    return db
        .into(db.playlistEntries)
        .insert(
          PlaylistEntriesCompanion.insert(
            id: id,
            clock: '0000000000001-00000-dev',
            originDevice: 'dev',
            localSeq: 1,
            playlistId: playlistId,
            trackId: trackId,
            position: 'a0',
            addedAt: DateTime(2026),
            status: Value(status),
            deleted: Value(deleted),
          ),
        );
  }

  group('allTracks', () {
    test('returns live local tracks ordered by title', () async {
      await addTrack('1', 'beta', 'A');
      await addTrack('2', 'Alpha', 'A');
      await addTrack('3', 'Gone', 'A', deleted: true);
      await addTrack('4', 'Remote', 'A', source: 'yt');
      final all = await repo.allTracks().first;
      expect([for (final t in all) t.title], ['Alpha', 'beta']);
    });

    test('yt tracks need an active entry in a live playlist', () async {
      await addTrack('1', 'orphan', 'A', source: 'yt');
      await addTrack('2', 'active', 'A', source: 'yt');
      await addTrack('3', 'tomb', 'A', source: 'yt');
      await addPlaylist('p1', 'P');
      await addEntry('e2', 'p1', '2');
      await addEntry('e3', 'p1', '3', deleted: true);
      final all = await repo.allTracks().first;
      expect([for (final t in all) t.title], ['active']);
      expect(await titles('a'), ['active']);
    });
  });

  group('reachability streams', () {
    for (final name in ['allTracks', 'searchTracks']) {
      test(
        '$name re-emits on entry add, tombstone and playlist delete',
        () async {
          await addTrack('1', 'zed', 'A', source: 'yt');
          await addPlaylist('p1', 'P');
          final stream = name == 'allTracks'
              ? repo.allTracks()
              : repo.searchTracks('zed');
          final emissions = <List<String>>[];
          final sub = stream.listen(
            (r) => emissions.add([for (final t in r) t.title]),
          );
          addTearDown(sub.cancel);
          Future<void> settle() =>
              Future<void>.delayed(const Duration(milliseconds: 50));
          await settle();
          expect(emissions.last, isEmpty);

          await addEntry('e1', 'p1', '1');
          await settle();
          expect(emissions.last, ['zed']);

          await (db.update(db.playlistEntries)..where((e) => e.id.equals('e1')))
              .write(const PlaylistEntriesCompanion(deleted: Value(true)));
          await settle();
          expect(emissions.last, isEmpty);

          await (db.update(db.playlistEntries)..where((e) => e.id.equals('e1')))
              .write(const PlaylistEntriesCompanion(deleted: Value(false)));
          await settle();
          expect(emissions.last, ['zed']);

          await (db.update(db.playlists)..where((p) => p.id.equals('p1')))
              .write(const PlaylistsCompanion(deleted: Value(true)));
          await settle();
          expect(emissions.last, isEmpty);
        },
      );
    }
  });
}
