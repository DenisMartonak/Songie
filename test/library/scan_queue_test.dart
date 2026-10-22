import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/library/scan_queue.dart';

ScanProgress progress(int processed, {bool done = false}) => ScanProgress(
  found: 10,
  processed: processed,
  added: processed,
  unchanged: 0,
  skipped: 0,
  done: done,
);

/// A scan the test finishes by hand.
class FakeScan {
  FakeScan(this.folder, this.playlist);
  final String folder;
  final String? playlist;
  final controller = StreamController<ScanProgress>();
  bool registerFolder = true;
}

void main() {
  late List<FakeScan> started;
  late ScanQueue queue;

  setUp(() {
    // AppLog prints to the console when no log file is set up.
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    addTearDown(() => debugPrint = originalDebugPrint);
    started = [];
    queue = ScanQueue((folder, {createPlaylistNamed, registerFolder = true}) {
      final scan = FakeScan(folder, createPlaylistNamed)
        ..registerFolder = registerFolder;
      started.add(scan);
      return scan.controller.stream;
    });
  });

  test('passes registerFolder through, registering by default', () async {
    unawaited(queue.enqueue('/a'));
    unawaited(queue.enqueue('/b', registerFolder: false));
    await pumpEventQueue();
    expect(started.single.registerFolder, isTrue);
    started[0].controller
      ..add(progress(1, done: true))
      ..close();
    await pumpEventQueue();
    expect(started[1].registerFolder, isFalse);
    started[1].controller
      ..add(progress(1, done: true))
      ..close();
  });

  test('runs scans one at a time, in order', () async {
    final first = queue.enqueue('/a', createPlaylistNamed: 'A');
    final second = queue.enqueue('/b');
    await pumpEventQueue();
    expect([for (final s in started) s.folder], ['/a']);
    expect(started.single.playlist, 'A');

    started[0].controller
      ..add(progress(10, done: true))
      ..close();
    expect((await first)?.done, isTrue);
    await pumpEventQueue();
    expect([for (final s in started) s.folder], ['/a', '/b']);
    expect(started[1].playlist, isNull);

    started[1].controller
      ..add(progress(3, done: true))
      ..close();
    expect((await second)?.processed, 3);
  });

  test('returns the last progress, or null for an empty stream', () async {
    final result = queue.enqueue('/a');
    await pumpEventQueue();
    started[0].controller
      ..add(progress(5))
      ..add(progress(10, done: true))
      ..close();
    expect((await result)?.processed, 10);

    final empty = queue.enqueue('/b');
    await pumpEventQueue();
    await started[1].controller.close();
    expect(await empty, isNull);
  });

  test('a failing scan rejects its caller and the queue carries on', () async {
    final failing = queue.enqueue('/missing');
    final next = queue.enqueue('/b');
    // Registered up front so the rejection is never unhandled.
    final failure = expectLater(failing, throwsA(isA<StateError>()));
    await pumpEventQueue();
    started[0].controller.addError(StateError('no such folder'));
    await started[0].controller.close();
    await failure;

    await pumpEventQueue();
    expect([for (final s in started) s.folder], ['/missing', '/b']);
    started[1].controller
      ..add(progress(1, done: true))
      ..close();
    expect((await next)?.done, isTrue);
  });

  test('a scan function that throws immediately is surfaced too', () async {
    final throwing = ScanQueue(
      (folder, {createPlaylistNamed, registerFolder = true}) =>
          throw StateError('boom'),
    );
    await expectLater(throwing.enqueue('/x'), throwsA(isA<StateError>()));
    // And the queue is still usable.
    await expectLater(throwing.enqueue('/y'), throwsA(isA<StateError>()));
  });

  test('current reports progress and is null when idle', () async {
    final seen = <ScanProgress?>[];
    final sub = queue.current.listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, [null]);

    final done = queue.enqueue('/a');
    await pumpEventQueue();
    started[0].controller.add(progress(4));
    await pumpEventQueue();
    expect(seen.last?.processed, 4);

    started[0].controller
      ..add(progress(10, done: true))
      ..close();
    await done;
    await pumpEventQueue();
    expect(seen.last, isNull);
  });

  test(
    'current is null between a failure and the next scan only at idle',
    () async {
      final seen = <ScanProgress?>[];
      final sub = queue.current.listen(seen.add);
      addTearDown(sub.cancel);

      final failing = queue.enqueue('/a');
      final failure = expectLater(failing, throwsA(anything));
      final next = queue.enqueue('/b');
      await pumpEventQueue();
      started[0].controller.addError('bad');
      await started[0].controller.close();
      await failure;
      await pumpEventQueue();
      // Still busy: /b is running, so the last value is not idle.
      expect(seen.last, isNotNull);

      started[1].controller.close();
      await next;
      await pumpEventQueue();
      expect(seen.last, isNull);
    },
  );

  test('a late listener gets the current value first', () async {
    final scanning = queue.enqueue('/a');
    await pumpEventQueue();
    started[0].controller.add(progress(7));
    await pumpEventQueue();

    expect((await queue.current.first)?.processed, 7);

    started[0].controller.close();
    await scanning;
    await pumpEventQueue();
    expect(await queue.current.first, isNull);
  });
}
