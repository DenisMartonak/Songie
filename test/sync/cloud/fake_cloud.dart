import 'dart:async';
import 'dart:convert';

import 'package:songies/core/hlc.dart';
import 'package:songies/sync/cloud/cloud_remote.dart';
import 'package:songies/sync/sync_row.dart';

/// The server side of cloud sync in memory: rows per user, a server seq
/// that grows on every write, and the newer-clock rule of `push_rows`.
class FakeServer {
  final _rows = <String, Map<String, (int, Map<String, dynamic>)>>{};
  var _seq = 0;
  final _topics = <String, StreamController<void>>{};

  /// Whether a push that wrote rows tells the user's devices (Realtime).
  bool notify = false;

  int write(String user, List<SyncRow> rows) {
    final mine = _rows.putIfAbsent(user, () => {});
    var written = 0;
    for (final r in rows) {
      // Through JSON, as jsonb would.
      final wire =
          jsonDecode(jsonEncode(rowToServer(r))) as Map<String, dynamic>;
      final key = '${r.table.wire}/${r.id}';
      final old = mine[key];
      if (old != null &&
          Hlc.parse(wire['clock'] as String)
                  .compareTo(Hlc.parse(old.$2['clock'] as String)) <=
              0) {
        continue;
      }
      mine[key] = (++_seq, {...wire, 'server_seq': _seq});
      written++;
    }
    if (written > 0 && notify) broadcast(user);
    return written;
  }

  List<(int, SyncRow)> read(String user, int after, int max) {
    final rows =
        (_rows[user]?.values ?? const <(int, Map<String, dynamic>)>[])
            .where((e) => e.$1 > after)
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (final e in rows.take(max))
        rowFromServer(jsonDecode(jsonEncode(e.$2)) as Map<String, dynamic>),
    ];
  }

  /// The user's rows as `'<wire>/<id>'` to their data.
  Map<String, Map<String, dynamic>> rowsOf(String user) => {
    for (final e in (_rows[user] ?? const {}).entries)
      e.key: e.value.$2['data'] as Map<String, dynamic>,
  };

  Stream<void> topic(String user) =>
      _topics.putIfAbsent(user, StreamController<void>.broadcast).stream;

  /// A Realtime message to [user]'s devices.
  void broadcast(String user) =>
      _topics.putIfAbsent(user, StreamController<void>.broadcast).add(null);
}

/// One device's [CloudRemote] on a [FakeServer], counting every call.
class FakeRemote implements CloudRemote {
  FakeRemote(this.server);

  final FakeServer server;

  /// Who is signed in (the server's `auth.uid()`).
  String? user;

  var pushCalls = 0;
  var pullCalls = 0;
  var changesCalls = 0;
  var closeCalls = 0;

  /// Every push attempted, failed ones too.
  final pushes = <List<SyncRow>>[];

  /// Pushes still to fail (as offline).
  var failPushes = 0;

  /// Every call fails as offline.
  var offline = false;

  /// Runs inside each push, before it writes.
  Future<void> Function()? duringPush;

  int get calls => pushCalls + pullCalls + changesCalls + closeCalls;

  @override
  Future<int> push(List<SyncRow> rows) async {
    pushCalls++;
    pushes.add(rows);
    if (rows.length > 500) throw StateError('more than 500 rows');
    await duringPush?.call();
    if (offline) throw const CloudOffline();
    if (failPushes > 0) {
      failPushes--;
      throw const CloudOffline();
    }
    return server.write(user!, rows);
  }

  @override
  Future<List<(int, SyncRow)>> pull(int after, {int max = 500}) async {
    pullCalls++;
    await Future<void>.delayed(Duration.zero);
    if (offline) throw const CloudOffline();
    return server.read(user!, after, max);
  }

  @override
  Stream<void> changes(String userId) {
    changesCalls++;
    return server.topic(userId);
  }

  @override
  Future<void> close() async => closeCalls++;
}
