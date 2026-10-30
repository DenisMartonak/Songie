import 'package:drift/drift.dart';
import 'package:songies/data/database.dart';

import 'sync_row.dart';

class ChangePage {
  const ChangePage(this.rows, this.next);

  final List<SyncRow> rows;

  /// The last row's seq when more rows remain, else null.
  final int? next;
}

/// Reads the rows of every synced table changed since a given local seq.
class ChangeFeed {
  ChangeFeed(this._db);

  final AppDatabase _db;

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
}
