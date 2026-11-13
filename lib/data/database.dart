import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../lyrics/lyrics.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistEntries,
    YtSeen,
    LocalFiles,
    PlaylistDevicePrefs,
    LibraryFolders,
    Settings,
    PlayHistory,
    Themes,
    Fonts,
    Lyrics,
    Listens,
    SavedArtists,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens (creating if needed) the database file at [f].
  static AppDatabase open(File f) =>
      AppDatabase(NativeDatabase.createInBackground(f));

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(playHistory);
      if (from < 3) await m.createTable(ytSeen);
      if (from < 4) {
        await m.createTable(playlistDevicePrefs);
        await m.addColumn(localFiles, localFiles.requestedAt);
        await m.addColumn(localFiles, localFiles.manual);
      }
      if (from < 5) {
        await m.createTable(themes);
        await m.createTable(fonts);
      }
      if (from < 6) await m.createTable(lyrics);
      if (from < 7) {
        await m.createTable(listens);
        await m.createIndex(listensStartedAt);
      }
      if (from < 8) {
        await m.addColumn(tracks, tracks.mergedInto);
        await m.addColumn(playlists, playlists.mergedInto);
        for (final idx in [
          tracksLocalSeq,
          playlistsLocalSeq,
          playlistEntriesLocalSeq,
          ytSeenLocalSeq,
          themesLocalSeq,
          fontsLocalSeq,
          lyricsLocalSeq,
          listensLocalSeq,
        ]) {
          await m.createIndex(idx);
        }
      }
      // Home-network sync's paired devices, gone with it.
      if (from < 9) await m.deleteTable('peers');
      if (from < 10) await _upgradeCreditMarkers();
      if (from < 11) {
        await m.createTable(savedArtists);
        await m.createIndex(savedArtistsLocalSeq);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  /// Plain lyrics stored a NUL before their credit line, which the server
  /// (Postgres) refuses; swaps it for today's marker. Not restamped: rows of
  /// the old form never reached a server (cloud sync came with schema 10).
  Future<void> _upgradeCreditMarkers() async {
    // hex() sees past a NUL, unlike most of SQLite's text functions;
    // 006372656469743A is "\0credit:".
    final rows = await customSelect(
      "SELECT id, body FROM lyrics WHERE kind = 'plain' "
      "AND instr(hex(body), '006372656469743A') > 0",
    ).get();
    for (final r in rows) {
      final body = upgradeCreditMarker(r.read<String>('body'));
      if (body == null) continue;
      await customStatement('UPDATE lyrics SET body = ? WHERE id = ?', [
        body,
        r.read<String>('id'),
      ]);
    }
  }
}
