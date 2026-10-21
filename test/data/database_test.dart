import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:songies/data/database.dart';

import '../helpers/test_db.dart';

void main() {
  group('in-memory', () {
    late AppDatabase db;
    setUp(() => db = testDb());
    tearDown(() => db.close());

    test('fileHash is unique', () async {
      await db.into(db.tracks).insert(trackRow(id: 't1', fileHash: 'h'));
      await expectLater(
        db.into(db.tracks).insert(trackRow(id: 't2', fileHash: 'h')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('ytVideoId is unique', () async {
      await db.into(db.tracks).insert(trackRow(id: 't1', ytVideoId: 'v'));
      await expectLater(
        db.into(db.tracks).insert(trackRow(id: 't2', ytVideoId: 'v')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('schema creates all tables', () async {
      final names =
          (await db
                  .customSelect(
                    "select name from sqlite_master where type='table'",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(
        names,
        containsAll([
          'tracks',
          'playlists',
          'playlist_entries',
          'local_files',
          'library_folders',
          'settings',
        ]),
      );
    });
  });

  test('open(File) enables WAL and foreign keys', () async {
    final dir = await Directory.systemTemp.createTemp('songies_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final fileDb = AppDatabase.open(File('${dir.path}/songies.db'));
    final mode = await fileDb.customSelect('PRAGMA journal_mode').getSingle();
    final fk = await fileDb.customSelect('PRAGMA foreign_keys').getSingle();
    await fileDb.close();
    expect(mode.data.values.single, 'wal');
    expect(fk.data.values.single, 1);
  });
}
