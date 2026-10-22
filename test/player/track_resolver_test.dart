import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/track_resolver.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late LocalTrackResolver resolver;

  setUp(() async {
    db = testDb();
    tmp = Directory.systemTemp.createTempSync('songies_resolver_');
    resolver = LocalTrackResolver(db);
    await db.into(db.tracks).insert(trackRow(id: 't1'));
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<Track> trackOf(String id) =>
      (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();

  Future<void> addFile(String trackId, String path, {String state = 'done'}) =>
      db
          .into(db.localFiles)
          .insert(
            LocalFilesCompanion.insert(
              trackId: trackId,
              path: path,
              state: state,
              bytes: 1,
              mtimeMs: 1,
            ),
          );

  test('returns the file source when the file exists', () async {
    final f = File(p.join(tmp.path, 'a.mp3'))..writeAsBytesSync([1, 2, 3]);
    await addFile('t1', f.path);

    final r = await resolver.resolve(await trackOf('t1'));

    expect(r, isA<Ok<AudioSourceRef>>());
    expect((r as Ok<AudioSourceRef>).value, FileSource(f.path));
  });

  test('a file that is back flips its missing state to done', () async {
    final f = File(p.join(tmp.path, 'back.mp3'))..writeAsBytesSync([1, 2, 3]);
    await addFile('t1', f.path, state: 'missing');

    final r = await resolver.resolve(await trackOf('t1'));

    expect(r, isA<Ok<AudioSourceRef>>());
    final row = await db.select(db.localFiles).getSingle();
    expect(row.state, 'done');
  });

  test('a file that is still gone stays missing', () async {
    await addFile('t1', p.join(tmp.path, 'gone.mp3'), state: 'missing');

    await resolver.resolve(await trackOf('t1'));

    final row = await db.select(db.localFiles).getSingle();
    expect(row.state, 'missing');
  });

  test('fails with notFound when the file is gone', () async {
    await addFile('t1', p.join(tmp.path, 'gone.mp3'));

    final r = await resolver.resolve(await trackOf('t1'));

    expect(r, isA<Err<AudioSourceRef>>());
    expect((r as Err<AudioSourceRef>).failure.kind, FailureKind.notFound);
  });

  test('fails with notFound when the track has no local file', () async {
    final r = await resolver.resolve(await trackOf('t1'));

    expect(r, isA<Err<AudioSourceRef>>());
    expect((r as Err<AudioSourceRef>).failure.kind, FailureKind.notFound);
  });
}
