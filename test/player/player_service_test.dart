import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';

import 'package:songies/ui/shell/player_error_snacks.dart';
import 'package:songies/youtube/yt_models.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_network_status.dart';

Track track(String id, {int durationMs = 0}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: durationMs,
  unavailable: false,
  searchText: 'title $id artist',
);

/// Resolves every track to `/music/<id>.mp3` unless listed in [missing].
class FakeResolver extends TrackResolver {
  final Set<String> missing = {};
  final List<String> resolved = [];
  final Map<String, Failure> failures = {};
  final List<String> prefetched = [];
  final List<String> invalidated = [];
  Completer<void>? gate;

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    resolved.add(t.id);
    final g = gate;
    if (g != null) await g.future;
    final f = failures[t.id];
    if (f != null) return Err(f);
    if (missing.contains(t.id)) {
      return Err(Failure(FailureKind.notFound, 'missing ${t.id}'));
    }
    return Ok(FileSource('/music/${t.id}.mp3'));
  }

  @override
  Future<void> prefetch(Track t) async => prefetched.add(t.id);

  @override
  void invalidate(Track t) => invalidated.add(t.id);
}

Track ytTrack(String id) => track(id).copyWith(source: 'yt');

Future<void> settle() => pumpEventQueue();

void main() {
  late FakeAudioBackend backend;
  late FakeResolver resolver;
  late List<String> missingReports;
  late List<String> started;
  late List<String> unavailable;
  late PlayerService player;
  final a = track('a');
  final b = track('b');
  final c = track('c');
  final d = track('d');
  final e = track('e');

  PlayerService build({int seed = 1}) => PlayerService(
    backend,
    resolver,
    random: Random(seed),
    onMissing: (id) async => missingReports.add(id),
    onUnavailable: (id) async => unavailable.add(id),
    onTrackStarted: (t, playlistId) async =>
        started.add('${t.id}@${playlistId ?? '-'}'),
  );

  setUp(() {
    // The service logs every skip; keep the test output clean.
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
    backend = FakeAudioBackend();
    resolver = FakeResolver();
    missingReports = [];
    started = [];
    unavailable = [];
    player = build();
  });

  tearDown(() async {
    await player.dispose();
  });

  group('playQueue', () {
    test('loads the start track then plays it', () async {
      await player.playQueue([a, b, c], startIndex: 1, sourcePlaylistId: 'pl');

      expect(backend.calls, ['setSource:/music/b.mp3', 'play']);
      expect(player.state.current, b);
      expect(player.state.index, 1);
      expect(player.state.playing, isTrue);
      expect(player.state.sourcePlaylistId, 'pl');
      expect(started, ['b@pl']);
    });

    test('empty queue has index -1 and no current track', () async {
      expect(player.state.index, -1);
      expect(player.state.current, isNull);
      await player.playQueue([a]);
      await player.playQueue([]);
      expect(player.state.queue, isEmpty);
      expect(player.state.index, -1);
      expect(player.state.current, isNull);
      expect(player.state.playing, isFalse);
      expect(backend.calls.last, 'stop');
    });

    test('out of range startIndex is clamped', () async {
      await player.playQueue([a, b], startIndex: 9);
      expect(player.state.current, b);
    });

    test(
      'takes the duration from the track until the backend reports it',
      () async {
        await player.playQueue([track('a', durationMs: 5000)]);
        expect(player.state.duration, const Duration(seconds: 5));
        backend.setDuration(const Duration(seconds: 7));
        expect(player.state.duration, const Duration(seconds: 7));
      },
    );
  });

  group('completion', () {
    test(
      'plays the next track, then stops at the end with repeat off',
      () async {
        await player.playQueue([a, b, c], startIndex: 1);
        backend.clearCalls();

        backend.complete();
        await settle();
        expect(backend.calls, ['setSource:/music/c.mp3', 'play']);
        expect(player.state.current, c);

        backend.clearCalls();
        backend.complete();
        await settle();
        expect(backend.calls, ['stop']);
        expect(player.state.playing, isFalse);
        expect(player.state.index, 2);
        expect(player.state.error, isNull);
      },
    );

    test('repeat all wraps to the first track', () async {
      player.cycleRepeat();
      expect(player.state.repeat, RepeatMode.all);
      await player.playQueue([a, b, c], startIndex: 2);
      backend.clearCalls();

      backend.complete();
      await settle();

      expect(backend.calls, ['setSource:/music/a.mp3', 'play']);
      expect(player.state.index, 0);
      expect(player.state.playing, isTrue);
    });

    test('repeat one replays the same track with seek(0) + play', () async {
      player.cycleRepeat();
      player.cycleRepeat();
      expect(player.state.repeat, RepeatMode.one);
      await player.playQueue([a, b], startIndex: 1);
      backend.clearCalls();

      backend.complete();
      await settle();

      expect(backend.calls, ['seek:0', 'play']);
      expect(player.state.index, 1);
      expect(player.state.playing, isTrue);
      expect(started, ['b@-', 'b@-']);

      backend.clearCalls();
      backend.complete();
      await settle();
      expect(backend.calls, ['seek:0', 'play']);
    });

    test('a completion that arrives after a manual skip is ignored', () async {
      await player.playQueue([a, b, c]);
      resolver.gate = Completer<void>();
      final skip = player.next();
      await settle();
      backend.complete(); // stale: belongs to a
      await settle();
      resolver.gate!.complete();
      resolver.gate = null;
      await skip;
      await settle();

      expect(player.state.current, b);
      expect(backend.sources, ['/music/a.mp3', '/music/b.mp3']);
    });

    test('the same completed state repeated does not advance twice', () async {
      await player.playQueue([a, b, c]);
      backend.complete();
      backend.emit(
        const BackendState(completed: true, position: Duration(seconds: 3)),
      );
      await settle();
      expect(player.state.current, b);
    });
  });

  group('previous', () {
    test('after more than 3 s restarts the current track', () async {
      await player.playQueue([a, b, c], startIndex: 1);
      backend.setPosition(const Duration(seconds: 5));
      backend.clearCalls();

      await player.previous();

      expect(backend.calls, ['seek:0']);
      expect(player.state.index, 1);
      expect(player.state.position, Duration.zero);
    });

    test('within 3 s goes to the previous track', () async {
      await player.playQueue([a, b, c], startIndex: 1);
      backend.setPosition(const Duration(seconds: 2));
      backend.clearCalls();

      await player.previous();

      expect(backend.calls, ['setSource:/music/a.mp3', 'play']);
      expect(player.state.index, 0);
    });

    test('at index 0 within 3 s restarts the track', () async {
      await player.playQueue([a, b]);
      backend.setPosition(const Duration(seconds: 2));
      backend.clearCalls();

      await player.previous();

      expect(backend.calls, ['seek:0']);
      expect(player.state.index, 0);
    });

    test('exactly 3 s counts as early and goes back', () async {
      await player.playQueue([a, b], startIndex: 1);
      backend.setPosition(const Duration(seconds: 3));
      await player.previous();
      expect(player.state.index, 0);
    });

    test(
      'skips missing earlier tracks backwards, keeps playing if none',
      () async {
        await player.playQueue([a, b, c], startIndex: 2);
        resolver.missing.addAll({'a', 'b'});
        backend.clearCalls();

        await player.previous();

        expect(missingReports, ['b', 'a']);
        expect(player.state.index, 2);
        expect(player.state.playing, isTrue);
        expect(player.state.error, isNull);
        expect(backend.calls, ['seek:0']);
      },
    );
  });

  group('next', () {
    test('moves forward and ignores repeat one', () async {
      player.cycleRepeat();
      player.cycleRepeat();
      await player.playQueue([a, b, c]);
      await player.next();
      expect(player.state.current, b);
    });

    test('at the end: repeat off stops, repeat all wraps', () async {
      await player.playQueue([a, b], startIndex: 1);
      backend.clearCalls();
      await player.next();
      expect(backend.calls, ['stop']);
      expect(player.state.playing, isFalse);
      expect(player.state.index, 1);

      player.cycleRepeat();
      await player.playQueue([a, b], startIndex: 1);
      await player.next();
      expect(player.state.index, 0);
      expect(player.state.playing, isTrue);
    });

    test('skips a missing track and reports it', () async {
      await player.playQueue([a, b, c]);
      resolver.missing.add('b');
      backend.clearCalls();

      await player.next();

      expect(missingReports, ['b']);
      expect(player.state.current, c);
      expect(backend.calls, ['setSource:/music/c.mp3', 'play']);
      expect(player.state.error, isNull);
    });

    test('with every track missing it tries each once and gives up', () async {
      resolver.missing.addAll({'a', 'b', 'c'});
      await player.playQueue([a, b, c]);

      expect(resolver.resolved, ['a', 'b', 'c']);
      expect(missingReports, ['a', 'b', 'c']);
      expect(player.state.playing, isFalse);
      expect(player.state.error, 'No playable files in queue');
      expect(backend.sources, isEmpty);
    });

    test('repeat all with every track missing does not loop forever', () async {
      player.cycleRepeat();
      resolver.missing.addAll({'a', 'b', 'c'});
      await player.playQueue([a, b, c], startIndex: 1);

      expect(resolver.resolved, ['b', 'c', 'a']);
      expect(player.state.error, 'No playable files in queue');
    });

    test('repeat all wraps around a missing tail to the first track', () async {
      player.cycleRepeat();
      await player.playQueue([a, b, c], startIndex: 1);
      resolver.missing.add('c');
      await player.next();
      expect(player.state.current, a);
    });

    test('a successful start clears the error; play() retries', () async {
      resolver.missing.addAll({'a'});
      await player.playQueue([a]);
      expect(player.state.error, isNotNull);

      resolver.missing.clear();
      await player.play();
      expect(player.state.error, isNull);
      expect(player.state.playing, isTrue);
      expect(backend.sources, ['/music/a.mp3']);
    });

    test(
      'skips a track whose source fails to load, without reporting it',
      () async {
        // The service logs the failure; keep the test output clean.
        final original = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        addTearDown(() => debugPrint = original);
        await player.playQueue([a, b, c]);
        backend.failNext.add('setSource');
        await player.next();
        expect(player.state.current, c);
        expect(missingReports, isEmpty);
      },
    );

    test(
      'rapid taps are serialised: setSource calls never interleave',
      () async {
        await player.playQueue([a, b, c, d, e]);
        backend.clearCalls();
        resolver.gate = Completer<void>();

        final futures = [player.next(), player.next(), player.next()];
        await settle();
        resolver.gate!.complete();
        await Future.wait(futures);

        expect(backend.calls, [
          'setSource:/music/b.mp3',
          'play',
          'setSource:/music/c.mp3',
          'play',
          'setSource:/music/d.mp3',
          'play',
        ]);
        expect(player.state.current, d);
      },
    );
  });

  group('engine errors mid-track', () {
    setUp(() {
      // The service logs the failure; keep the test output clean.
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = original);
    });

    test('skip to the next playable track', () async {
      await player.playQueue([a, b, c]);
      resolver.missing.add('b');
      backend.clearCalls();

      backend.emitError();
      await settle();

      expect(player.state.current, c);
      expect(player.state.playing, isTrue);
      expect(backend.calls, ['setSource:/music/c.mp3', 'play']);
      expect(missingReports, ['b']);
    });

    test('on the last track the queue ends like a normal end', () async {
      await player.playQueue([a, b], startIndex: 1);

      backend.emitError();
      await settle();

      expect(player.state.playing, isFalse);
      expect(player.state.index, 1);
      expect(player.state.error, PlayerService.playbackFailedError);
    });

    test('repeat all wraps to the first track', () async {
      player.cycleRepeat();
      await player.playQueue([a, b], startIndex: 1);

      backend.emitError();
      await settle();

      expect(player.state.current, a);
      expect(player.state.playing, isTrue);
    });

    test('a track that keeps failing does not loop forever', () async {
      player.cycleRepeat();
      await player.playQueue([a, b]);
      // Every track fails right after it starts.
      backend.onSetSource = (_) => Future(backend.emitError);

      backend.emitError();
      await settle();
      await settle();

      expect(player.state.playing, isFalse);
      expect(player.state.error, PlayerService.engineFailedError);
      expect(backend.sources.length, lessThanOrEqualTo(3));
    });

    test('an error for a track the user already left is ignored', () async {
      await player.playQueue([a, b, c]);
      resolver.gate = Completer<void>();
      final skip = player.next(); // waits on the gate
      backend.emitError(); // reported for a, then the skip lands on b
      await settle();
      resolver.gate!.complete();
      await skip;
      await settle();

      expect(player.state.current, b);
    });

    test('an error while stopped does nothing', () async {
      await player.playQueue([a, b]);
      await player.pause();
      await player.playQueue([]);
      backend.clearCalls();

      backend.emitError();
      await settle();

      expect(backend.calls, isEmpty);
    });
  });

  group('playAt', () {
    test('jumps to the index; out of range is ignored', () async {
      await player.playQueue([a, b, c]);
      await player.playAt(2);
      expect(player.state.current, c);
      backend.clearCalls();
      await player.playAt(7);
      await player.playAt(-1);
      expect(backend.calls, isEmpty);
      expect(player.state.current, c);
    });
  });

  group('transport', () {
    test('toggle, pause, play and seek drive the backend', () async {
      await player.playQueue([a]);
      backend.clearCalls();

      await player.togglePlay();
      expect(player.state.playing, isFalse);
      await player.togglePlay();
      expect(player.state.playing, isTrue);
      await player.seek(const Duration(seconds: 42));
      expect(player.state.position, const Duration(seconds: 42));

      expect(backend.calls, ['pause', 'play', 'seek:42000']);
    });

    test('rapid togglePlay taps are serialised: pause then play', () async {
      await player.playQueue([a]);
      backend.clearCalls();

      final first = player.togglePlay();
      final second = player.togglePlay();
      await Future.wait([first, second]);

      expect(backend.calls, ['pause', 'play']);
      expect(player.state.playing, isTrue);
    });

    test('play after the queue ended restarts the last track', () async {
      await player.playQueue([a, b], startIndex: 1);
      backend.complete();
      await settle();
      expect(player.state.playing, isFalse);

      backend.clearCalls();
      await player.play();
      expect(backend.calls, ['setSource:/music/b.mp3', 'play']);
      expect(player.state.playing, isTrue);
    });

    test('commands on an empty queue do nothing', () async {
      await player.play();
      await player.pause();
      await player.next();
      await player.previous();
      await player.seek(const Duration(seconds: 1));
      await player.togglePlay();
      expect(backend.calls, isEmpty);
      expect(player.state.playing, isFalse);
    });

    test(
      'backend position and buffering updates reach the state stream',
      () async {
        await player.playQueue([a]);
        final seen = <PlayerState>[];
        final sub = player.states.listen(seen.add);

        backend.setPosition(const Duration(seconds: 1));
        backend.setBuffering(true);
        await settle();
        await sub.cancel();

        expect(seen.length, greaterThanOrEqualTo(2));
        expect(seen.last.position, const Duration(seconds: 1));
        expect(seen.last.buffering, isTrue);
        expect(player.state.position, const Duration(seconds: 1));
      },
    );
  });

  group('buffered position', () {
    test('comes from the backend', () async {
      await player.playQueue([a]);
      backend.setBuffered(const Duration(seconds: 40));
      await settle();
      expect(player.state.buffered, const Duration(seconds: 40));
    });

    test('is cleared with the position on a track change and a stop', () async {
      await player.playQueue([a, b]);
      backend.setBuffered(const Duration(seconds: 40));
      await settle();
      final seen = <PlayerState>[];
      final sub = player.states.listen(seen.add);

      await player.next();
      await settle();
      // From the first state showing the new track on, nothing is stale.
      final changed = seen.skipWhile((s) => s.current != b).toList();
      expect(changed, isNotEmpty);
      expect(changed.map((s) => s.buffered), everyElement(Duration.zero));

      backend.setBuffered(const Duration(seconds: 40));
      await settle();
      seen.clear();
      await player.playQueue([c]);
      await settle();
      expect(
        seen.skipWhile((s) => s.current != c).map((s) => s.buffered),
        everyElement(Duration.zero),
      );
      await sub.cancel();
    });
  });

  group('shuffle', () {
    test(
      'keeps the current track first and restores order when turned off',
      () async {
        await player.playQueue([a, b, c, d, e], startIndex: 2);

        player.setShuffle(true);
        expect(player.state.shuffle, isTrue);
        expect(player.state.index, 0);
        expect(player.state.current, c);
        expect(player.state.queue.toSet(), {a, b, c, d, e});
        expect(player.state.queue, hasLength(5));

        player.setShuffle(false);
        expect(player.state.shuffle, isFalse);
        expect(player.state.queue, [a, b, c, d, e]);
        expect(player.state.index, 2);
        expect(player.state.current, c);
        expect(backend.sources, ['/music/c.mp3']);
      },
    );

    test('actually reorders (seeded)', () async {
      final ids = List.generate(20, (i) => track('t$i'));
      await player.playQueue(ids);
      player.setShuffle(true);
      expect(player.state.queue, isNot(ids));
      expect(player.state.queue.first, ids.first);
    });

    test('on a one-track queue is harmless', () async {
      await player.playQueue([a]);
      player.setShuffle(true);
      expect(player.state.queue, [a]);
      expect(player.state.current, a);
      player.setShuffle(false);
      expect(player.state.current, a);
      expect(backend.sources, ['/music/a.mp3']);
    });

    test('playQueue while shuffle is on shuffles the new queue', () async {
      player.setShuffle(true);
      final ids = List.generate(20, (i) => track('t$i'));
      await player.playQueue(ids, startIndex: 5);
      expect(player.state.current, ids[5]);
      expect(player.state.index, 0);
      expect(player.state.queue.toSet(), ids.toSet());
      player.setShuffle(false);
      expect(player.state.queue, ids);
      expect(player.state.index, 5);
    });

    test('removed tracks stay removed when shuffle is turned off', () async {
      await player.playQueue([a, b, c, d, e], startIndex: 2);
      player.setShuffle(true);
      final idx = player.state.queue.indexOf(d);
      await player.removeAt(idx);
      player.setShuffle(false);
      expect(player.state.queue, [a, b, c, e]);
      expect(player.state.current, c);
    });

    test('moves made while shuffled are dropped when turned off', () async {
      await player.playQueue([a, b, c, d, e], startIndex: 2);
      player.setShuffle(true);
      player.move(0, 4);
      player.setShuffle(false);
      expect(player.state.queue, [a, b, c, d, e]);
      expect(player.state.current, c);
      expect(player.state.index, 2);
    });
  });

  group('queue editing', () {
    test('removeAt(current) while playing starts the next track', () async {
      await player.playQueue([a, b, c]);
      backend.clearCalls();

      await player.removeAt(0);

      expect(player.state.queue, [b, c]);
      expect(player.state.current, b);
      expect(player.state.index, 0);
      expect(player.state.playing, isTrue);
      expect(backend.calls, ['setSource:/music/b.mp3', 'play']);
    });

    test(
      'removing the last remaining track stops with an empty queue',
      () async {
        await player.playQueue([a]);
        backend.clearCalls();

        await player.removeAt(0);

        expect(player.state.queue, isEmpty);
        expect(player.state.index, -1);
        expect(player.state.current, isNull);
        expect(player.state.playing, isFalse);
        expect(backend.calls, ['stop']);
      },
    );

    test(
      'removing the current last track follows the end-of-queue rule',
      () async {
        await player.playQueue([a, b], startIndex: 1);
        backend.clearCalls();
        await player.removeAt(1);
        expect(backend.calls, ['stop']);
        expect(player.state.playing, isFalse);
        expect(player.state.queue, [a]);
        expect(player.state.index, 0);

        player.cycleRepeat();
        await player.playQueue([a, b], startIndex: 1);
        await player.removeAt(1);
        expect(player.state.current, a);
        expect(player.state.playing, isTrue);
      },
    );

    test('removing the current track while paused does not autoplay', () async {
      await player.playQueue([a, b]);
      await player.pause();
      backend.clearCalls();

      await player.removeAt(0);

      expect(player.state.current, b);
      expect(player.state.playing, isFalse);
      expect(backend.calls, ['stop']);
    });

    test(
      'removing a track before the current one shifts the index only',
      () async {
        await player.playQueue([a, b, c], startIndex: 2);
        backend.clearCalls();

        await player.removeAt(0);

        expect(player.state.index, 1);
        expect(player.state.current, c);
        expect(backend.calls, isEmpty);
      },
    );

    test(
      'removing a track after the current one changes nothing else',
      () async {
        await player.playQueue([a, b, c]);
        backend.clearCalls();
        await player.removeAt(2);
        expect(player.state.queue, [a, b]);
        expect(player.state.index, 0);
        expect(backend.calls, isEmpty);
      },
    );

    test('move(0, 2) keeps the current track and updates the index', () async {
      await player.playQueue([a, b, c]);
      backend.clearCalls();

      player.move(0, 2);

      expect(player.state.queue, [b, c, a]);
      expect(player.state.current, a);
      expect(player.state.index, 2);
      expect(backend.calls, isEmpty);
    });

    test(
      'moving other tracks around the current one tracks its index',
      () async {
        await player.playQueue([a, b, c, d], startIndex: 1);
        player.move(3, 0);
        expect(player.state.queue, [d, a, b, c]);
        expect(player.state.current, b);
        expect(player.state.index, 2);
        player.move(0, 3);
        expect(player.state.queue, [a, b, c, d]);
        expect(player.state.index, 1);
      },
    );

    test('invalid moves and removals are ignored', () async {
      await player.playQueue([a, b]);
      player.move(-1, 1);
      player.move(0, 5);
      await player.removeAt(5);
      await player.removeAt(-1);
      expect(player.state.queue, [a, b]);
    });

    test('no queue mutation restarts the current track', () async {
      await player.playQueue([a, b, c, d], startIndex: 1);
      backend.clearCalls();

      player.move(0, 3);
      player.setShuffle(true);
      player.setShuffle(false);
      player.cycleRepeat();
      await player.removeAt(player.state.queue.indexOf(d));

      expect(backend.calls, isEmpty);
      expect(player.state.current, b);
    });

    test('the queue exposed in state cannot be mutated by callers', () async {
      await player.playQueue([a, b]);
      expect(() => player.state.queue.add(c), throwsUnsupportedError);
    });
  });

  group('upNext', () {
    PlayerState at(
      List<Track> q,
      int index, [
      RepeatMode repeat = RepeatMode.off,
    ]) => PlayerState(queue: q, index: index, repeat: repeat);

    test('the middle of the queue gives the next track', () {
      expect(at([a, b, c], 1).upNext, c);
    });

    test('the end with repeat off gives null', () {
      expect(at([a, b, c], 2).upNext, isNull);
    });

    test('the end with repeat all gives the first track', () {
      expect(at([a, b, c], 2, RepeatMode.all).upNext, a);
    });

    test('repeat one gives null', () {
      expect(at([a, b, c], 0, RepeatMode.one).upNext, isNull);
    });

    test('an unavailable next track is skipped', () {
      final gone = b.copyWith(unavailable: true);
      expect(at([a, gone, c], 0).upNext, c);
      expect(at([a, b, gone], 1).upNext, isNull);
      expect(at([a, b, gone], 1, RepeatMode.all).upNext, a);
    });

    test('a one-song queue with repeat all gives null', () {
      expect(at([a], 0, RepeatMode.all).upNext, isNull);
    });

    test('an empty queue gives null', () {
      expect(const PlayerState().upNext, isNull);
    });
  });

  group('repeat', () {
    test('cycles off, all, one, off', () {
      expect(player.state.repeat, RepeatMode.off);
      player.cycleRepeat();
      expect(player.state.repeat, RepeatMode.all);
      player.cycleRepeat();
      expect(player.state.repeat, RepeatMode.one);
      player.cycleRepeat();
      expect(player.state.repeat, RepeatMode.off);
    });
  });

  group('volume', () {
    test('defaults to 1.0', () {
      expect(player.state.volume, 1.0);
    });

    test('sets the backend volume and the state', () async {
      await player.setVolume(0.4);
      expect(backend.calls, ['setVolume:0.4']);
      expect(player.state.volume, 0.4);
    });

    test('clamps to 0..1 and ignores NaN', () async {
      await player.setVolume(1.7);
      expect(player.state.volume, 1.0);
      await player.setVolume(-0.5);
      expect(player.state.volume, 0.0);
      backend.clearCalls();
      await player.setVolume(double.nan);
      expect(backend.calls, isEmpty);
      expect(player.state.volume, 0.0);
    });

    test('is serialized with other commands', () async {
      resolver.gate = Completer<void>();
      final started = player.playQueue([a]);
      final vol = player.setVolume(0.5);
      await settle();
      expect(backend.calls, isNot(contains('setVolume:0.5')));
      resolver.gate!.complete();
      await started;
      await vol;
      expect(backend.calls.last, 'setVolume:0.5');
    });

    test('survives a queue change', () async {
      await player.setVolume(0.3);
      await player.playQueue([a, b]);
      expect(player.state.volume, 0.3);
    });
  });

  group('offline playback', () {
    final offline = Failure(FailureKind.network, "You're offline");
    late FakeNetworkStatus net;

    /// YouTube tracks [ids] that have no downloaded file: offline they fail
    /// to resolve, as the stream resolver does.
    void notDownloaded(Iterable<String> ids) {
      for (final id in ids) {
        resolver.failures[id] = offline;
      }
    }

    setUp(() async {
      await player.dispose(); // also closes the backend
      backend = FakeAudioBackend();
      net = FakeNetworkStatus(NetworkKind.offline);
      player = PlayerService(
        backend,
        resolver,
        network: net,
        onMissing: (id) async => missingReports.add(id),
        onUnavailable: (id) async => unavailable.add(id),
      );
    });

    test(
      'skips undownloaded YouTube songs quietly to a downloaded one',
      () async {
        final ys = [for (var i = 1; i <= 6; i++) ytTrack('y$i')];
        notDownloaded(['y1', 'y2', 'y3', 'y4', 'y5']);
        await player.playQueue(ys);

        expect(resolver.resolved, ['y1', 'y2', 'y3', 'y4', 'y5', 'y6']);
        expect(backend.sources, ['/music/y6.mp3']);
        expect(player.state.current, ys[5]);
        expect(player.state.playing, isTrue);
        expect(player.state.error, isNull);
        expect(player.state.notice, isNull);
        expect(unavailable, isEmpty);
      },
    );

    test('auto-advance passes undownloaded songs, local MP3s play', () async {
      final ys = [for (var i = 1; i <= 4; i++) ytTrack('y$i')];
      notDownloaded(['y1', 'y2', 'y3', 'y4']);
      final d = ytTrack('d');
      await player.playQueue([a, ...ys, d, b]);
      expect(player.state.current, a);

      backend.complete();
      await settle();
      expect(player.state.current, d);
      expect(player.state.playing, isTrue);
      expect(player.state.notice, isNull);

      backend.complete();
      await settle();
      expect(player.state.current, b);
      expect(backend.sources, ['/music/a.mp3', '/music/d.mp3', '/music/b.mp3']);
    });

    test('quiet skips do not count toward the 3-in-a-row cap', () async {
      final ys = [for (var i = 1; i <= 3; i++) ytTrack('y$i')];
      notDownloaded(['y1', 'y2', 'y3']);
      // Two real failures, then undownloaded songs, then a playable one.
      resolver.missing.addAll(['a', 'b']);
      await player.playQueue([a, b, ...ys, c]);

      expect(player.state.current, c);
      expect(player.state.playing, isTrue);
      expect(missingReports, ['a', 'b']);
    });

    test('stops when nothing left is downloaded', () async {
      final ys = [for (var i = 1; i <= 5; i++) ytTrack('y$i')];
      notDownloaded(ys.map((y) => y.id));
      await player.playQueue(ys);

      expect(resolver.resolved, ['y1', 'y2', 'y3', 'y4', 'y5']);
      expect(backend.sources, isEmpty);
      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
      expect(player.state.notice, isNull);
    });

    test('online, a network failure still stops playback', () async {
      net.kind = NetworkKind.wifi;
      final ys = [for (var i = 1; i <= 3; i++) ytTrack('y$i')];
      resolver.failures['y1'] = offline;
      await player.playQueue(ys);

      expect(resolver.resolved, ['y1']);
      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
      expect(player.state.current, ys[0]);
    });
  });

  group('network failures', () {
    final offline = Failure(FailureKind.network, "You're offline");

    test('stop playback without skipping', () async {
      resolver.failures['a'] = offline;
      await player.playQueue([a, b, c]);

      expect(backend.calls, isNot(contains('play')));
      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
      expect(resolver.resolved, ['a']);
      expect(player.state.current, a);
    });

    test('stop when auto-advancing', () async {
      await player.playQueue([a, b, c]);
      resolver.failures['b'] = offline;
      backend.complete();
      await settle();

      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
      expect(resolver.resolved, ['a', 'b']);
      expect(backend.calls.last, 'stop');
      expect(player.state.current, b);
      expect(player.state.index, 1);
    });

    test('play after a network stop retries the failed track', () async {
      await player.playQueue([a, b, c]);
      resolver.failures['b'] = offline;
      backend.complete();
      await settle();
      resolver.failures.clear();
      backend.clearCalls();

      await player.play();
      expect(backend.calls, ['setSource:/music/b.mp3', 'play']);
      expect(player.state.current, b);
      expect(player.state.playing, isTrue);
      expect(player.state.error, isNull);
    });

    test('next stops on the failed track and play retries it', () async {
      await player.playQueue([a, b, c]);
      resolver.failures['b'] = offline;
      await player.next();
      expect(player.state.current, b);
      expect(player.state.playing, isFalse);
      resolver.failures.clear();
      await player.play();
      expect(backend.sources.last, '/music/b.mp3');
      expect(player.state.playing, isTrue);
    });

    test('previous does not restart after a network stop', () async {
      await player.playQueue([a, b, c], startIndex: 2);
      resolver.failures['b'] = offline;
      await player.previous();
      expect(resolver.resolved, ['c', 'b']);
      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
    });

    test('yt notFound skips and reports unavailable', () async {
      final y = ytTrack('y');
      resolver.failures['y'] = Failure(
        FailureKind.notFound,
        'ytdlp:notFound:x',
      );
      await player.playQueue([y, b]);

      expect(player.state.current, b);
      expect(player.state.playing, isTrue);
      expect(unavailable, ['y']);
      expect(missingReports, isEmpty);
    });

    test('local notFound does not report unavailable', () async {
      resolver.missing.add('a');
      await player.playQueue([a, b]);
      expect(unavailable, isEmpty);
    });
  });

  group('yt engine retry', () {
    test('first engine error re-resolves the same entry once', () async {
      final y = ytTrack('y');
      await player.playQueue([y, b]);
      backend.clearCalls();

      backend.emitError();
      await settle();

      expect(resolver.invalidated, ['y']);
      expect(resolver.resolved, ['y', 'y']);
      expect(backend.calls, ['setSource:/music/y.mp3', 'play']);
      expect(player.state.current, y);
      expect(player.state.playing, isTrue);
      expect(started, ['y@-']);
    });

    test('second engine error follows the skip path', () async {
      final y = ytTrack('y');
      await player.playQueue([y, b]);
      backend.emitError();
      await settle();
      backend.emitError();
      await settle();

      expect(resolver.invalidated, ['y']);
      expect(player.state.current, b);
    });

    test('local tracks are not retried', () async {
      await player.playQueue([a, b]);
      backend.emitError();
      await settle();
      expect(resolver.invalidated, isEmpty);
      expect(player.state.current, b);
    });

    test('network failure on the retry stops playback', () async {
      final y = ytTrack('y');
      await player.playQueue([y, b]);
      resolver.failures['y'] = Failure(FailureKind.network, "You're offline");
      backend.emitError();
      await settle();
      expect(player.state.playing, isFalse);
      expect(player.state.error, "You're offline");
      expect(resolver.resolved, ['y', 'y']);
    });
  });

  group('prefetch', () {
    Future<void> at(int secs) async {
      backend.setDuration(const Duration(seconds: 100));
      backend.setPosition(Duration(seconds: secs));
      await settle();
    }

    test('fires once when within 20 s of the end', () async {
      await player.playQueue([a, b, c]);
      await at(70);
      expect(resolver.prefetched, isEmpty);
      await at(80);
      await at(85);
      expect(resolver.prefetched, ['b']);
    });

    test('not while paused or with unknown duration', () async {
      await player.playQueue([a, b]);
      backend.setPosition(const Duration(seconds: 95));
      expect(resolver.prefetched, isEmpty);
      await player.pause();
      backend.setDuration(const Duration(seconds: 100));
      backend.setPosition(const Duration(seconds: 96));
      expect(resolver.prefetched, isEmpty);
    });

    test('none at the end with repeat off, wraps with repeat all', () async {
      await player.playQueue([a, b], startIndex: 1);
      await at(90);
      expect(resolver.prefetched, isEmpty);

      player.cycleRepeat();
      await player.playQueue([a, b], startIndex: 1);
      await at(90);
      expect(resolver.prefetched, ['a']);
    });

    test('skips an unavailable next entry', () async {
      final u = track('u').copyWith(unavailable: true);
      await player.playQueue([a, u, c]);
      await at(90);
      expect(resolver.prefetched, ['c']);
    });

    test('none for repeat one', () async {
      player.cycleRepeat();
      player.cycleRepeat();
      await player.playQueue([a, b]);
      await at(90);
      expect(resolver.prefetched, isEmpty);
    });

    test('again for the next entry', () async {
      await player.playQueue([a, b, c]);
      await at(90);
      backend.complete();
      await settle();
      await at(90);
      expect(resolver.prefetched, ['b', 'c']);
    });
  });

  group('yt-dlp failures that hit every track', () {
    test('extractor failure stops instead of skipping', () async {
      final y1 = ytTrack('y1');
      final y2 = ytTrack('y2');
      final y3 = ytTrack('y3');
      for (final id in ['y1', 'y2', 'y3']) {
        resolver.failures[id] = Failure(
          FailureKind.unknown,
          'ytdlp:extractor:boom',
        );
      }
      await player.playQueue([y1, y2, y3]);

      expect(resolver.resolved, ['y1']);
      expect(player.state.playing, isFalse);
      expect(player.state.current, y1);
      expect(player.state.error, 'ytdlp:extractor:boom');
      expect(
        playerErrorMessage(player.state.error!),
        'YouTube changed something — try Settings → Update yt-dlp',
      );
    });

    test('missingBinary stops with the install copy', () async {
      final y1 = ytTrack('y1');
      resolver.failures['y1'] = Failure(
        FailureKind.unknown,
        'ytdlp:missingBinary:not installed',
      );
      await player.playQueue([y1, b]);

      expect(resolver.resolved, ['y1']);
      expect(player.state.playing, isFalse);
      expect(
        playerErrorMessage(player.state.error!),
        "yt-dlp isn't installed — install it in Settings",
      );
    });

    test('unknown yt-dlp failure stops', () async {
      final y1 = ytTrack('y1');
      resolver.failures['y1'] = Failure(FailureKind.unknown, 'ytdlp:unknown:x');
      await player.playQueue([y1, b]);
      expect(resolver.resolved, ['y1']);
      expect(player.state.playing, isFalse);
      expect(player.state.error, 'ytdlp:unknown:x');
    });

    test('play after the stop retries the failed track', () async {
      final y1 = ytTrack('y1');
      resolver.failures['y1'] = Failure(
        FailureKind.unknown,
        'ytdlp:extractor:boom',
      );
      await player.playQueue([y1, b]);
      resolver.failures.clear();
      await player.play();
      expect(player.state.current, y1);
      expect(player.state.playing, isTrue);
    });
  });

  group('yt setSource failure retry', () {
    test('a setSource throw re-resolves the yt entry once', () async {
      final y = ytTrack('y');
      backend.failNext.add('setSource');
      await player.playQueue([y, b]);

      expect(resolver.invalidated, ['y']);
      expect(resolver.resolved, ['y', 'y']);
      expect(player.state.current, y);
      expect(player.state.playing, isTrue);
      expect(started, ['y@-']);
    });

    test('a second throw skips to the next entry', () async {
      final y = ytTrack('y');
      backend.onSetSource = (s) {
        if (s is FileSource && s.path.endsWith('/y.mp3')) {
          throw StateError('403');
        }
      };
      await player.playQueue([y, b]);

      expect(resolver.invalidated, ['y']);
      expect(resolver.resolved, ['y', 'y', 'b']);
      expect(player.state.current, b);
      expect(player.state.playing, isTrue);
    });

    test('local setSource throws are not retried', () async {
      backend.failNext.add('setSource');
      await player.playQueue([a, b]);
      expect(resolver.invalidated, isEmpty);
      expect(player.state.current, b);
    });
  });

  group('feedback while a stream resolves', () {
    test('index and buffering are emitted before the resolve', () async {
      final y = ytTrack('y');
      await player.playQueue([a, y]);
      final gate = Completer<void>();
      resolver.gate = gate;

      final done = player.playAt(1);
      await settle();
      expect(player.state.index, 1);
      expect(player.state.buffering, isTrue);

      gate.complete();
      await done;
      expect(player.state.index, 1);
      expect(player.state.buffering, isFalse);
      expect(player.state.playing, isTrue);
    });

    test(
      'previous falling back to the current track restores its index',
      () async {
        final y = ytTrack('y');
        await player.playQueue([y, b], startIndex: 1);
        resolver.failures['y'] = Failure(
          FailureKind.notFound,
          'ytdlp:notFound:x',
        );
        await player.previous();
        expect(player.state.current, b);
        expect(player.state.index, 1);
        expect(player.state.buffering, isFalse);
        expect(player.state.playing, isTrue);
      },
    );
  });

  group('switching and skipping', () {
    Failure notFound(String id) =>
        ytFailure(YtErrorKind.notFound, 'unavailable $id');

    test(
      'switching to a YouTube track pauses the old audio before resolving',
      () async {
        final y = ytTrack('y');
        await player.playQueue([a, y]);
        final gate = Completer<void>();
        resolver.gate = gate;

        final done = player.next();
        await settle();
        expect(backend.pauseCalls, 1);
        expect(player.state.index, 1);
        expect(player.state.current, y);

        gate.complete();
        await done;
        expect(player.state.playing, isTrue);
        expect(backend.sources.last, '/music/y.mp3');
      },
    );

    test('playQueue onto a YouTube track pauses the old audio first', () async {
      await player.playQueue([a]);
      final gate = Completer<void>();
      resolver.gate = gate;

      final y = ytTrack('y');
      final done = player.playQueue([y]);
      await settle();
      expect(backend.pauseCalls, 1);
      expect(player.state.current, y);

      gate.complete();
      await done;
      expect(player.state.playing, isTrue);
    });

    test(
      'removing the current track onto a YouTube one pauses it first',
      () async {
        final y = ytTrack('y');
        await player.playQueue([a, y]);
        final gate = Completer<void>();
        resolver.gate = gate;

        final done = player.removeAt(0);
        await settle();
        expect(backend.pauseCalls, 1);
        expect(player.state.current, y);

        gate.complete();
        await done;
        expect(player.state.playing, isTrue);
      },
    );

    test('a failed start skips at most 3 tracks', () async {
      final ys = [for (var i = 1; i <= 6; i++) ytTrack('y$i')];
      for (final y in ys) {
        resolver.failures[y.id] = notFound(y.id);
      }
      await player.playQueue(ys);

      expect(resolver.resolved, ['y1', 'y2', 'y3']);
      expect(player.state.playing, isFalse);
      expect(player.state.error, PlayerService.tooManyFailuresError);
      expect(player.state.notice!.trackTitle, ys[2].title);
      expect(backend.sources, isEmpty);
    });

    test('play after the cap stop tries again', () async {
      final ys = [for (var i = 1; i <= 4; i++) ytTrack('y$i')];
      for (final y in ys) {
        resolver.failures[y.id] = notFound(y.id);
      }
      await player.playQueue(ys);
      resolver.failures.clear();
      await player.play();
      expect(player.state.current, ys[2]);
      expect(player.state.playing, isTrue);
      expect(player.state.error, isNull);
    });

    test('the cap resets after a successful start', () async {
      final ys = [for (var i = 1; i <= 5; i++) ytTrack('y$i')];
      resolver.failures['y1'] = notFound('y1');
      resolver.failures['y2'] = notFound('y2');
      await player.playQueue([...ys.take(3), a, ...ys.skip(3)]);
      expect(player.state.current, ys[2]);
      expect(player.state.playing, isTrue);
    });

    test('each skip publishes a notice', () async {
      final y1 = ytTrack('y1');
      resolver.failures['y1'] = notFound('y1');
      await player.playQueue([y1, b, c]);

      expect(player.state.current, b);
      expect(player.state.notice!.trackTitle, y1.title);
      expect(player.state.notice!.reason, 'ytdlp:notFound:unavailable y1');

      await player.next();
      expect(player.state.current, c);
      expect(player.state.notice, isNull);
    });

    test('a single YouTube song that fails reports its own reason', () async {
      final y1 = ytTrack('y1');
      resolver.failures['y1'] = notFound('y1');
      await player.playQueue([y1]);
      expect(player.state.playing, isFalse);
      expect(player.state.error, 'ytdlp:notFound:unavailable y1');
    });

    test('a late engine error from the previous source is ignored', () async {
      final ya = ytTrack('ya');
      final yb = ytTrack('yb');
      await player.playQueue([ya, yb, c]);
      // A's engine fails while B is being loaded.
      backend.onSetSource = (_) {
        backend.onSetSource = null;
        backend.emitError();
      };
      await player.next();
      await settle();

      expect(resolver.resolved, ['ya', 'yb']);
      expect(resolver.invalidated, isEmpty);
      expect(player.state.current, yb);
      expect(player.state.playing, isTrue);
    });

    test(
      'completed well before the end is treated as an engine error',
      () async {
        final y = ytTrack('y');
        await player.playQueue([y, b]);
        backend.emit(
          const BackendState(
            completed: true,
            position: Duration(seconds: 30),
            duration: Duration(seconds: 200),
          ),
        );
        await settle();

        expect(resolver.invalidated, ['y']);
        expect(resolver.resolved, ['y', 'y']);
        expect(player.state.current, y);
        expect(player.state.playing, isTrue);
      },
    );

    test('completed within 5 s of the end advances normally', () async {
      final y = ytTrack('y');
      await player.playQueue([y, b]);
      backend.emit(
        const BackendState(
          completed: true,
          position: Duration(seconds: 197),
          duration: Duration(seconds: 200),
        ),
      );
      await settle();

      expect(resolver.invalidated, isEmpty);
      expect(player.state.current, b);
      expect(player.state.playing, isTrue);
    });

    test('a local track completing early advances normally', () async {
      await player.playQueue([a, b]);
      backend.emit(
        const BackendState(
          completed: true,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 200),
        ),
      );
      await settle();
      expect(player.state.current, b);
      expect(player.state.playing, isTrue);
      expect(player.state.notice, isNull);
    });

    test('completed with an unknown duration advances normally', () async {
      final y = ytTrack('y');
      await player.playQueue([y, b]);
      backend.emit(
        const BackendState(completed: true, position: Duration(seconds: 30)),
      );
      await settle();
      expect(resolver.invalidated, isEmpty);
      expect(player.state.current, b);
    });

    test('a halt does not count toward the cap and sets no notice', () async {
      final y1 = ytTrack('y1');
      final y2 = ytTrack('y2');
      resolver.failures['y1'] = notFound('y1');
      resolver.failures['y2'] = Failure(FailureKind.network, "You're offline");
      await player.playQueue([y1, y2, b]);
      expect(resolver.resolved, ['y1', 'y2']);
      expect(player.state.error, "You're offline");
      expect(player.state.notice!.trackTitle, y1.title);
    });
  });

  group('trackStarts', () {
    test('emits on every start and not on seek, pause or play', () async {
      final ids = <String>[];
      final sub = player.trackStarts.listen((t) => ids.add(t.id));
      addTearDown(sub.cancel);

      await player.playQueue([a, b, c]);
      await settle();
      expect(ids, ['a']);

      await player.next();
      await settle();
      expect(ids, ['a', 'b']);

      await player.seek(const Duration(seconds: 10));
      await player.pause();
      await player.play();
      await settle();
      expect(ids, ['a', 'b']);

      player.cycleRepeat();
      player.cycleRepeat();
      backend.complete();
      await settle();
      expect(player.state.current, b);
      expect(ids, ['a', 'b', 'b']);

      backend.setPosition(const Duration(seconds: 5));
      await player.previous();
      await settle();
      expect(ids, ['a', 'b', 'b', 'b']);
    });

    test('a failed start does not emit', () async {
      final ids = <String>[];
      final sub = player.trackStarts.listen((t) => ids.add(t.id));
      addTearDown(sub.cancel);
      resolver.missing.add('a');
      await player.playQueue([a, b]);
      await settle();
      expect(ids, ['b']);
    });
  });
}
