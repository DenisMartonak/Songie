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

/// Undoes the v8 additions (the v9 removal of `peers` and the v11 table) on an
/// open current-schema database.
Future<void> _stepBackToV7(AppDatabase db) async {
  await db.customStatement('DROP TABLE IF EXISTS peers');
  await db.customStatement('DROP TABLE IF EXISTS saved_artists');
  for (final t in [
    'tracks',
    'playlists',
    'playlist_entries',
    'yt_seen',
    'themes',
    'fonts',
    'lyrics',
    'listens',
  ]) {
    await db.customStatement('DROP INDEX IF EXISTS ${t}_local_seq');
  }
  await db.customStatement('ALTER TABLE tracks DROP COLUMN merged_into');
  await db.customStatement('ALTER TABLE playlists DROP COLUMN merged_into');
}

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
    expect(version.data.values.single, 11);
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
    expect(version.data.values.single, 11);
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
      expect(version.data.values.single, 11);
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
    await first.customStatement('DROP TABLE lyrics');
    await first.customStatement('DROP TABLE listens');
    await _stepBackToV7(first);
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
    expect(version.data.values.single, 11);
  });

  test(
    'a v5 database opened with v9 code gains an empty lyrics table',
    () async {
      final dir = await Directory.systemTemp.createTemp('songies_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/songies.db');

      final first = AppDatabase.open(file);
      await first.customSelect('select 1').get();
      await first.customStatement('DROP TABLE lyrics');
      await first.customStatement('DROP TABLE listens');
      await _stepBackToV7(first);
      await first.customStatement('PRAGMA user_version = 5');
      await first.close();

      final db = AppDatabase.open(file);
      addTearDown(db.close);
      expect(await db.select(db.lyrics).get(), isEmpty);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, 11);
    },
  );

  test(
    'a v6 database opened with v9 code gains an empty listens table and index',
    () async {
      final dir = await Directory.systemTemp.createTemp('songies_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/songies.db');

      final first = AppDatabase.open(file);
      await first.customSelect('select 1').get();
      await first.customStatement('DROP TABLE listens');
      await _stepBackToV7(first);
      await first.customStatement('PRAGMA user_version = 6');
      await first.close();

      final db = AppDatabase.open(file);
      addTearDown(db.close);
      expect(await db.select(db.listens).get(), isEmpty);
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'listens_started_at'",
          )
          .get();
      expect(idx, hasLength(1));
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, 11);
    },
  );

  test('v7 to v9 adds merged_into and local_seq indexes', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    final first = AppDatabase.open(file);
    await first.customSelect('select 1').get();
    await _stepBackToV7(first);
    await first.customStatement('PRAGMA user_version = 7');
    await first.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);
    final cols = await db.customSelect('PRAGMA table_info(tracks)').get();
    expect(cols.map((r) => r.read<String>('name')), contains('merged_into'));
    final idx = await db.customSelect('PRAGMA index_list(listens)').get();
    expect(
      idx.map((r) => r.read<String>('name')),
      contains('listens_local_seq'),
    );
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 11);
  });
  test('v8 to v9 drops peers and keeps every other table\'s rows', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    // A v8 database: today's tables plus the paired-devices table, with a
    // row in each.
    final first = AppDatabase.open(file);
    await first.customSelect('select 1').get();
    await first.customStatement(
      'CREATE TABLE IF NOT EXISTS "peers" ("device_id" TEXT NOT NULL, '
      '"name" TEXT NOT NULL, "cert_fingerprint" TEXT NOT NULL, '
      '"pair_key" TEXT NOT NULL, "host" TEXT NULL, "port" INTEGER NULL, '
      '"last_sent_seq" INTEGER NOT NULL DEFAULT 0, '
      '"last_received_seq" INTEGER NOT NULL DEFAULT 0, '
      '"last_sync_at" INTEGER NULL, PRIMARY KEY ("device_id"))',
    );
    const sync = "'c', 'dev', 1";
    for (final sql in [
      "INSERT INTO peers (device_id, name, cert_fingerprint, pair_key) "
          "VALUES ('d2', 'Laptop', 'ff', 'a2V5')",
      "INSERT INTO tracks (id, clock, origin_device, local_seq, source, title, "
          "artist, search_text) VALUES ('t1', $sync, 'local', 'Halo', "
          "'Beyonce', 'halo beyonce')",
      "INSERT INTO playlists (id, clock, origin_device, local_seq, name, "
          "source) VALUES ('p1', $sync, 'Chill', 'local')",
      "INSERT INTO playlist_entries (id, clock, origin_device, local_seq, "
          "playlist_id, track_id, position, added_at) "
          "VALUES ('e1', $sync, 'p1', 't1', 'a', 0)",
      "INSERT INTO yt_seen (id, clock, origin_device, local_seq, playlist_id, "
          "video_id) VALUES ('s1', $sync, 'p1', 'v1')",
      "INSERT INTO themes (id, clock, origin_device, local_seq, name, "
          "spec_json) VALUES ('th1', $sync, 'Dark', '{}')",
      "INSERT INTO fonts (id, clock, origin_device, local_seq, family, "
          "file_hash, ext) VALUES ('f1', $sync, 'Fira', 'h', 'ttf')",
      "INSERT INTO lyrics (id, clock, origin_device, local_seq, kind, body, "
          "fetched_at) VALUES ('t1', $sync, 'plain', 'la', 0)",
      "INSERT INTO listens (id, clock, origin_device, local_seq, track_id, "
          "started_at, heard_ms, counted, main_artist, title_snapshot, "
          "artist_snapshot) VALUES ('l1', $sync, 't1', 0, 1000, 1, 'Beyonce', "
          "'Halo', 'Beyonce')",
      "INSERT INTO local_files (track_id, path, state, bytes, mtime_ms) "
          "VALUES ('t1', '/m/halo.mp3', 'present', 1, 1)",
      "INSERT INTO playlist_device_prefs (playlist_id) VALUES ('p1')",
      "INSERT INTO library_folders (path) VALUES ('/m')",
      "INSERT INTO settings (key, value) VALUES ('k', 'v')",
      "INSERT INTO play_history (track_id, played_at) VALUES ('t1', 0)",
    ]) {
      await first.customStatement(sql);
    }
    Future<Map<String, int>> counts(AppDatabase db) async {
      final names = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT IN ('peers', 'saved_artists')",
          )
          .get();
      return {
        for (final r in names)
          r.read<String>('name'):
              (await db
                      .customSelect(
                        'SELECT count(*) AS n FROM "${r.read<String>('name')}"',
                      )
                      .getSingle())
                  .read<int>('n'),
      };
    }

    final before = await counts(first);
    expect(before.values, everyElement(1));
    await first.customStatement('DROP TABLE saved_artists');
    await first.customStatement('PRAGMA user_version = 8');
    await first.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);
    final peers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'peers'",
        )
        .get();
    expect(peers, isEmpty);
    expect(await counts(db), before);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 11);
  });

  test('v9 to v10 rewrites the NUL credit marker in plain lyrics', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    final first = AppDatabase.open(file);
    for (final (id, kind, body) in [
      ('t1', 'plain', 'la\n\u0000credit:Source: Me'),
      ('t2', 'plain', 'no credit'),
      ('t3', 'synced', '[00:01.00]x\n[by:Me]'),
    ]) {
      await first.customStatement(
        'INSERT INTO lyrics (id, clock, origin_device, local_seq, kind, body, '
        "fetched_at) VALUES (?, 'c', 'dev', 7, ?, ?, 0)",
        [id, kind, body],
      );
    }
    await first.customStatement('DROP TABLE saved_artists');
    await first.customStatement('PRAGMA user_version = 9');
    await first.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);
    final rows = {for (final r in await db.select(db.lyrics).get()) r.id: r};
    expect(rows['t1']!.body, 'la\ncredit:Source: Me');
    // Not restamped: no device has pushed a row of the old form yet.
    expect(rows['t1']!.localSeq, 7);
    expect(rows['t2']!.body, 'no credit');
    expect(rows['t3']!.body, '[00:01.00]x\n[by:Me]');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 11);
  });

  test('v10 to v11 creates saved_artists', () async {
    final dir = await Directory.systemTemp.createTemp('songies_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/songies.db');

    final first = AppDatabase.open(file);
    await first.customStatement('DROP TABLE saved_artists');
    await first.customStatement('PRAGMA user_version = 10');
    await first.close();

    final db = AppDatabase.open(file);
    addTearDown(db.close);
    expect(await db.select(db.savedArtists).get(), isEmpty);
    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'saved_artists_local_seq'",
        )
        .get();
    expect(idx, hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 11);
  });
}
