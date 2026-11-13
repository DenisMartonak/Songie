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

@TableIndex(name: 'tracks_local_seq', columns: {#localSeq})
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

  /// Set on a track merged into another by sync dedupe; points at the winner.
  TextColumn get mergedInto => text().nullable()();
}

@TableIndex(name: 'playlists_local_seq', columns: {#localSeq})
class Playlists extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get coverRef => text().nullable()();

  /// 'local' | 'yt'
  TextColumn get source => text()();
  TextColumn get ytPlaylistUrl => text().nullable()();
  DateTimeColumn get lastYtSyncAt => dateTime().nullable()();

  /// Set on a playlist merged into another by sync; points at the winner.
  TextColumn get mergedInto => text().nullable()();

  /// Its share code while this account shares it (playlist sharing).
  TextColumn get shareCode => text().nullable()();

  /// The share code it follows: read-only, updated from the owner's.
  TextColumn get followCode => text().nullable()();

  /// The followed playlist owner's username.
  TextColumn get followOwner => text().nullable()();

  /// The `updated_at` of the owner's snapshot last applied.
  DateTimeColumn get followUpdatedAt => dateTime().nullable()();

  /// The owner stopped sharing it: now the follower's own playlist.
  BoolColumn get followEnded => boolean().withDefault(const Constant(false))();
}

@TableIndex(
  name: 'playlist_entries_playlist_position',
  columns: {#playlistId, #position},
)
@TableIndex(name: 'playlist_entries_local_seq', columns: {#localSeq})
class PlaylistEntries extends Table with SyncColumns {
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();

  /// Fractional index; entries sort by this string.
  TextColumn get position => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get kept => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
}

/// Synced: which YouTube videos a playlist has already seen, so sync never
/// re-adds one the user removed.
@TableIndex(name: 'yt_seen_local_seq', columns: {#localSeq})
class YtSeen extends Table with SyncColumns {
  TextColumn get playlistId => text()();
  TextColumn get videoId => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {playlistId, videoId},
  ];
}

/// Synced: a user-saved theme. [specJson] is the `ThemeSpec` JSON (spec §9).
/// The built-in themes are never stored here.
@DataClassName('ThemeRow')
@TableIndex(name: 'themes_local_seq', columns: {#localSeq})
class Themes extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get specJson => text()();
}

/// Synced: an imported font. The file lives at `<appData>/fonts/<fileHash>.<ext>`.
@DataClassName('FontRow')
@TableIndex(name: 'fonts_local_seq', columns: {#localSeq})
class Fonts extends Table with SyncColumns {
  TextColumn get family => text()();
  TextColumn get fileHash => text()();

  /// 'ttf' | 'otf'
  TextColumn get ext => text()();
}

/// Device-local: where a track's audio file lives on this device. Not synced.
///
/// Local-library tracks use states 'done' | 'missing'. YouTube downloads
/// (tracks with source 'yt') use 'queued' | 'downloading' | 'done' | 'failed',
/// with [path] '' until done and [error] holding the user message. The local
/// library logic (scan, missing-marking, Locate) never touches YouTube rows.
class LocalFiles extends Table {
  TextColumn get trackId => text()();
  TextColumn get path => text()();

  /// 'done' | 'missing' | 'queued' | 'downloading' | 'failed'
  TextColumn get state => text()();
  IntColumn get bytes => integer()();
  IntColumn get mtimeMs => integer()();
  TextColumn get error => text().nullable()();

  /// When a YouTube download was requested (ms since epoch); FIFO key.
  IntColumn get requestedAt => integer().nullable()();

  /// A YouTube download the user asked for on this one track.
  BoolColumn get manual => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Device-local: playlists whose YouTube tracks this device downloads.
/// Not synced.
class PlaylistDevicePrefs extends Table {
  TextColumn get playlistId => text()();
  BoolColumn get downloadEnabled =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {playlistId};
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

/// Device-local: which track started playing, from which playlist and when.
/// Not synced. Only the newest [maxRows] rows are kept (see
/// `PlayHistoryRepository`).
@DataClassName('PlayHistoryEntry')
class PlayHistory extends Table {
  /// Monotonic, so "newest" never depends on the clock's resolution.
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  TextColumn get playlistId => text().nullable()();
  DateTimeColumn get playedAt => dateTime()();
}

/// Synced lyrics for a track; the row id is the track id (one row per track).
@DataClassName('LyricsRow')
@TableIndex(name: 'lyrics_local_seq', columns: {#localSeq})
class Lyrics extends Table with SyncColumns {
  /// 'synced' | 'plain' | 'none'
  TextColumn get kind => text()();

  /// LRC text for synced, plain text for plain, empty for none.
  TextColumn get body => text()();

  /// 'lrclib' | 'youtube'; null for none.
  TextColumn get source => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();
}

/// One listening session of a track (Plan 9). Written when a song starts and
/// re-stamped as it is heard; pruned after 730 days.
@DataClassName('ListenRow')
@TableIndex(name: 'listens_started_at', columns: {#startedAt})
@TableIndex(name: 'listens_local_seq', columns: {#localSeq})
class Listens extends Table with SyncColumns {
  TextColumn get trackId => text()();

  /// When the song started playing (UTC).
  DateTimeColumn get startedAt => dateTime()();

  /// How much of the song was actually heard.
  IntColumn get heardMs => integer()();

  /// Whether this listen is a play (see `reachedPlay`).
  BoolColumn get counted => boolean()();

  /// Main artist at the time (see `mainArtist`).
  TextColumn get mainArtist => text()();
  TextColumn get titleSnapshot => text()();
  TextColumn get artistSnapshot => text()();
  TextColumn get artworkRef => text().nullable()();
}

/// An artist the user saved. The row id is `artist:<browseId>`.
@TableIndex(name: 'saved_artists_local_seq', columns: {#localSeq})
class SavedArtists extends Table with SyncColumns {
  TextColumn get browseId => text()();
  TextColumn get name => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  DateTimeColumn get savedAt => dateTime()();
}
