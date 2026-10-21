import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:songies/data/database.dart';

/// In-memory database for tests.
AppDatabase testDb() => AppDatabase(NativeDatabase.memory());

/// A [TracksCompanion] with defaults for every required column.
TracksCompanion trackRow({
  required String id,
  String? fileHash,
  String? ytVideoId,
  String source = 'local',
  String title = 'Title',
  String artist = 'Artist',
  String? album,
  int durationMs = 0,
  String clock = '0000000000001-00000-dev',
  String originDevice = 'dev',
  int localSeq = 1,
}) {
  return TracksCompanion.insert(
    id: id,
    clock: clock,
    originDevice: originDevice,
    localSeq: localSeq,
    source: source,
    title: title,
    artist: artist,
    album: Value(album),
    durationMs: Value(durationMs),
    fileHash: Value(fileHash),
    ytVideoId: Value(ytVideoId),
    searchText: '${title.toLowerCase()} ${artist.toLowerCase()}',
  );
}
