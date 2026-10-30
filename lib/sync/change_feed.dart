import 'package:drift/drift.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';

import 'sync_row.dart';

class ChangePage {
  const ChangePage(this.rows, this.next);

  final List<SyncRow> rows;

  /// The last row's seq when more rows remain, else null.
  final int? next;
}

/// Reads the rows of every synced table changed since a given local seq.
class ChangeFeed {
  /// [stamp] (this device's) lets [safeHigh] see seqs issued but not yet
  /// written.
  ChangeFeed(this._db, {this._stamp});

  final AppDatabase _db;
  final SyncStamp? _stamp;

  TableInfo _info(SyncTable t) => t.info(_db);

  Future<ChangePage> since(int seq, {int limit = 500}) async {
    final all = <SyncRow>[];
    for (final t in SyncTable.values) {
      final info = _info(t);
      final rows = await _db
          .customSelect(
            'SELECT * FROM ${t.wire} WHERE local_seq > ? '
            'ORDER BY local_seq LIMIT ?',
            variables: [Variable.withInt(seq), Variable.withInt(limit + 1)],
            readsFrom: {info},
          )
          .get();
      for (final r in rows) {
        final d = info.map(r.data) as DataClass;
        all.add(SyncRow(t, d.toJson()));
      }
    }
    all.sort((a, b) => a.localSeq.compareTo(b.localSeq));
    if (all.length <= limit) return ChangePage(all, null);
    final page = all.sublist(0, limit);
    return ChangePage(page, page.last.localSeq);
  }

  Future<int> highSeq() async {
    var high = 0;
    for (final t in SyncTable.values) {
      final r = await _db
          .customSelect('SELECT MAX(local_seq) AS m FROM ${t.wire}')
          .getSingle();
      final m = r.read<int?>('m');
      if (m != null && m > high) high = m;
    }
    return high;
  }

  /// The highest seq a sync watermark may move to: [highSeq], but below the
  /// lowest seq issued in the last [SyncStamp.pendingWindow] that is still
  /// pending, since its write may still land and must not be skipped.
  ///
  /// An issued seq with no row is pending unless a row with its stamp's id
  /// has a higher seq: that row was written and then overwritten by a later
  /// write (a playlist created, then renamed). A seq that never gets a row (a
  /// rolled-back write) holds it back only until it leaves that window; rows
  /// above it are just sent again.
  Future<int> safeHigh() async {
    final high = await highSeq();
    final recent = [...?_stamp?.recentStamps().where((s) => s.$1 <= high)];
    if (recent.isEmpty) return high;
    final present = <int>{};
    for (final t in SyncTable.values) {
      final rows = await _db
          .customSelect(
            'SELECT local_seq AS s FROM ${t.wire} '
            'WHERE local_seq BETWEEN ? AND ?',
            variables: [
              Variable.withInt(recent.first.$1),
              Variable.withInt(high),
            ],
          )
          .get();
      present.addAll(rows.map((r) => r.read<int>('s')));
    }
    for (final (seq, id) in recent) {
      if (!present.contains(seq) && !await _overwritten(id, seq)) {
        return seq - 1;
      }
    }
    return high;
  }

  /// Whether a row with [id] has a seq above [seq].
  Future<bool> _overwritten(String id, int seq) async {
    for (final t in SyncTable.values) {
      final rows = await _db
          .customSelect(
            'SELECT 1 FROM ${t.wire} WHERE id = ? AND local_seq > ? LIMIT 1',
            variables: [Variable.withString(id), Variable.withInt(seq)],
          )
          .get();
      if (rows.isNotEmpty) return true;
    }
    return false;
  }
}
