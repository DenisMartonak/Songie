import 'dart:collection';

import 'package:drift/drift.dart';

import '../core/hlc.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../stats/listen_store.dart';
import 'sync_row.dart';

/// What one [RowApplier.apply] changed.
class ApplyReport {
  const ApplyReport({
    required this.written,
    required this.playlistIds,
    required this.tracksAdded,
  });

  /// Synced rows written: applied rows plus rows restamped by merging.
  final int written;

  /// Playlists whose row or entries were written.
  final Set<String> playlistIds;

  /// Tracks that did not exist here before and are live afterwards.
  final int tracksAdded;
}

/// Writes a final set of synced rows into the local database and merges rows
/// that are the same thing under two ids (spec "Same thing, two ids").
///
/// Both sides of a sync run this on the same rows, so every choice is
/// deterministic: of rows sharing a natural key the smaller id survives, and
/// a row that changes is changed the same way on either side.
class RowApplier {
  RowApplier(this._db, this._stamp, {DateTime Function() now = DateTime.now})
    : _now = now; // ignore: prefer_initializing_formals

  final AppDatabase _db;
  final SyncStamp _stamp;
  final DateTime Function() _now;

  /// Applies [rows] in one transaction (joining the caller's, if any).
  Future<ApplyReport> apply(List<SyncRow> rows) =>
      _db.transaction(() => _Run(_db, _stamp, _now()).apply(rows));
}

/// Rows are written in this table order, so references are written after the
/// rows they point at.
const _order = [
  SyncTable.tracks,
  SyncTable.playlists,
  SyncTable.fonts,
  SyncTable.themes,
  SyncTable.playlistEntries,
  SyncTable.ytSeen,
  SyncTable.lyrics,
  SyncTable.listens,
];

/// The state of one [RowApplier.apply] call.
class _Run {
  _Run(this._db, this._stamp, DateTime now)
    : _listenCutoffMs = now
          .subtract(ListenStore.retention)
          .millisecondsSinceEpoch;

  final AppDatabase _db;
  final SyncStamp _stamp;
  final int _listenCutoffMs;

  final _seqs = Queue<int>();
  final _playlistIds = <String>{};
  final _addedTracks = <String>{};
  var _written = 0;

  Future<ApplyReport> apply(List<SyncRow> rows) async {
    final sorted = [...rows]
      ..sort((a, b) {
        final t = _order.indexOf(a.table) - _order.indexOf(b.table);
        return t != 0 ? t : a.id.compareTo(b.id);
      });
    if (sorted.isNotEmpty) {
      // Count what would be written now; merges only ever skip more, so
      // this is enough seqs (unused ones leave harmless gaps).
      var n = 0;
      var maxClock = Hlc.parse(sorted.first.clock);
      for (final r in sorted) {
        final c = Hlc.parse(r.clock);
        if (c.compareTo(maxClock) > 0) maxClock = c;
        if (await _decide(r) != null) n++;
      }
      _seqs.addAll(await _stamp.reserve(n, observedClock: maxClock.pack()));
    }
    for (final r in sorted) {
      await _applyOne(r);
    }
    return ApplyReport(
      written: _written,
      playlistIds: _playlistIds,
      tracksAdded: _addedTracks.length,
    );
  }

  /// [r] with its references followed to the end of their merge chains, or
  /// null when it is skipped.
  Future<SyncRow?> _decide(SyncRow r) async {
    if (r.table == SyncTable.listens &&
        (r.data['startedAt']! as int) < _listenCutoffMs) {
      return null;
    }
    final followed = await _follow(r);
    final local = await _local(r.table, r.id);
    if (local != null &&
        (local.contentHash == followed.contentHash ||
            Hlc.parse(local.clock).compareTo(Hlc.parse(r.clock)) >= 0)) {
      return null;
    }
    return followed;
  }

  Future<void> _applyOne(SyncRow incoming) async {
    final followed = await _decide(incoming);
    if (followed == null) return;
    final existed = await _local(incoming.table, incoming.id) != null;
    final row = await _claim(followed);
    if (identical(row, incoming)) {
      await _put(row, _seqs.isNotEmpty ? _seqs.removeFirst() : await _seq());
    } else {
      await _restamp(row);
    }
    switch (row.table) {
      case SyncTable.tracks:
        if (!existed && !row.deleted) _addedTracks.add(row.id);
        final into = row.data['mergedInto'] as String?;
        if (into != null) {
          final end = await _end(_db.tracks, into);
          if (end != row.id) await _trackRefs(row.id, end);
        }
      case SyncTable.playlists:
        final into = row.data['mergedInto'] as String?;
        if (into != null) {
          final end = await _end(_db.playlists, into);
          if (end != row.id) await _playlistRefs(row.id, end);
        }
      case SyncTable.lyrics:
        final end = await _end(_db.tracks, row.id);
        if (end != row.id) await _moveLyrics(row.id, end);
      default:
    }
  }

  Future<int> _seq() async => (await _stamp.reserve(1)).single;

  // --- Following merges -----------------------------------------------------

  Future<SyncRow> _follow(SyncRow r) async {
    final changes = <String, Object?>{};
    Future<void> follow(String key, TableInfo table) async {
      final id = r.data[key]! as String;
      final end = await _end(table, id);
      if (end != id) changes[key] = end;
    }

    switch (r.table) {
      case SyncTable.playlistEntries:
        await follow('trackId', _db.tracks);
        await follow('playlistId', _db.playlists);
      case SyncTable.listens:
        await follow('trackId', _db.tracks);
      case SyncTable.ytSeen:
        await follow('playlistId', _db.playlists);
      default:
    }
    return changes.isEmpty ? r : _with(r, changes);
  }

  /// The end of [id]'s `merged_into` chain in [table] ([id] if not merged).
  Future<String> _end(TableInfo table, String id) async {
    final seen = <String>{id};
    var current = id;
    while (true) {
      final r = await _db
          .customSelect(
            'SELECT merged_into FROM ${table.actualTableName} WHERE id = ?',
            variables: [Variable.withString(current)],
          )
          .getSingleOrNull();
      final next = r?.read<String?>('merged_into');
      if (next == null || !seen.add(next)) return current;
      current = next;
    }
  }

  // --- Natural keys ---------------------------------------------------------

  /// Settles [row]'s natural keys against the local rows before it is
  /// written, and returns it, changed if it lost.
  Future<SyncRow> _claim(SyncRow row) => switch (row.table) {
    SyncTable.tracks => _claimTrack(row),
    SyncTable.playlists => _claimPlaylist(row),
    SyncTable.fonts => _claimFont(row),
    SyncTable.playlistEntries => _claimEntry(row),
    SyncTable.ytSeen => _claimSeen(row),
    _ => Future.value(row),
  };

  /// Tracks: `ytVideoId` and `fileHash` are unique columns, so every other
  /// row holding one of [row]'s keys gives it up. Of live rows the smallest
  /// id survives and the rest merge into it; a deleted row only gives up its
  /// keys (to the live row, or else to the smaller id).
  Future<SyncRow> _claimTrack(SyncRow row) async {
    final video = row.data['ytVideoId'] as String?;
    final hash = row.data['fileHash'] as String?;
    if (video == null && hash == null) return row;
    final others = await _select(
      SyncTable.tracks,
      'id != ? AND (yt_video_id = ? OR file_hash = ?)',
      [row.id, video, hash],
    );
    if (others.isEmpty) return row;
    final winner = _best([row, ...others]);
    for (final x in others) {
      if (x.id == winner.id) continue;
      if (x.deleted) {
        await _restamp(_with(x, _noTrackKeys));
      } else {
        await _mergeTrack(x, winner.id);
      }
    }
    if (winner.id == row.id) return row;
    return _with(row, {
      ..._noTrackKeys,
      if (!row.deleted) ...{'deleted': true, 'mergedInto': winner.id},
    });
  }

  static const _noTrackKeys = {'ytVideoId': null, 'fileHash': null};

  /// Playlists: live ones with the same YouTube URL are one playlist.
  Future<SyncRow> _claimPlaylist(SyncRow row) async {
    final url = row.data['ytPlaylistUrl'] as String?;
    if (row.deleted || url == null) return row;
    final others = await _select(
      SyncTable.playlists,
      'id != ? AND deleted = 0 AND yt_playlist_url = ?',
      [row.id, url],
    );
    final winner = _best([row, ...others]);
    for (final x in others) {
      if (x.id != winner.id) await _mergePlaylist(x, winner.id);
    }
    if (winner.id == row.id) return row;
    return _with(row, {'deleted': true, 'mergedInto': winner.id});
  }

  /// Fonts: live ones with the same file are one font. Nothing references a
  /// font row by id, so the loser is only deleted.
  Future<SyncRow> _claimFont(SyncRow row) async {
    if (row.deleted) return row;
    final others = await _select(
      SyncTable.fonts,
      'id != ? AND deleted = 0 AND file_hash = ?',
      [row.id, row.data['fileHash']],
    );
    final winner = _best([row, ...others]);
    for (final x in others) {
      if (x.id != winner.id) await _restamp(_with(x, {'deleted': true}));
    }
    return winner.id == row.id ? row : _with(row, {'deleted': true});
  }

  /// Entries of a live YouTube playlist: one live entry per song. Local
  /// playlists may hold a song twice, so their entries match only by id.
  Future<SyncRow> _claimEntry(SyncRow row) async {
    if (row.deleted) return row;
    final playlistId = row.data['playlistId']! as String;
    final trackId = row.data['trackId']! as String;
    if (!await _isLiveYt(playlistId)) return row;
    final others = await _liveEntries(playlistId, trackId, except: row.id);
    final winner = _best([row, ...others]);
    for (final x in others) {
      if (x.id != winner.id) await _restamp(_with(x, {'deleted': true}));
    }
    return winner.id == row.id ? row : _with(row, {'deleted': true});
  }

  /// yt_seen: (playlistId, videoId) is a unique key over every row, so the
  /// losers, live or deleted, move to a key of their own.
  Future<SyncRow> _claimSeen(SyncRow row) async {
    final others = await _select(
      SyncTable.ytSeen,
      'id != ? AND playlist_id = ? AND video_id = ?',
      [row.id, row.data['playlistId'], row.data['videoId']],
    );
    if (others.isEmpty) return row;
    final winner = _best([row, ...others]);
    SyncRow vacate(SyncRow r) =>
        _with(r, {'deleted': true, 'videoId': 'merged:${r.id}'});
    for (final x in others) {
      if (x.id != winner.id) await _restamp(vacate(x));
    }
    return winner.id == row.id ? row : vacate(row);
  }

  /// Live rows first, then the smallest id.
  SyncRow _best(List<SyncRow> rows) => rows.reduce((a, b) {
    if (a.deleted != b.deleted) return a.deleted ? b : a;
    return a.id.compareTo(b.id) <= 0 ? a : b;
  });

  // --- Merging --------------------------------------------------------------

  Future<void> _mergeTrack(SyncRow loser, String survivor) async {
    await _restamp(
      _with(loser, {..._noTrackKeys, 'deleted': true, 'mergedInto': survivor}),
    );
    _addedTracks.remove(loser.id);
    await _trackRefs(loser.id, survivor);
  }

  Future<void> _mergePlaylist(SyncRow loser, String survivor) async {
    await _restamp(_with(loser, {'deleted': true, 'mergedInto': survivor}));
    await _playlistRefs(loser.id, survivor);
  }

  /// Points every reference to track [from] at track [to].
  Future<void> _trackRefs(String from, String to) async {
    for (final e in await _select(SyncTable.playlistEntries, 'track_id = ?', [
      from,
    ])) {
      await _restamp(_with(e, {'trackId': to}));
      if (!e.deleted) await _dedupeEntries(e.data['playlistId']! as String, to);
    }
    for (final l in await _select(SyncTable.listens, 'track_id = ?', [from])) {
      await _restamp(_with(l, {'trackId': to}));
    }
    await _moveLyrics(from, to);
    await _moveLocalFile(from, to);
  }

  /// Points every reference to playlist [from] at playlist [to].
  Future<void> _playlistRefs(String from, String to) async {
    final entries = await _select(
      SyncTable.playlistEntries,
      'playlist_id = ?',
      [from],
    );
    for (final e in entries) {
      await _restamp(_with(e, {'playlistId': to}));
    }
    for (final e in entries.where((e) => !e.deleted)) {
      await _dedupeEntries(to, e.data['trackId']! as String);
    }
    for (final s in await _select(SyncTable.ytSeen, 'playlist_id = ?', [
      from,
    ])) {
      await _restamp(await _claimSeen(_with(s, {'playlistId': to})));
    }
    await _mergePrefs(from, to);
  }

  /// Leaves one live entry (the smallest id) of [trackId] in [playlistId]
  /// when that is a live YouTube playlist.
  Future<void> _dedupeEntries(String playlistId, String trackId) async {
    if (!await _isLiveYt(playlistId)) return;
    final live = await _liveEntries(playlistId, trackId);
    if (live.length < 2) return;
    final keep = _best(live);
    for (final x in live) {
      if (x.id != keep.id) await _restamp(_with(x, {'deleted': true}));
    }
  }

  /// Track [from]'s lyrics go to [to] unless [to] has live lyrics of its own;
  /// [from]'s lyrics row is deleted either way.
  Future<void> _moveLyrics(String from, String to) async {
    final mine = await _local(SyncTable.lyrics, from);
    if (mine == null || mine.deleted) return;
    final theirs = await _local(SyncTable.lyrics, to);
    if (theirs == null || theirs.deleted) {
      await _restamp(_with(mine, {'id': to}));
    }
    await _restamp(_with(mine, {'deleted': true}));
  }

  /// Device-local: the survivor keeps its file row, or takes the loser's when
  /// it has none or the loser's is done and its own isn't.
  Future<void> _moveLocalFile(String from, String to) async {
    final files = _db.localFiles;
    final mine = await (_db.select(
      files,
    )..where((f) => f.trackId.equals(from))).getSingleOrNull();
    if (mine == null) return;
    final theirs = await (_db.select(
      files,
    )..where((f) => f.trackId.equals(to))).getSingleOrNull();
    final take =
        theirs == null || (mine.state == 'done' && theirs.state != 'done');
    if (take) {
      await (_db.delete(files)..where((f) => f.trackId.equals(to))).go();
      await (_db.update(files)..where((f) => f.trackId.equals(from))).write(
        LocalFilesCompanion(trackId: Value(to)),
      );
    } else {
      await (_db.delete(files)..where((f) => f.trackId.equals(from))).go();
    }
  }

  /// Device-local: downloads stay on for [to] if they were on for either.
  Future<void> _mergePrefs(String from, String to) async {
    final prefs = _db.playlistDevicePrefs;
    final rows = await (_db.select(
      prefs,
    )..where((p) => p.playlistId.isIn([from, to]))).get();
    if (!rows.any((p) => p.playlistId == from)) return;
    await (_db.delete(prefs)..where((p) => p.playlistId.equals(from))).go();
    await _db
        .into(prefs)
        .insertOnConflictUpdate(
          PlaylistDevicePrefsCompanion.insert(
            playlistId: to,
            downloadEnabled: Value(rows.any((p) => p.downloadEnabled)),
          ),
        );
  }

  // --- Reading and writing --------------------------------------------------

  Future<bool> _isLiveYt(String playlistId) async {
    final p = await _local(SyncTable.playlists, playlistId);
    return p != null && !p.deleted && p.data['source'] == 'yt';
  }

  Future<List<SyncRow>> _liveEntries(
    String playlistId,
    String trackId, {
    String? except,
  }) => _select(
    SyncTable.playlistEntries,
    'deleted = 0 AND playlist_id = ? AND track_id = ? AND id != ?',
    [playlistId, trackId, except ?? ''],
  );

  TableInfo _info(SyncTable t) => switch (t) {
    SyncTable.tracks => _db.tracks,
    SyncTable.playlists => _db.playlists,
    SyncTable.playlistEntries => _db.playlistEntries,
    SyncTable.ytSeen => _db.ytSeen,
    SyncTable.themes => _db.themes,
    SyncTable.fonts => _db.fonts,
    SyncTable.lyrics => _db.lyrics,
    SyncTable.listens => _db.listens,
  };

  Future<SyncRow?> _local(SyncTable t, String id) async {
    final rows = await _select(t, 'id = ?', [id]);
    return rows.isEmpty ? null : rows.single;
  }

  /// Rows of [t] matching [where], ordered by id. Null [args] never match.
  Future<List<SyncRow>> _select(
    SyncTable t,
    String where,
    List<Object?> args,
  ) async {
    final info = _info(t);
    final rows = await _db
        .customSelect(
          'SELECT * FROM ${t.wire} WHERE $where ORDER BY id',
          variables: [for (final a in args) Variable<String>(a as String?)],
          readsFrom: {info},
        )
        .get();
    return [
      for (final r in rows)
        SyncRow(t, (info.map(r.data) as DataClass).toJson()),
    ];
  }

  /// Writes [row] keeping its stamp, with local seq [seq].
  Future<void> _put(SyncRow row, int seq) async {
    await _db
        .into(_info(row.table))
        .insertOnConflictUpdate(_explicitNulls(row.toInsertable(seq)));
    _written++;
    if (row.table == SyncTable.playlists) _playlistIds.add(row.id);
    if (row.table == SyncTable.playlistEntries) {
      _playlistIds.add(row.data['playlistId']! as String);
    }
  }

  /// Writes [row] with a fresh stamp from this device.
  Future<void> _restamp(SyncRow row) async {
    final st = await _stamp.next();
    await _put(
      row.withStamp(clock: st.clock, originDevice: st.originDevice),
      st.localSeq,
    );
  }

  /// A data class writes its null fields as absent, which on update would
  /// keep the old value; a companion built with `nullToAbsent: false`
  /// writes them as null.
  static Insertable<DataClass> _explicitNulls(Insertable<DataClass> d) =>
      switch (d) {
        Track t => t.toCompanion(false),
        Playlist p => p.toCompanion(false),
        PlaylistEntry e => e.toCompanion(false),
        YtSeenData y => y.toCompanion(false),
        ThemeRow t => t.toCompanion(false),
        FontRow f => f.toCompanion(false),
        LyricsRow l => l.toCompanion(false),
        ListenRow l => l.toCompanion(false),
        _ => d,
      };

  static SyncRow _with(SyncRow r, Map<String, Object?> changes) =>
      SyncRow(r.table, {...r.data, ...changes});
}
