import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:songies/data/database.dart';

/// The synced tables, in the order used to break ties in the change feed.
enum SyncTable {
  tracks('tracks'),
  playlists('playlists'),
  playlistEntries('playlist_entries'),
  ytSeen('yt_seen'),
  themes('themes'),
  fonts('fonts'),
  lyrics('lyrics'),
  listens('listens'),
  savedArtists('saved_artists');

  const SyncTable(this.wire);

  /// The table's name on the wire and in SQL.
  final String wire;

  /// Whether concurrent edits on two devices can collide on a natural key
  /// and need the clash rules rather than plain last-write-wins.
  bool get clashes =>
      this == SyncTable.playlists || this == SyncTable.playlistEntries;

  /// This table in [db].
  TableInfo<Table, DataClass> info(AppDatabase db) => switch (this) {
    SyncTable.tracks => db.tracks,
    SyncTable.playlists => db.playlists,
    SyncTable.playlistEntries => db.playlistEntries,
    SyncTable.ytSeen => db.ytSeen,
    SyncTable.themes => db.themes,
    SyncTable.fonts => db.fonts,
    SyncTable.lyrics => db.lyrics,
    SyncTable.listens => db.listens,
    SyncTable.savedArtists => db.savedArtists,
  };

  static SyncTable fromWire(String wire) =>
      SyncTable.values.firstWhere((t) => t.wire == wire);
}

/// One synced row: a table and the drift data class `toJson()` of the row.
class SyncRow {
  SyncRow(this.table, Map<String, Object?> data)
    : data = Map.unmodifiable(data);

  final SyncTable table;
  final Map<String, Object?> data;

  static const _stampKeys = {'clock', 'originDevice', 'localSeq'};

  String get id => data['id']! as String;
  String get clock => data['clock']! as String;
  String get originDevice => data['originDevice']! as String;
  int get localSeq => data['localSeq']! as int;
  bool get deleted => data['deleted']! as bool;

  /// First 16 hex chars of SHA-256 over the canonical JSON of the data,
  /// leaving out the stamp so equal content hashes equally on any device.
  String get contentHash {
    final sorted = <String, Object?>{
      for (final k
          in (data.keys.where((k) => !_stampKeys.contains(k)).toList()..sort()))
        k: data[k],
    };
    return sha256
        .convert(utf8.encode(jsonEncode(sorted)))
        .toString()
        .substring(0, 16);
  }

  SyncRow withStamp({required String clock, required String originDevice}) =>
      SyncRow(table, {...data, 'clock': clock, 'originDevice': originDevice});

  Map<String, Object?> toWire() => {'table': table.wire, 'data': data};

  factory SyncRow.fromWire(Map<String, Object?> json) => SyncRow(
    SyncTable.fromWire(json['table']! as String),
    Map<String, Object?>.from(json['data']! as Map),
  );

  /// The row as a drift companion with a fresh [localSeq], ready to insert or
  /// upsert. Every column is present, nulls included, so an upsert also sets
  /// columns back to null (a data class would leave its nulls out).
  Insertable<DataClass> toInsertable(int localSeq) {
    final json = <String, dynamic>{...data, 'localSeq': localSeq};
    return switch (table) {
      SyncTable.tracks => Track.fromJson(json).toCompanion(false),
      SyncTable.playlists => Playlist.fromJson(json).toCompanion(false),
      SyncTable.playlistEntries => PlaylistEntry.fromJson(
        json,
      ).toCompanion(false),
      SyncTable.ytSeen => YtSeenData.fromJson(json).toCompanion(false),
      SyncTable.themes => ThemeRow.fromJson(json).toCompanion(false),
      SyncTable.fonts => FontRow.fromJson(json).toCompanion(false),
      SyncTable.lyrics => LyricsRow.fromJson(json).toCompanion(false),
      SyncTable.listens => ListenRow.fromJson(json).toCompanion(false),
      SyncTable.savedArtists => SavedArtist.fromJson(json).toCompanion(false),
    };
  }
}
