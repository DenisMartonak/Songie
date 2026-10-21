import 'package:drift/drift.dart';

/// Columns shared by every row that is synced between devices.
///
/// Rows are never hard-deleted: [deleted] is a tombstone. [clock] is a packed
/// HLC, [originDevice] the device that last wrote the row and [localSeq] a
/// per-device monotonic counter used to find rows changed since a given point.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get clock => text()();
  TextColumn get originDevice => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get localSeq => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tracks extends Table with SyncColumns {
  /// 'yt' | 'local'
  TextColumn get source => text()();
  TextColumn get ytVideoId => text().nullable().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get artworkRef => text().nullable()();
  TextColumn get fileHash => text().nullable().unique()();
  BoolColumn get unavailable => boolean().withDefault(const Constant(false))();
  TextColumn get searchText => text()();
}

class Playlists extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get coverRef => text().nullable()();

  /// 'local' | 'yt'
  TextColumn get source => text()();
  TextColumn get ytPlaylistUrl => text().nullable()();
  DateTimeColumn get lastYtSyncAt => dateTime().nullable()();
}

@TableIndex(
  name: 'playlist_entries_playlist_position',
  columns: {#playlistId, #position},
)
class PlaylistEntries extends Table with SyncColumns {
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();

  /// Fractional index; entries sort by this string.
  TextColumn get position => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get kept => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
}

/// Device-local: where a track's audio file lives on this device. Not synced.
class LocalFiles extends Table {
  TextColumn get trackId => text()();
  TextColumn get path => text()();

  /// 'done' | 'missing'
  TextColumn get state => text()();
  IntColumn get bytes => integer()();
  IntColumn get mtimeMs => integer()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Device-local: folders scanned for music. Not synced.
class LibraryFolders extends Table {
  TextColumn get path => text()();
  DateTimeColumn get lastScanAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}

/// Device-local key/value settings. Not synced.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
