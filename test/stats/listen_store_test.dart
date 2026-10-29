import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/stats/listen_store.dart';

import '../helpers/test_db.dart';

Track _track({String source = 'local', String artist = 'A feat. B'}) => Track(
  id: 't1',
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  title: 'Halo',
  artist: artist,
  durationMs: 200000,
  artworkRef: 'art.jpg',
  unavailable: false,
  searchText: 'halo',
);

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  var now = DateTime.utc(2026, 10, 29, 12);
  late ListenStore store;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    now = DateTime.utc(2026, 10, 29, 12);
    store = ListenStore(db, stamp, now: () => now);
  });
  tearDown(() => db.close());

  final at = DateTime.utc(2026, 10, 29, 11);

  test('start writes one stamped row with the snapshots', () async {
    final id = await store.start(
      _track(),
      at,
      const Duration(seconds: 5),
      false,
    );
    final row = await db.select(db.listens).getSingle();
    expect(row.id, id);
    expect(row.trackId, 't1');
    expect(row.startedAt.toUtc(), at);
    expect(row.heardMs, 5000);
    expect(row.counted, isFalse);
    expect(row.mainArtist, 'A');
    expect(row.titleSnapshot, 'Halo');
    expect(row.artistSnapshot, 'A feat. B');
    expect(row.artworkRef, 'art.jpg');
    expect(row.deleted, isFalse);
    expect(row.clock, isNotEmpty);
    expect(row.originDevice, stamp.deviceId);
  });

  test('a YouTube track uses the comma rule', () async {
    await store.start(
      _track(source: 'yt', artist: 'A feat. B, C'),
      at,
      const Duration(seconds: 1),
      false,
    );
    expect((await db.select(db.listens).getSingle()).mainArtist, 'A feat. B');
  });

  test('update changes heard time and counted with a newer clock', () async {
    final id = await store.start(
      _track(),
      at,
      const Duration(seconds: 5),
      false,
    );
    final first = await db.select(db.listens).getSingle();
    await store.update(id!, const Duration(seconds: 40), true);
    final rows = await db.select(db.listens).get();
    expect(rows, hasLength(1));
    expect(rows.single.heardMs, 40000);
    expect(rows.single.counted, isTrue);
    expect(rows.single.clock.compareTo(first.clock), greaterThan(0));
    expect(rows.single.localSeq, greaterThan(first.localSeq));
  });

  test('prune keeps a 399-day-old row and deletes a 401-day-old one', () async {
    await store.start(
      _track(),
      now.subtract(const Duration(days: 399)),
      const Duration(seconds: 1),
      false,
    );
    final old = await store.start(
      _track(),
      now.subtract(const Duration(days: 401)),
      const Duration(seconds: 1),
      false,
    );
    await store.prune();
    final rows = await db.select(db.listens).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, isNot(old));
  });

  test(
    'start against a closed database returns null without throwing',
    () async {
      await db.close();
      expect(
        await store.start(_track(), at, const Duration(seconds: 1), false),
        isNull,
      );
      await store.update('x', const Duration(seconds: 1), true);
      await store.prune();
    },
  );
}
