import 'dart:async';

import 'package:drift/drift.dart';

/// Like a drift `watch()`, for a query that is costly to re-run: [read]
/// runs on listen, then after writes to [tables], at most once per [every]
/// while writes keep coming. The first write after a quiet spell runs it
/// at once; later ones wait for the spell to end and run it once.
Stream<T> throttledWatch<T>(
  GeneratedDatabase db,
  Set<ResultSetImplementation<dynamic, dynamic>> tables,
  Future<T> Function() read, {
  required Duration every,
}) {
  late final StreamController<T> out;
  StreamSubscription<Set<TableUpdate>>? sub;
  Timer? timer;
  // Since the last run a write caused.
  final since = Stopwatch();
  var running = false;
  var dirty = false;

  late void Function() onWrite;

  Future<void> run() async {
    running = true;
    try {
      final v = await read();
      if (!out.isClosed) out.add(v);
    } catch (e, s) {
      if (!out.isClosed) out.addError(e, s);
    }
    running = false;
    if (dirty && !out.isClosed) {
      dirty = false;
      onWrite();
    }
  }

  void runNow() {
    since
      ..reset()
      ..start();
    unawaited(run());
  }

  onWrite = () {
    // A write during a run: once more after it, as it may not show it.
    if (running) {
      dirty = true;
      return;
    }
    if (timer != null) return;
    if (!since.isRunning || since.elapsed >= every) {
      runNow();
      return;
    }
    timer = Timer(every - since.elapsed, () {
      timer = null;
      runNow();
    });
  };

  out = StreamController<T>(
    onListen: () {
      sub = db
          .tableUpdates(TableUpdateQuery.onAllTables(tables))
          .listen((_) => onWrite());
      unawaited(run());
    },
    onCancel: () async {
      timer?.cancel();
      timer = null;
      await sub?.cancel();
    },
  );
  return out.stream;
}
