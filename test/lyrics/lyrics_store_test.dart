import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_store.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late LyricsStore store;

  setUp(() async {
    db = testDb();
    store = LyricsStore(db, await SyncStamp.load(db));
  });
  tearDown(() => db.close());

  final at = DateTime.utc(2026, 10, 29, 12, 30);

  test('a synced result round-trips with fetchedAt', () async {
    const l = TrackLyrics(
      kind: LyricsKind.synced,
      source: LyricsSource.lrclib,
      lines: [
        LyricLine(Duration(seconds: 1), 'one'),
        LyricLine(Duration(seconds: 5, milliseconds: 500), 'two'),
      ],
    );
    await store.write('t1', l, at);
    final got = await store.read('t1');
    expect(got!.lyrics, l);
    expect(got.fetchedAt.toUtc(), at);
  });

  test('a plain result and a none result round-trip', () async {
    const plain = TrackLyrics(
      kind: LyricsKind.plain,
      source: LyricsSource.youtube,
      text: 'a\nb',
      credit: 'Somebody',
    );
    const none = TrackLyrics(kind: LyricsKind.none, source: null);
    await store.write('p', plain, at);
    await store.write('n', none, at);
    expect((await store.read('p'))!.lyrics, plain);
    final n = await store.read('n');
    expect(n!.lyrics.kind, LyricsKind.none);
    expect(n.fetchedAt.toUtc(), at);
  });

  test('a second write replaces the first with a newer clock', () async {
    await store.write(
      't1',
      const TrackLyrics(
        kind: LyricsKind.plain,
        source: LyricsSource.lrclib,
        text: 'old',
      ),
      at,
    );
    final first = await db.select(db.lyrics).getSingle();
    await store.write(
      't1',
      const TrackLyrics(
        kind: LyricsKind.plain,
        source: LyricsSource.lrclib,
        text: 'new',
      ),
      at,
    );
    final rows = await db.select(db.lyrics).get();
    expect(rows, hasLength(1));
    expect(rows.single.clock.compareTo(first.clock), greaterThan(0));
    expect((await store.read('t1'))!.lyrics.text, 'new');
  });

  test('a tombstoned row reads as null and is revived by a write', () async {
    const l = TrackLyrics(
      kind: LyricsKind.plain,
      source: LyricsSource.lrclib,
      text: 'x',
    );
    await store.write('t1', l, at);
    await (db.update(db.lyrics)..where((t) => t.id.equals('t1'))).write(
      const LyricsCompanion(deleted: Value(true)),
    );
    expect(await store.read('t1'), isNull);
    await store.write('t1', l, at);
    expect(await store.read('t1'), isNotNull);
  });

  test('lyrics from a file are never stored', () async {
    await store.write(
      't1',
      const TrackLyrics(
        kind: LyricsKind.plain,
        source: LyricsSource.file,
        text: 'x',
      ),
      at,
    );
    expect(await db.select(db.lyrics).get(), isEmpty);
  });

  test('reading an unknown id gives null', () async {
    expect(await store.read('nope'), isNull);
  });
}
