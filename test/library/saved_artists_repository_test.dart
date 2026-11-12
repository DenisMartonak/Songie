import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/library/saved_artists_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SavedArtistsRepository repo;

  setUp(() async {
    db = testDb();
    repo = SavedArtistsRepository(db, await SyncStamp.load(db));
  });
  tearDown(() => db.close());

  const artist = YtmArtist(browseId: 'UC1', name: 'Halsey', thumbnailUrl: 'u1');

  Future<SavedArtist> row() => db.select(db.savedArtists).getSingle();

  test(
    'save then watchAll has one row with id artist:UC1 and the name',
    () async {
      await repo.save(artist);
      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single.id, 'artist:UC1');
      expect(all.single.browseId, 'UC1');
      expect(all.single.name, 'Halsey');
      expect(all.single.thumbnailUrl, 'u1');
    },
  );

  test(
    'save, unsave, save leaves one row, deleted false, a newer clock each time',
    () async {
      await repo.save(artist);
      final c1 = (await row()).clock;
      await repo.unsave('UC1');
      final gone = await row();
      expect(gone.deleted, isTrue);
      expect(gone.clock.compareTo(c1), greaterThan(0));
      await repo.save(artist);
      final again = await row();
      expect(again.deleted, isFalse);
      expect(again.clock.compareTo(gone.clock), greaterThan(0));
      expect(await db.select(db.savedArtists).get(), hasLength(1));
    },
  );

  test('unsave hides it from watchAll and watchIsSaved emits false', () async {
    await repo.save(artist);
    expect(await repo.watchIsSaved('UC1').first, isTrue);
    await repo.unsave('UC1');
    expect(await repo.watchAll().first, isEmpty);
    expect(await repo.watchIsSaved('UC1').first, isFalse);
  });

  test('refresh of an unsaved artist writes nothing', () async {
    await repo.refresh(artist);
    expect(await db.select(db.savedArtists).get(), isEmpty);
  });

  test('refresh with the same name and thumbnail keeps the clock', () async {
    await repo.save(artist);
    final before = await row();
    await repo.refresh(artist);
    expect((await row()).clock, before.clock);
  });

  test('refresh with a new name updates it and restamps', () async {
    await repo.save(artist);
    final before = await row();
    await repo.refresh(
      const YtmArtist(browseId: 'UC1', name: 'Halsey!', thumbnailUrl: 'u1'),
    );
    final after = await row();
    expect(after.name, 'Halsey!');
    expect(after.clock.compareTo(before.clock), greaterThan(0));
  });
}
