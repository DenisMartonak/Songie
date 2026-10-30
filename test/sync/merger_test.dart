import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/hlc.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/sync/merger.dart';
import 'package:songies/sync/row_applier.dart';
import 'package:songies/sync/sync_row.dart';

import '../helpers/test_db.dart';

/// A canonical clock at [ms] for device [dev].
String clk(int ms, [String dev = 'peer']) =>
    '${ms.toString().padLeft(13, '0')}-00000-$dev';

const _at = 1700000000000;

SyncRow pl(
  String id, {
  String name = 'Mix',
  String? cover,
  String source = 'local',
  String? url,
  int? lastSync,
  bool deleted = false,
  String clock = '0000000000100-00000-me',
}) => SyncRow(SyncTable.playlists, {
  'id': id,
  'clock': clock,
  'originDevice': Hlc.parse(clock).deviceId,
  'deleted': deleted,
  'localSeq': 1,
  'name': name,
  'coverRef': cover,
  'source': source,
  'ytPlaylistUrl': url,
  'lastYtSyncAt': lastSync,
  'mergedInto': null,
});

SyncRow en(
  String id,
  String playlistId, {
  String track = 't1',
  String position = 'a0',
  String status = 'active',
  bool deleted = false,
  String clock = '0000000000100-00000-me',
}) => SyncRow(SyncTable.playlistEntries, {
  'id': id,
  'clock': clock,
  'originDevice': Hlc.parse(clock).deviceId,
  'deleted': deleted,
  'localSeq': 1,
  'playlistId': playlistId,
  'trackId': track,
  'position': position,
  'status': status,
  'kept': false,
  'addedAt': _at,
});

SyncRow th(String id, String name, String clock) => SyncRow(SyncTable.themes, {
  'id': id,
  'clock': clock,
  'originDevice': Hlc.parse(clock).deviceId,
  'deleted': false,
  'localSeq': 1,
  'name': name,
  'specJson': '{}',
});

/// A [LocalView] over a fixed set of rows.
class FakeLocal implements LocalView {
  FakeLocal(this.rows);

  final List<SyncRow> rows;

  @override
  Future<SyncRow?> row(SyncTable t, String id) async {
    for (final r in rows) {
      if (r.table == t && r.id == id) return r;
    }
    return null;
  }

  @override
  Future<List<SyncRow>> entriesOf(String playlistId) async => [
    for (final r in rows)
      if (r.table == SyncTable.playlistEntries &&
          r.data['playlistId'] == playlistId)
        r,
  ];
}

Map<String, SyncRow> byId(List<SyncRow> rows) => {
  for (final r in rows) '${r.table.wire}/${r.id}': r,
};

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late Merger merger;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db, nowMs: () => 1000);
    merger = Merger(stamp: stamp, peerName: 'Pixel');
  });

  tearDown(() => db.close());

  bool restamped(SyncRow r) => r.originDevice == stamp.deviceId;

  test('one-sided rows settle', () {
    final a = pl('p1');
    final b = en('e1', 'p2', clock: clk(200));
    final c = th('h1', 'Dark', clk(300));
    final r = merger.merge([a], [b, c]);
    expect(r.clashes, isEmpty);
    expect(r.settled, unorderedEquals([a, b, c]));
  });

  test('lww tables take the higher clock', () {
    final mine = th('h1', 'Mine', clk(500, 'me'));
    final theirs = th('h1', 'Theirs', clk(400));
    final newer = th('h2', 'Newer', clk(900));
    final older = th('h2', 'Older', clk(800, 'me'));
    final r = merger.merge([mine, older], [theirs, newer]);
    expect(r.clashes, isEmpty);
    expect(r.settled, unorderedEquals([mine, newer]));
  });

  test('rename on one side and removed songs on the other do not clash', () {
    final rename = pl('p', name: 'Renamed');
    final removed = [
      en('e1', 'p', deleted: true, clock: clk(200)),
      en('e2', 'p', deleted: true, clock: clk(200)),
    ];
    final r = merger.merge([rename], removed);
    expect(r.clashes, isEmpty);
    expect(r.settled, unorderedEquals([rename, ...removed]));
  });

  test('same entry moved differently clashes', () {
    final mine = en('e1', 'p', position: 'a1');
    final theirs = en('e1', 'p', position: 'a5', clock: clk(200));
    final other = en('e2', 'p', clock: clk(200));
    final lww = th('h1', 'Dark', clk(300));
    final r = merger.merge([mine], [theirs, other, lww]);
    expect(r.settled, [lww]);
    expect(r.clashes, hasLength(1));
    final c = r.clashes.single;
    expect(c.playlistId, 'p');
    expect(c.name, isNull, reason: 'neither side changed the playlist row');
    expect(c.mineDeleted, isFalse);
    expect(c.theirsDeleted, isFalse);
    expect(c.mine, [mine]);
    expect(c.theirs, unorderedEquals([theirs, other]));
  });

  test('a rename on one side and a cover change on the other clash', () {
    final r = merger.merge(
      [pl('p', name: 'Renamed')],
      [pl('p', cover: 'c.png', clock: clk(200))],
    );
    expect(r.clashes.single.name, 'Renamed');
  });

  test('delete against edit clashes for the whole playlist', () {
    final mine = [pl('p', deleted: true), en('e1', 'p', deleted: true)];
    final theirs = [en('e2', 'p', track: 't2', clock: clk(200))];
    final r = merger.merge(mine, theirs);
    expect(r.settled, isEmpty);
    final c = r.clashes.single;
    expect(c.playlistId, 'p');
    expect(c.name, 'Mix');
    expect(c.mineDeleted, isTrue);
    expect(c.theirsDeleted, isFalse);
    expect(c.mine, unorderedEquals(mine));
    expect(c.theirs, theirs);
  });

  test('a deletion against only removed songs does not clash', () {
    final mine = [pl('p', deleted: true), en('e1', 'p', deleted: true)];
    final theirs = [en('e2', 'p', deleted: true, clock: clk(200))];
    final r = merger.merge(mine, theirs);
    expect(r.clashes, isEmpty);
    expect(r.settled, unorderedEquals([...mine, ...theirs]));
  });

  test('merge of identical sets has no clashes', () {
    final rows = [pl('p'), en('e1', 'p'), th('h1', 'Dark', clk(300))];
    final copies = [
      for (final r in rows) r.withStamp(clock: clk(900), originDevice: 'peer'),
    ];
    final r = merger.merge(rows, copies);
    expect(r.clashes, isEmpty);
    expect(r.settled, hasLength(3));
    expect(
      r.settled.map((r) => r.contentHash),
      unorderedEquals(rows.map((r) => r.contentHash)),
    );
  });

  group('resolve', () {
    // Mine moved e1 and renamed; theirs moved e1 too and added e3.
    final mineRows = [pl('p', name: 'Mine'), en('e1', 'p', position: 'a1')];
    final theirRows = [
      en('e1', 'p', position: 'a5', clock: clk(5000)),
      en('e3', 'p', track: 't3', position: 'a9', clock: clk(5000)),
    ];
    final local = FakeLocal([
      pl('p', name: 'Mine'),
      en('e1', 'p', position: 'a1'),
      en('e2', 'p', track: 't2', position: 'a3'),
      en('e4', 'p', track: 't4', position: 'a4', deleted: true),
    ]);

    test('keepMine restamps my version of the clashing row', () async {
      final r = merger.merge(mineRows, theirRows);
      final f = byId(
        await merger.resolve(r, {'p': Resolution.keepMine}, local),
      );
      expect(
        f.keys,
        unorderedEquals([
          'playlists/p',
          'playlist_entries/e1',
          'playlist_entries/e3',
        ]),
      );
      expect(f['playlists/p'], same(mineRows[0]), reason: 'not clashing');
      expect(f['playlist_entries/e3'], same(theirRows[1]));
      final e1 = f['playlist_entries/e1']!;
      expect(e1.data['position'], 'a1');
      expect(restamped(e1), isTrue);
      expect(
        Hlc.parse(e1.clock).compareTo(Hlc.parse(theirRows[0].clock)),
        greaterThan(0),
        reason: 'a restamped winner beats both sides',
      );
    });

    test('keepTheirs restamps their version of the clashing row', () async {
      final r = merger.merge(mineRows, theirRows);
      final f = byId(
        await merger.resolve(r, {'p': Resolution.keepTheirs}, local),
      );
      expect(f, hasLength(3));
      expect(f['playlists/p'], same(mineRows[0]));
      final e1 = f['playlist_entries/e1']!;
      expect(e1.data['position'], 'a5');
      expect(restamped(e1), isTrue);
      expect(
        Hlc.parse(e1.clock).compareTo(Hlc.parse(theirRows[0].clock)),
        greaterThan(0),
      );
    });

    test('keepBoth keeps mine and copies theirs as a new playlist', () async {
      final r = merger.merge(mineRows, theirRows);
      final rows = await merger.resolve(r, {'p': Resolution.keepBoth}, local);
      final f = byId(rows);
      expect(f['playlist_entries/e1']!.data['position'], 'a1');
      expect(f['playlist_entries/e3'], same(theirRows[1]));
      final copies = rows
          .where((r) => r.table == SyncTable.playlists && r.id != 'p')
          .toList();
      final copy = copies.single;
      expect(restamped(copy), isTrue);
      expect(copy.data['name'], 'Mine (from Pixel)');
      expect(copy.data['source'], 'local');
      expect(copy.deleted, isFalse);
      final copied = rows
          .where((r) => r.data['playlistId'] == copy.id)
          .toList();
      expect(copied.every(restamped), isTrue);
      expect(copied.every((e) => !e.deleted), isTrue);
      expect(
        {for (final e in copied) e.data['trackId']: e.data['position']},
        {'t1': 'a5', 't2': 'a3', 't3': 'a9'},
        reason: 'their view: local overlaid with their rows, live only',
      );
      expect(copied.map((e) => e.id).toSet(), hasLength(3));
      expect(copied.any((e) => ['e1', 'e2', 'e3'].contains(e.id)), isFalse);
    });

    test(
      'keepBoth on a YouTube playlist makes a local copy without the link',
      () async {
        const url = 'https://youtube.com/playlist?list=X';
        final long = 'n' * 95;
        final r = merger.merge(
          [pl('p', name: long, source: 'yt', url: url, lastSync: _at)],
          [
            pl(
              'p',
              name: 'Theirs',
              source: 'yt',
              url: url,
              lastSync: _at,
              clock: clk(5000),
            ),
          ],
        );
        final rows = await merger.resolve(r, {
          'p': Resolution.keepBoth,
        }, FakeLocal(const []));
        final copy = rows.singleWhere((r) => r.id != 'p');
        expect(copy.data['name'], 'Theirs (from Pixel)');
        expect(copy.data['source'], 'local');
        expect(copy.data['ytPlaylistUrl'], isNull);
        expect(copy.data['lastYtSyncAt'], isNull);
        final mine = rows.singleWhere((r) => r.id == 'p');
        expect(mine.data['ytPlaylistUrl'], url);
        expect(mine.data['name'], long);
      },
    );

    test('keepBoth cuts the copy name to the playlist name limit', () async {
      final r = merger.merge(
        [pl('p', name: 'Mine')],
        [pl('p', name: 'x' * 99, clock: clk(5000))],
      );
      final rows = await merger.resolve(r, {
        'p': Resolution.keepBoth,
      }, FakeLocal(const []));
      final copy = rows.singleWhere((r) => r.id != 'p');
      expect(copy.data['name'], ('${'x' * 99} (from Pixel)').substring(0, 100));
    });

    group('delete against edit', () {
      final mineDel = [
        pl('p', deleted: true),
        en('e1', 'p', deleted: true),
        en('e2', 'p', track: 't2', deleted: true),
      ];
      final theirEdit = [
        en('e3', 'p', track: 't3', position: 'a9', clock: clk(5000)),
      ];
      final localDel = FakeLocal([
        pl('p', deleted: true),
        en('e1', 'p', deleted: true),
        en('e2', 'p', track: 't2', position: 'a3', deleted: true),
        en('e0', 'p', track: 't0', deleted: true),
      ]);

      test('when the deletion wins every entry is tombstoned', () async {
        final r = merger.merge(mineDel, theirEdit);
        final rows = await merger.resolve(r, {
          'p': Resolution.keepMine,
        }, localDel);
        final f = byId(rows);
        expect(
          f.keys,
          unorderedEquals([
            'playlists/p',
            'playlist_entries/e1',
            'playlist_entries/e2',
            'playlist_entries/e3',
          ]),
          reason: 'an old tombstone nobody changed is left alone',
        );
        expect(rows.every((r) => r.deleted), isTrue);
        expect(rows.every(restamped), isTrue);
      });

      test(
        'when the edit wins the playlist comes back with their view',
        () async {
          final r = merger.merge(mineDel, theirEdit);
          final rows = await merger.resolve(r, {
            'p': Resolution.keepTheirs,
          }, localDel);
          final f = byId(rows);
          expect(
            f.keys,
            unorderedEquals([
              'playlists/p',
              'playlist_entries/e1',
              'playlist_entries/e2',
              'playlist_entries/e3',
            ]),
          );
          expect(rows.every(restamped), isTrue);
          expect(f['playlists/p']!.deleted, isFalse);
          expect(
            [
              for (final id in ['e1', 'e2', 'e3'])
                f['playlist_entries/$id']!.deleted,
            ],
            [false, false, false],
            reason: 'their device still had the songs this one deleted',
          );
        },
      );

      test('keepBoth when their side deleted throws', () async {
        final r = merger.merge(theirEdit, [
          pl('p', deleted: true, clock: clk(5000)),
        ]);
        expect(r.clashes.single.theirsDeleted, isTrue);
        expect(
          () => merger.resolve(r, {'p': Resolution.keepBoth}, localDel),
          throwsArgumentError,
        );
      });
    });

    test('a missing choice throws', () async {
      final r = merger.merge(mineRows, theirRows);
      expect(() => merger.resolve(r, {}, local), throwsArgumentError);
    });

    test('settled rows pass through', () async {
      final t = th('h1', 'Dark', clk(300));
      final r = merger.merge([t], const []);
      expect(await merger.resolve(r, {}, local), [t]);
    });
  });

  test('DbLocalView reads rows and every entry of a playlist', () async {
    final rows = [
      pl('p'),
      en('e1', 'p'),
      en('e2', 'p', deleted: true),
      en('e3', 'q'),
    ];
    // Tracks t1 is referenced by the entries; the applier needs it present.
    await db.into(db.tracks).insert(trackRow(id: 't1'));
    await RowApplier(db, stamp).apply(rows);
    final view = DbLocalView(db);
    expect((await view.row(SyncTable.playlists, 'p'))!.data['name'], 'Mix');
    expect(await view.row(SyncTable.playlists, 'x'), isNull);
    expect(
      (await view.entriesOf('p')).map((e) => e.id),
      unorderedEquals(['e1', 'e2']),
    );
  });
}
