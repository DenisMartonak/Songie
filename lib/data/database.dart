import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistEntries,
    YtSeen,
    LocalFiles,
    LibraryFolders,
    Settings,
    PlayHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens (creating if needed) the database file at [f].
  static AppDatabase open(File f) =>
      AppDatabase(NativeDatabase.createInBackground(f));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(playHistory);
      if (from < 3) await m.createTable(ytSeen);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
