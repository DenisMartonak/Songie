import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/stats/listen_recorder.dart';
import 'package:songies/stats/listen_store.dart';

Track _track(String id, {int durationMs = 200000}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'T$id',
  artist: 'A',
  durationMs: durationMs,
  unavailable: false,
  searchText: 't a',
);

/// Records calls; [rows] holds what a real table would contain.
class _FakeStore implements ListenStore {
  final calls = <String>[];
  final rows = <String, (Duration, bool)>{};
  final startedAt = <String, DateTime>{};
  final updates = <String, List<Duration>>{};
  bool throwOnUpdate = false;
  bool failStart = false;
  Completer<void>? startGate;
  var _n = 0;

  @override
  Future<String?> start(
    Track t,
    DateTime startedAtUtc,
    Duration heard,
    bool counted,
  ) async {
    calls.add('start ${t.id} ${heard.inSeconds}');
    final g = startGate;
    if (g != null) await g.future;
    if (failStart) return null;
    final id = 'L${++_n}';
    rows[id] = (heard, counted);
    startedAt[id] = startedAtUtc;
    updates[id] = [];
    return id;
  }

  @override
  Future<void> update(String id, Duration heard, bool counted) async {
    calls.add('update $id ${heard.inSeconds}');
    if (throwOnUpdate) throw StateError('disk full');
    rows[id] = (heard, counted);
    updates[id]!.add(heard);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _settle() => pumpEventQueue();

void main() {
  late StreamController<PlayerState> states;
  late StreamController<Track> starts;
  late _FakeStore store;
  late ListenRecorder recorder;
  final now = DateTime.utc(2026, 10, 29, 12);
  final a = _track('a');
  final b = _track('b');

  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
    states = StreamController<PlayerState>.broadcast(sync: true);
    starts = StreamController<Track>.broadcast(sync: true);
    store = _FakeStore();
    recorder = ListenRecorder(
      states.stream,
      starts.stream,
      store,
      now: () => now,
    );
  });
  tearDown(() async {
    recorder.dispose();
    await states.close();
    await starts.close();
  });

  void tick(
    Track t,
    int ms, {
    bool playing = true,
    bool buffering = false,
    Duration? duration,
  }) => states.add(
    PlayerState(
      queue: [a, b, if (t != a && t != b) t],
      index: t == a ? 0 : (t == b ? 1 : 2),
      playing: playing,
      buffering: buffering,
      position: Duration(milliseconds: ms),
      duration: duration,
    ),
  );

  /// Plays [from]..[to] seconds of [t] in 1 s steps.
  void play(Track t, int from, int to, {Duration? duration}) {
    for (var s = from; s <= to; s++) {
      tick(t, s * 1000, duration: duration);
    }
  }

  Future<(Duration, bool)> finish(String id) async {
    recorder.dispose();
    await _settle();
    return store.rows[id]!;
  }

  group('heard time (Review Focus 1)', () {
    test(
      '20 s, a 60 s pause, then 15 s is one listen of 35 s, counted',
      () async {
        starts.add(a);
        play(a, 0, 20);
        for (var i = 0; i < 60; i++) {
          tick(a, 20000, playing: false);
        }
        play(a, 20, 35);
        expect(await finish('L1'), (const Duration(seconds: 35), true));
        expect(store.calls.where((c) => c.startsWith('start')), hasLength(1));
      },
    );

    test('a seek from 10 s to 3:00 adds nothing', () async {
      starts.add(a);
      play(a, 0, 10);
      play(a, 180, 185);
      expect(await finish('L1'), (const Duration(seconds: 15), false));
    });

    test('buffering ticks add nothing', () async {
      starts.add(a);
      play(a, 0, 10);
      for (var s = 10; s <= 15; s++) {
        tick(a, s * 1000, buffering: true);
      }
      play(a, 15, 20);
      expect(await finish('L1'), (const Duration(seconds: 15), false));
    });

    test(
      'a short song played whole counts, using the state duration',
      () async {
        final short = _track('s', durationMs: 0);
        starts.add(short);
        play(short, 0, 20, duration: const Duration(seconds: 20));
        expect(await finish('L1'), (const Duration(seconds: 20), true));
      },
    );

    test('without a state duration the track length is used', () async {
      final short = _track('s', durationMs: 20000);
      starts.add(short);
      play(short, 0, 20);
      expect(await finish('L1'), (const Duration(seconds: 20), true));
    });
  });

  group('new listens (Review Focus 2)', () {
    test('repeat-one: 2:00 then 10 s gives two rows', () async {
      starts.add(a);
      play(a, 0, 120);
      tick(a, 0);
      starts.add(a);
      play(a, 1, 10);
      await finish('L2');
      expect(store.rows['L1'], (const Duration(seconds: 120), true));
      expect(store.rows['L2'], (const Duration(seconds: 10), false));
    });

    test('a "previous" restart after 1:00 gives two rows', () async {
      starts.add(a);
      play(a, 0, 60);
      starts.add(a);
      tick(a, 0);
      play(a, 1, 5);
      await finish('L2');
      expect(store.rows['L1'], (const Duration(seconds: 60), true));
      expect(store.rows['L2'], (const Duration(seconds: 5), false));
    });

    test('pausing and seeking never start a new listen', () async {
      starts.add(a);
      play(a, 0, 10);
      tick(a, 10000, playing: false);
      play(a, 0, 5); // seek back to 0:00 and play
      await finish('L1');
      expect(store.calls.where((c) => c.startsWith('start')), hasLength(1));
      expect(store.rows['L1']!.$1, const Duration(seconds: 15));
    });

    test('a start followed by an immediate skip writes no row', () async {
      starts.add(a);
      tick(a, 0);
      starts.add(b);
      play(b, 0, 0);
      recorder.dispose();
      await _settle();
      expect(store.calls, isEmpty);
    });

    test('a null current track closes the listen', () async {
      starts.add(a);
      play(a, 0, 40);
      states.add(const PlayerState());
      await _settle();
      expect(store.rows['L1'], (const Duration(seconds: 40), true));
      final n = store.calls.length;
      recorder.dispose();
      await _settle();
      expect(store.calls, hasLength(n));
    });
  });

  group('start event ordering', () {
    test('same track, state at 0 before the start event', () async {
      starts.add(a);
      play(a, 0, 40);
      tick(a, 0);
      starts.add(a);
      play(a, 1, 10);
      await finish('L2');
      expect(store.rows['L1']!.$1, const Duration(seconds: 40));
      expect(store.rows['L2']!.$1, const Duration(seconds: 10));
    });

    test('same track, start event before the old song\'s last step', () async {
      starts.add(a);
      play(a, 0, 40);
      starts.add(a);
      tick(a, 41000); // the old play's last tick, late
      tick(a, 0);
      play(a, 1, 10);
      await finish('L2');
      expect(store.rows['L1']!.$1, const Duration(seconds: 40));
      expect(store.rows['L2']!.$1, const Duration(seconds: 10));
    });

    test('new track, its states before the start event', () async {
      starts.add(a);
      play(a, 0, 40);
      play(b, 0, 1);
      starts.add(b);
      play(b, 2, 10);
      await finish('L2');
      expect(store.rows['L1']!.$1, const Duration(seconds: 40));
      expect(store.rows['L2']!.$1, const Duration(seconds: 10));
    });

    test('new track, the start event before its states', () async {
      starts.add(a);
      play(a, 0, 40);
      starts.add(b);
      tick(a, 41000); // the old song's last tick, late
      play(b, 0, 10);
      await finish('L2');
      expect(store.rows['L1']!.$1, const Duration(seconds: 40));
      expect(store.rows['L2']!.$1, const Duration(seconds: 10));
    });
  });

  group('saving', () {
    test('startedAt is when the first heard time arrived, minus it', () async {
      starts.add(a);
      tick(a, 1500);
      await _settle();
      expect(store.calls, ['start a 1']);
      expect(
        store.startedAt['L1'],
        now.subtract(const Duration(milliseconds: 1500)),
      );
    });

    test('checkpoints about every 30 s of heard time, then a final', () async {
      starts.add(a);
      play(a, 0, 95);
      await finish('L1');
      expect(store.updates['L1'], const [
        Duration(seconds: 30),
        Duration(seconds: 60),
        Duration(seconds: 90),
        Duration(seconds: 95),
      ]);
    });

    test('75 s then dispose without a final state keeps 75 s', () async {
      starts.add(a);
      play(a, 0, 75);
      final row = await finish('L1');
      expect(row.$1, const Duration(seconds: 75));
    });

    test('a failing final update leaves the 60 s checkpoint', () async {
      starts.add(a);
      play(a, 0, 75);
      await _settle();
      store.throwOnUpdate = true;
      final row = await finish('L1');
      expect(row, (const Duration(seconds: 60), true));
      expect(store.calls.last, 'update L1 75');
    });

    test(
      'updates due before start returns wait for its id, in order',
      () async {
        store.startGate = Completer<void>();
        starts.add(a);
        play(a, 0, 65);
        await _settle();
        expect(store.calls, ['start a 1']);
        store.startGate!.complete();
        store.startGate = null;
        await _settle();
        expect(store.calls, ['start a 1', 'update L1 30', 'update L1 60']);
        await finish('L1');
        expect(store.calls.last, 'update L1 65');
      },
    );

    test('a listen whose start failed gets no updates', () async {
      store.failStart = true;
      starts.add(a);
      play(a, 0, 40);
      recorder.dispose();
      await _settle();
      expect(store.calls, ['start a 1']);
    });

    test('nothing is written after dispose', () async {
      starts.add(a);
      play(a, 0, 10);
      recorder.dispose();
      await _settle();
      final n = store.calls.length;
      starts.add(b);
      play(b, 0, 40);
      await _settle();
      expect(store.calls, hasLength(n));
    });

    test('queue end then a later start: one row with the heard time', () async {
      starts.add(a);
      play(a, 0, 40);
      tick(a, 0, playing: false); // queue end: still current, at 0:00
      await _settle();
      expect(store.rows['L1'], (const Duration(seconds: 40), true));
      final n = store.calls.length;
      starts.add(b);
      await _settle();
      expect(store.calls, hasLength(n));
      expect(store.rows.keys, ['L1']);
    });

    test('a 20 s song heard to the queue end is saved counted', () async {
      final short = _track('s', durationMs: 20000);
      const length = Duration(seconds: 20);
      starts.add(short);
      play(short, 0, 20, duration: length);
      tick(short, 0, playing: false, duration: length);
      await _settle();
      expect(store.rows['L1'], (const Duration(seconds: 20), true));
    });

    test('a pause after 45 s saves 45 s at the pause', () async {
      starts.add(a);
      play(a, 0, 45);
      await _settle();
      expect(store.updates['L1'], const [Duration(seconds: 30)]);
      tick(a, 45000, playing: false);
      await _settle();
      expect(store.updates['L1'], const [
        Duration(seconds: 30),
        Duration(seconds: 45),
      ]);
    });

    test('buffering saves like a pause', () async {
      starts.add(a);
      play(a, 0, 40);
      tick(a, 40000, buffering: true);
      await _settle();
      expect(store.updates['L1']!.last, const Duration(seconds: 40));
    });

    test('a play is saved the moment it counts', () async {
      final short = _track('s', durationMs: 20000);
      starts.add(short);
      play(short, 0, 20, duration: const Duration(seconds: 20));
      await _settle();
      expect(store.updates['L1'], const [Duration(seconds: 20)]);
    });

    test('counting and the checkpoint together write once', () async {
      starts.add(a);
      play(a, 0, 30);
      await _settle();
      expect(store.updates['L1'], const [Duration(seconds: 30)]);
      expect(store.rows['L1'], (const Duration(seconds: 30), true));
    });

    test('an unchanged listen is not written again', () async {
      starts.add(a);
      play(a, 0, 10);
      tick(a, 10000, playing: false);
      tick(a, 10000, playing: false);
      play(a, 10, 10); // resume tick, nothing heard yet
      tick(a, 10000, playing: false);
      recorder.dispose();
      await _settle();
      expect(store.updates['L1'], const [Duration(seconds: 10)]);
    });
  });
}
