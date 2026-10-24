import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The schema as shipped at version 1 (before play history).
const _v1Schema = <String>[
  'CREATE TABLE "tracks" ("id" TEXT NOT NULL, "clock" TEXT NOT NULL, "origin_device" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "local_seq" INTEGER NOT NULL, "source" TEXT NOT NULL, "yt_video_id" TEXT NULL UNIQUE, "title" TEXT NOT NULL, "artist" TEXT NOT NULL, "album" TEXT NULL, "duration_ms" INTEGER NOT NULL DEFAULT 0, "artwork_ref" TEXT NULL, "file_hash" TEXT NULL UNIQUE, "unavailable" INTEGER NOT NULL DEFAULT 0 CHECK ("unavailable" IN (0, 1)), "search_text" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "playlists" ("id" TEXT NOT NULL, "clock" TEXT NOT NULL, "origin_device" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "local_seq" INTEGER NOT NULL, "name" TEXT NOT NULL, "cover_ref" TEXT NULL, "source" TEXT NOT NULL, "yt_playlist_url" TEXT NULL, "last_yt_sync_at" INTEGER NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "playlist_entries" ("id" TEXT NOT NULL, "clock" TEXT NOT NULL, "origin_device" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "local_seq" INTEGER NOT NULL, "playlist_id" TEXT NOT NULL, "track_id" TEXT NOT NULL, "position" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT \'active\', "kept" INTEGER NOT NULL DEFAULT 0 CHECK ("kept" IN (0, 1)), "added_at" INTEGER NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "local_files" ("track_id" TEXT NOT NULL, "path" TEXT NOT NULL, "state" TEXT NOT NULL, "bytes" INTEGER NOT NULL, "mtime_ms" INTEGER NOT NULL, "error" TEXT NULL, PRIMARY KEY ("track_id"))',
  'CREATE TABLE "library_folders" ("path" TEXT NOT NULL, "last_scan_at" INTEGER NULL, PRIMARY KEY ("path"))',
  'CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE INDEX playlist_entries_playlist_position ON playlist_entries (playlist_id, position)',
];

void main() {
  test('a v1 database opened with v2 code gains play_history and keeps tracks', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    final raw = sqlite.sqlite3.open(file.path);
    for (final sql in _v1Schema) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO tracks (id, clock, origin_device, local_seq, source, title, "
      "artist, search_text) VALUES ('t1', 'c', 'dev', 1, 'local', 'Halo', "
      "'Beyonce', 'halo beyonce')",
    );
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);

    final tables =
        (await db
                .customSelect(
                  "select name from sqlite_master where type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(tables, contains('play_history'));

    final tracks = await db.select(db.tracks).get();
    expect([for (final t in tracks) t.title], ['Halo']);

    // The new table is usable.
    await db
        .into(db.playHistory)
        .insert(
          PlayHistoryCompanion.insert(trackId: 't1', playedAt: DateTime(2026)),
        );
    expect(await db.select(db.playHistory).get(), hasLength(1));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 5);
  });

  test('a v2 database opened with v3 code gains yt_seen and keeps data', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    final raw = sqlite.sqlite3.open(file.path);
    for (final sql in _v1Schema) {
      raw.execute(sql);
    }
    raw.execute(
      'CREATE TABLE "play_history" ("id" INTEGER NOT NULL, "track_id" TEXT NOT NULL, "playlist_id" TEXT NULL, "played_at" INTEGER NOT NULL, PRIMARY KEY ("id" AUTOINCREMENT))',
    );
    raw.execute(
      "INSERT INTO tracks (id, clock, origin_device, local_seq, source, title, "
      "artist, search_text) VALUES ('t1', 'c', 'dev', 1, 'local', 'Halo', "
      "'Beyonce', 'halo beyonce')",
    );
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);

    expect(
      [for (final t in await db.select(db.tracks).get()) t.title],
      ['Halo'],
    );
    await db
        .into(db.ytSeen)
        .insert(
          YtSeenCompanion.insert(
            id: 's1',
            clock: 'c',
            originDevice: 'dev',
            localSeq: 2,
            playlistId: 'p',
            videoId: 'v',
          ),
        );
    expect(await db.select(db.ytSeen).get(), hasLength(1));
    // (playlist, video) is unique.
    await expectLater(
      db
          .into(db.ytSeen)
          .insert(
            YtSeenCompanion.insert(
              id: 's2',
              clock: 'c',
              originDevice: 'dev',
              localSeq: 3,
              playlistId: 'p',
              videoId: 'v',
            ),
          ),
      throwsA(anything),
    );
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 5);
  });

  test(
    'a v3 database opened with v4 code gains download columns and keeps rows',
    () async {
      final dir = await Directory.systemTemp.createTemp('songies_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/songies.db');

      final raw = sqlite.sqlite3.open(file.path);
      for (final sql in _v1Schema) {
        raw.execute(sql);
      }
      raw.execute(
        'CREATE TABLE "play_history" ("id" INTEGER NOT NULL, "track_id" TEXT NOT NULL, "playlist_id" TEXT NULL, "played_at" INTEGER NOT NULL, PRIMARY KEY ("id" AUTOINCREMENT))',
      );
      raw.execute(
        'CREATE TABLE "yt_seen" ("id" TEXT NOT NULL, "clock" TEXT NOT NULL, "origin_device" TEXT NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "local_seq" INTEGER NOT NULL, "playlist_id" TEXT NOT NULL, "video_id" TEXT NOT NULL, PRIMARY KEY ("id"), UNIQUE ("playlist_id", "video_id"))',
      );
      raw.execute(
        "INSERT INTO local_files (track_id, path, state, bytes, mtime_ms) "
        "VALUES ('t1', '/m/a.mp3', 'done', 5, 7)",
      );
      raw.execute('PRAGMA user_version = 3');
      raw.close();

      final db = AppDatabase.open(file);
      addTearDown(db.close);

      final rows = await db.select(db.localFiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.path, '/m/a.mp3');
      expect(rows.single.state, 'done');
      expect(rows.single.requestedAt, isNull);
      expect(rows.single.manual, isFalse);

      await db
          .into(db.playlistDevicePrefs)
          .insert(PlaylistDevicePrefsCompanion.insert(playlistId: 'p'));
      final pref = await db.select(db.playlistDevicePrefs).getSingle();
      expect(pref.downloadEnabled, isFalse);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, 5);
    },
  );

  test('a v4 database opened with v5 code gains themes and fonts', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    // Create a current database, drop the v5 tables and step back to v4.
    final first = AppDatabase.open(file);
    await first.customSelect('select 1').get();
    await first.customStatement('DROP TABLE themes');
    await first.customStatement('DROP TABLE fonts');
    await first.customStatement('PRAGMA user_version = 4');
    await first.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);
    await db
        .into(db.themes)
        .insert(
          ThemesCompanion.insert(
            id: 'th1',
            clock: 'c',
            originDevice: 'dev',
            localSeq: 1,
            name: 'Mine',
            specJson: '{}',
          ),
        );
    await db
        .into(db.fonts)
        .insert(
          FontsCompanion.insert(
            id: 'f1',
            clock: 'c',
            originDevice: 'dev',
            localSeq: 2,
            family: 'Fira',
            fileHash: 'abc',
            ext: 'ttf',
          ),
        );
    expect(await db.select(db.themes).get(), hasLength(1));
    expect((await db.select(db.fonts).getSingle()).family, 'Fira');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 5);
  });
}
