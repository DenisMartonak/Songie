import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/stats/artist_photos.dart';
import 'package:songies/stats/stats_models.dart';

import '../helpers/test_db.dart';

ArtistStat stat(String name, {String? track = 't'}) => ArtistStat(
  name: name,
  plays: 1,
  heard: const Duration(minutes: 1),
  sampleTrackId: track,
);

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late DateTime clock;
  var savedMap = <String, ArtistPhoto>{};
  final trackCalls = <String>[];
  final artistCalls = <String>[];
  Future<ArtistPhoto?> Function(String) artistFn = (_) async => null;

  ArtistPhotos make() => ArtistPhotos(
    settings: settings,
    saved: () async => savedMap,
    browseIdForTrack: (t) async {
      trackCalls.add(t);
      return 'B-$t';
    },
    artist: (b) {
      artistCalls.add(b);
      return artistFn(b);
    },
    now: () => clock,
  );

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    clock = DateTime(2026, 1, 1);
    savedMap = {};
    trackCalls.clear();
    artistCalls.clear();
    artistFn = (b) async => (browseId: b, photoUrl: 'url-$b');
  });
  tearDown(() => db.close());

  test('saved artist wins without a lookup', () async {
    savedMap = {'A': (browseId: 'SA', photoUrl: 'saved')};
    final p = make();
    await p.fill([stat('A')]);
    expect(trackCalls, isEmpty);
    expect(artistCalls, isEmpty);
    expect(p.of('A'), (browseId: 'SA', photoUrl: 'saved'));
  });

  test('looks up through the sample track', () async {
    final p = make();
    var n = 0;
    p.changes.listen((_) => n++);
    await p.fill([stat('A', track: 'x')]);
    await Future<void>.delayed(Duration.zero);
    expect(trackCalls, ['x']);
    expect(p.of('A'), (browseId: 'B-x', photoUrl: 'url-B-x'));
    expect(n, 1);
  });

  test('kept across instances', () async {
    await make().fill([stat('A')]);
    trackCalls.clear();
    artistCalls.clear();
    final second = make();
    await second.load();
    await second.fill([stat('A')]);
    expect(second.of('A'), isNotNull);
    expect(trackCalls, isEmpty);
    expect(artistCalls, isEmpty);
  });

  test('failures are not cached', () async {
    artistFn = (_) async => throw Exception('boom');
    final p = make();
    await p.fill([stat('A')]);
    expect(p.of('A'), isNull);
    artistFn = (_) async => null;
    await p.fill([stat('A')], force: true);
    expect(p.of('A'), isNull);
    expect(artistCalls.length, 2);
  });

  test('at most once an hour', () async {
    final p = make();
    await p.fill([stat('A')]);
    artistFn = (_) async => null;
    clock = clock.add(const Duration(minutes: 10));
    await p.fill([stat('B')]);
    expect(trackCalls, ['t']);
    clock = clock.add(const Duration(minutes: 51));
    await p.fill([stat('B')]);
    expect(artistCalls.length, 2);
    await p.fill([stat('C')], force: true);
    expect(artistCalls.length, 3);
  });

  test('apply fills known names and leaves others', () async {
    final p = make();
    await p.fill([stat('A', track: 'x')]);
    final out = p.apply([stat('A'), stat('Z')]);
    expect(out[0].photoUrl, 'url-B-x');
    expect(out[0].browseId, 'B-x');
    expect(out[1].photoUrl, isNull);
    expect(out[1].browseId, isNull);
  });

  test('fill without load keeps the stored photos', () async {
    await make().fill([stat('A', track: 'x')]);
    final second = make();
    await second.fill([stat('B', track: 'y')]);
    expect(second.of('A'), (browseId: 'B-x', photoUrl: 'url-B-x'));
    final third = make();
    await third.load();
    expect(third.of('A'), isNotNull);
    expect(third.of('B'), isNotNull);
  });

  test('load is done once and returns the same future', () async {
    final p = make();
    expect(identical(p.load(), p.load()), isTrue);
  });

  test('a saved artist without a photo is looked up by its page', () async {
    savedMap = {'A': (browseId: 'SA', photoUrl: null)};
    final p = make();
    await p.fill([stat('A', track: 'x')]);
    expect(trackCalls, isEmpty);
    expect(artistCalls, ['SA']);
    expect(p.of('A'), (browseId: 'SA', photoUrl: 'url-SA'));
  });

  test('dispose closes the changes stream', () async {
    final p = make();
    var done = false;
    p.changes.listen((_) {}, onDone: () => done = true);
    await p.dispose();
    expect(done, isTrue);
  });
}
