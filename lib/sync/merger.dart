import 'package:drift/drift.dart';

import '../core/hlc.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../library/library_repository.dart' show maxPlaylistNameLength;
import 'sync_row.dart';

/// The user's answer to one playlist clash.
enum Resolution { keepMine, keepTheirs, keepBoth }

/// One playlist both devices changed in ways that collide, to ask about.
class PlaylistClash {
  const PlaylistClash({
    required this.playlistId,
    required this.name,
    required this.mineDeleted,
    required this.theirsDeleted,
    required this.mine,
    required this.theirs,
  });

  final String playlistId;

  /// The playlist's name from my changed row if live, else from theirs. Null
  /// when neither side changed the playlist row itself (only its entries):
  /// the caller then reads the name locally.
  final String? name;

  final bool mineDeleted;
  final bool theirsDeleted;

  /// That playlist's changed rows (the playlist and its entries) per side.
  final List<SyncRow> mine;
  final List<SyncRow> theirs;
}

class MergeResult {
  const MergeResult({required this.settled, required this.clashes});

  /// Rows decided without asking.
  final List<SyncRow> settled;
  final List<PlaylistClash> clashes;
}

/// This device's synced rows, as [Merger.resolve] needs them.
abstract class LocalView {
  Future<SyncRow?> row(SyncTable t, String id);

  /// Every entry of [playlistId], tombstones included.
  Future<List<SyncRow>> entriesOf(String playlistId);
}

class DbLocalView implements LocalView {
  DbLocalView(this._db);

  final AppDatabase _db;

  @override
  Future<SyncRow?> row(SyncTable t, String id) async {
    final rows = await _select(t, 'id = ?', id);
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<List<SyncRow>> entriesOf(String playlistId) =>
      _select(SyncTable.playlistEntries, 'playlist_id = ?', playlistId);

  Future<List<SyncRow>> _select(SyncTable t, String where, String arg) async {
    final info = t.info(_db);
    final rows = await _db
        .customSelect(
          'SELECT * FROM ${t.wire} WHERE $where ORDER BY id',
          variables: [Variable.withString(arg)],
          readsFrom: {info},
        )
        .get();
    return [
      for (final r in rows) SyncRow(t, (await info.map(r.data)).toJson()),
    ];
  }
}

/// Settles this device's changed rows ("mine") against a peer's ("theirs").
///
/// Rows are matched per table by id. Rows changed on one side, or the same
/// on both, are taken. Two versions written by the same device never clash:
/// they are that device's earlier and later writes (a peer sends back rows it
/// applied from this device), so the higher clock wins. On the playlist
/// tables, a row both sides changed differently is a clash, and clashes are grouped per playlist for the
/// user to answer once; elsewhere the higher clock wins. Deleting a playlist
/// on one side while the other made any live change to it is a clash of the
/// whole playlist.
///
/// A playlist tombstone left by duplicate merging (`mergedInto` set) is not
/// a user deletion: it never clashes and wins against the other side's
/// version, and entries pointing at the merged-away playlist are moved to
/// the end of its merge chain (as the applier would), so edits to them land
/// in the survivor.
///
/// Known limit: no base version of a row is kept, so changes to different
/// fields of the same row (a rename on one device, a cover on the other)
/// still clash.
class Merger {
  Merger({required this._stamp, required this.peerName});

  final SyncStamp _stamp;
  final String peerName;

  MergeResult merge(List<SyncRow> mine, List<SyncRow> theirs) {
    final into = <String, String>{
      for (final r in [...mine, ...theirs])
        if (_merged(r)) r.id: r.data['mergedInto']! as String,
    };
    final settled = <SyncRow>[];
    final groups = <String, List<(SyncRow?, SyncRow?)>>{};
    for (final pair in _pairs(
      [for (final r in mine) _follow(r, into)],
      [for (final r in theirs) _follow(r, into)],
    )) {
      final row = (pair.$1 ?? pair.$2)!;
      if (row.table.clashes) {
        groups.putIfAbsent(_playlistOf(row), () => []).add(pair);
      } else {
        settled.add(_settle(pair));
      }
    }
    final clashes = <PlaylistClash>[];
    for (final MapEntry(key: playlistId, value: pairs) in groups.entries) {
      final c = _clash(playlistId, pairs);
      if (c == null) {
        settled.addAll(pairs.map(_settle));
      } else {
        clashes.add(c);
      }
    }
    return MergeResult(settled: settled, clashes: clashes);
  }

  /// The final rows: the settled ones plus each clash resolved by [choices]
  /// (keyed by playlist id). Rows the choice decides get fresh stamps that
  /// beat both sides' versions.
  Future<List<SyncRow>> resolve(
    MergeResult r,
    Map<String, Resolution> choices,
    LocalView local,
  ) async {
    final out = [...r.settled];
    if (r.clashes.isEmpty) return out;
    for (final c in r.clashes) {
      final choice = choices[c.playlistId];
      if (choice == null) {
        throw ArgumentError('No choice for playlist ${c.playlistId}');
      }
      if (choice == Resolution.keepBoth && c.theirsDeleted) {
        throw ArgumentError(
          'Cannot keep both of playlist ${c.playlistId}: theirs is deleted',
        );
      }
    }
    // Fresh stamps must sort after every clock seen, the peer's included.
    final clocks = [
      for (final c in r.clashes) ...[...c.mine, ...c.theirs].map(_hlc),
    ];
    await _stamp.reserve(
      0,
      observedClock: clocks
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b)
          .pack(),
    );
    for (final c in r.clashes) {
      out.addAll(await _resolve(c, choices[c.playlistId]!, local));
    }
    return out;
  }

  // --- Merging --------------------------------------------------------------

  /// Rows of both sides matched by table and id, in first-seen order.
  static List<(SyncRow?, SyncRow?)> _pairs(
    List<SyncRow> mine,
    List<SyncRow> theirs,
  ) {
    final pairs = <String, (SyncRow?, SyncRow?)>{};
    for (final m in mine) {
      pairs[_key(m)] = (m, null);
    }
    for (final t in theirs) {
      pairs[_key(t)] = (pairs[_key(t)]?.$1, t);
    }
    return pairs.values.toList();
  }

  /// Whether [r] is a playlist merged away into another by sync.
  static bool _merged(SyncRow? r) =>
      r != null &&
      r.table == SyncTable.playlists &&
      r.data['mergedInto'] != null;

  /// [r], an entry, pointed at the end of its playlist's merge chain in
  /// [into]; any other row as it is.
  static SyncRow _follow(SyncRow r, Map<String, String> into) {
    if (r.table != SyncTable.playlistEntries) return r;
    final from = r.data['playlistId']! as String;
    final seen = {from};
    var end = from;
    for (var next = into[end]; next != null && seen.add(next);) {
      end = next;
      next = into[end];
    }
    return end == from ? r : SyncRow(r.table, {...r.data, 'playlistId': end});
  }

  static String _key(SyncRow r) => '${r.table.wire}/${r.id}';

  static String _playlistOf(SyncRow r) =>
      r.table == SyncTable.playlists ? r.id : r.data['playlistId']! as String;

  static Hlc _hlc(SyncRow r) => Hlc.parse(r.clock);

  /// The row taken without asking: the only one, either of two equal ones,
  /// a merge tombstone, or the one with the higher clock.
  static SyncRow _settle((SyncRow?, SyncRow?) pair) {
    final (a, b) = pair;
    if (a == null) return b!;
    if (b == null || a.contentHash == b.contentHash) return a;
    if (_merged(a) != _merged(b)) return _merged(a) ? a : b;
    return _hlc(a).compareTo(_hlc(b)) >= 0 ? a : b;
  }

  /// Both versions were written by the same device, one after the other: not
  /// concurrent, so the higher clock simply wins. This is how a device's own
  /// earlier write comes back from a peer that applied it in the last sync.
  static bool _sameOrigin((SyncRow?, SyncRow?) pair) {
    final (a, b) = pair;
    return a != null && b != null && a.originDevice == b.originDevice;
  }

  /// Both sides changed the row differently. Two tombstones never clash, nor
  /// does a merge tombstone, nor two versions from the same device.
  static bool _differ((SyncRow?, SyncRow?) pair) {
    final (a, b) = pair;
    return a != null &&
        b != null &&
        a.contentHash != b.contentHash &&
        !_sameOrigin(pair) &&
        !(a.deleted && b.deleted) &&
        !_merged(a) &&
        !_merged(b);
  }

  static SyncRow? _playlistRow(List<SyncRow> rows) {
    for (final r in rows) {
      if (r.table == SyncTable.playlists) return r;
    }
    return null;
  }

  static PlaylistClash? _clash(
    String playlistId,
    List<(SyncRow?, SyncRow?)> pairs,
  ) {
    final mine = [for (final p in pairs) ?p.$1];
    final theirs = [for (final p in pairs) ?p.$2];
    final minePl = _playlistRow(mine);
    final theirPl = _playlistRow(theirs);
    // A merged-away playlist's changes go to its survivor, so a deletion of
    // it on either side is not one the user is asked about.
    final merged = _merged(minePl) || _merged(theirPl);
    final mineDeleted = !merged && (minePl?.deleted ?? false);
    final theirsDeleted = !merged && (theirPl?.deleted ?? false);
    // A live version paired with one from the same device is that device's
    // older or newer write, not a change made against the deletion.
    bool liveChange(SyncRow? r, (SyncRow?, SyncRow?) p) =>
        r != null && !r.deleted && !_sameOrigin(p);
    final clash =
        pairs.any(_differ) ||
        (mineDeleted && pairs.any((p) => liveChange(p.$2, p))) ||
        (theirsDeleted && pairs.any((p) => liveChange(p.$1, p)));
    if (!clash) return null;
    final named = [
      if (minePl != null && !mineDeleted) minePl,
      if (theirPl != null && !theirsDeleted) theirPl,
      ?minePl,
      ?theirPl,
    ];
    return PlaylistClash(
      playlistId: playlistId,
      name: named.isEmpty ? null : named.first.data['name']! as String,
      mineDeleted: mineDeleted,
      theirsDeleted: theirsDeleted,
      mine: mine,
      theirs: theirs,
    );
  }

  // --- Resolving ------------------------------------------------------------

  Future<List<SyncRow>> _resolve(
    PlaylistClash c,
    Resolution choice,
    LocalView local,
  ) async {
    final theirsWin = choice == Resolution.keepTheirs;
    final win = theirsWin ? c.theirs : c.mine;
    final lose = theirsWin ? c.mine : c.theirs;
    final winDeleted = theirsWin ? c.theirsDeleted : c.mineDeleted;
    final loseDeleted = theirsWin ? c.mineDeleted : c.theirsDeleted;
    final out = winDeleted
        ? await _deletionWins(c, win, lose, local)
        : loseDeleted
        ? await _editWins(c, theirsWin, win, lose, local)
        : await _pick(win, lose);
    if (choice == Resolution.keepBoth) out.addAll(await _copyTheirs(c, local));
    return out;
  }

  /// Every row of the group: the winner's version of each clashing row,
  /// restamped; every other change as it is.
  Future<List<SyncRow>> _pick(List<SyncRow> win, List<SyncRow> lose) async => [
    for (final pair in _pairs(win, lose))
      _differ(pair) ? await _restamp(pair.$1!) : _settle(pair),
  ];

  /// The playlist tombstone and a tombstone for every entry anyone has live
  /// or changed, all restamped.
  Future<List<SyncRow>> _deletionWins(
    PlaylistClash c,
    List<SyncRow> win,
    List<SyncRow> lose,
    LocalView local,
  ) async {
    final out = [await _restamp(_playlistRow(win)!)];
    final versions = <String, List<SyncRow>>{};
    void add(SyncRow e) => versions.putIfAbsent(e.id, () => []).add(e);
    // Winner first, so its version is the base of the tombstone.
    for (final e in [...win, ...lose]) {
      if (e.table == SyncTable.playlistEntries) add(e);
    }
    final changed = versions.keys.toSet();
    (await local.entriesOf(c.playlistId)).forEach(add);
    for (final id in versions.keys.toList()..sort()) {
      final vs = versions[id]!;
      if (!changed.contains(id) && vs.every((e) => e.deleted)) continue;
      out.add(await _restamp(vs.first, const {'deleted': true}));
    }
    return out;
  }

  /// The winner's playlist row, live, and its view of the entries, restamped;
  /// the loser's changes to entries outside that view as they are.
  Future<List<SyncRow>> _editWins(
    PlaylistClash c,
    bool theirsWin,
    List<SyncRow> win,
    List<SyncRow> lose,
    LocalView local,
  ) async {
    final playlist =
        _playlistRow(win) ??
        await local.row(SyncTable.playlists, c.playlistId) ??
        _playlistRow(lose)!;
    final out = [
      await _restamp(playlist, const {'deleted': false}),
    ];
    final view = await _view(c, local, theirs: theirsWin);
    final changed = {
      for (final e in [...win, ...lose])
        if (e.table == SyncTable.playlistEntries) e.id,
    };
    for (final id in view.keys.toList()..sort()) {
      final e = view[id]!;
      if (!e.deleted || changed.contains(id)) out.add(await _restamp(e));
    }
    for (final e in lose) {
      if (e.table == SyncTable.playlistEntries && !view.containsKey(e.id)) {
        out.add(e);
      }
    }
    return out;
  }

  /// Their playlist as a new local playlist of this device's, with their
  /// live entries.
  Future<List<SyncRow>> _copyTheirs(PlaylistClash c, LocalView local) async {
    final base =
        _playlistRow(c.theirs) ??
        await local.row(SyncTable.playlists, c.playlistId);
    if (base == null) throw StateError('Playlist ${c.playlistId} not found');
    final st = await _stamp.next();
    final copy = SyncRow(SyncTable.playlists, {
      ...base.data,
      'id': st.id,
      'clock': st.clock,
      'originDevice': st.originDevice,
      'deleted': false,
      'name': _cut('${base.data['name']} (from $peerName)'),
      'source': 'local',
      'ytPlaylistUrl': null,
      'lastYtSyncAt': null,
      'mergedInto': null,
    });
    final out = [copy];
    final view = await _view(c, local, theirs: true);
    final live = view.values.where((e) => !e.deleted).toList()
      ..sort((a, b) {
        final p = (a.data['position']! as String).compareTo(
          b.data['position']! as String,
        );
        return p != 0 ? p : a.id.compareTo(b.id);
      });
    for (final e in live) {
      final st = await _stamp.next();
      out.add(
        SyncRow(SyncTable.playlistEntries, {
          ...e.data,
          'id': st.id,
          'playlistId': copy.id,
          'clock': st.clock,
          'originDevice': st.originDevice,
        }),
      );
    }
    return out;
  }

  /// One side's entries of the clash's playlist, by id: the local ones
  /// overlaid with that side's changes. Their view also undoes this device's
  /// entry tombstones when this device deleted the playlist, since their
  /// device still has those songs.
  Future<Map<String, SyncRow>> _view(
    PlaylistClash c,
    LocalView local, {
    required bool theirs,
  }) async {
    final view = {for (final e in await local.entriesOf(c.playlistId)) e.id: e};
    for (final e in c.mine) {
      if (e.table == SyncTable.playlistEntries) view[e.id] = e;
    }
    if (!theirs) return view;
    if (c.mineDeleted) {
      for (final e in c.mine) {
        if (e.table == SyncTable.playlistEntries && e.deleted) {
          view[e.id] = SyncRow(e.table, {...e.data, 'deleted': false});
        }
      }
    }
    for (final e in c.theirs) {
      if (e.table == SyncTable.playlistEntries) view[e.id] = e;
    }
    return view;
  }

  /// [row] with [changes] and a fresh stamp from this device.
  Future<SyncRow> _restamp(
    SyncRow row, [
    Map<String, Object?> changes = const {},
  ]) async {
    final st = await _stamp.next(id: row.id);
    return SyncRow(row.table, {
      ...row.data,
      ...changes,
    }).withStamp(clock: st.clock, originDevice: st.originDevice);
  }

  /// [s] cut to the playlist name limit, never inside a surrogate pair.
  static String _cut(String s) {
    if (s.length <= maxPlaylistNameLength) return s;
    var end = maxPlaylistNameLength;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
  }
}
