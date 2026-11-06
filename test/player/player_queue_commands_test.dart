import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';

import '../helpers/fake_audio_backend.dart';

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

List<String> ids(List<Track> q) => [for (final t in q) t.id];

/// Like [_Resolver], but while [gate] is set every resolve waits for it,
/// which holds the player's command lock.
class _GatedResolver extends _Resolver {
  Completer<void>? gate;

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    final g = gate;
    if (g != null) await g.future;
    return super.resolve(t);
  }
}

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  final ten = [for (var i = 0; i < 10; i++) track('t$i')];
  final x = track('x');
  final y = track('y');

  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
    backend = FakeAudioBackend();
    player = PlayerService(backend, _Resolver(), random: Random(3));
  });

  tearDown(() => player.dispose());

  group('updateTrack', () {
    test('swaps in the newer row everywhere it is queued', () async {
      await player.playQueue([ten[0], ten[1], ten[0]]);
      player.setShuffle(true);
      final newer = ten[0].copyWith(artworkRef: const Value('yt2-a.jpg'));
      player.updateTrack(newer);

      expect(player.state.current?.artworkRef, 'yt2-a.jpg');
      expect(
        [
          for (final t in player.state.queue)
            if (t.id == 't0') t.artworkRef,
        ],
        ['yt2-a.jpg', 'yt2-a.jpg'],
      );
      player.setShuffle(false);
      expect(player.state.queue.first.artworkRef, 'yt2-a.jpg');
    });

    test('leaves the state alone for a track that is not queued', () async {
      await player.playQueue(ten);
      final before = player.state;
      player.updateTrack(x);
      expect(identical(player.state, before), isTrue);
    });
  });

  group('addToQueue', () {
    test('inserts right after the current song', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([x, y]);
      expect(player.state.queue, hasLength(12));
      expect(ids(player.state.queue).sublist(3, 7), ['t3', 'x', 'y', 't4']);
      expect(player.state.index, 3);
    });

    test('songs added one by one play in the order they were added', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([x]);
      await player.addToQueue([y]);
      expect(ids(player.state.queue).sublist(3, 7), ['t3', 'x', 'y', 't4']);

      backend.clearCalls();
      await player.next();
      await player.next();
      await player.next();
      expect(backend.sources, [
        '/music/x.mp3',
        '/music/y.mp3',
        '/music/t4.mp3',
      ]);
    });

    test('a song queued while a queued one plays goes after the rest of the '
        'queued songs', () async {
      final z = track('z');
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([x, y]);
      await player.next();
      expect(player.state.current, x);
      await player.addToQueue([z]);
      expect(ids(player.state.queue).sublist(4, 8), ['x', 'y', 'z', 't4']);
    });

    test('runs after an earlier playQueue that is still starting', () async {
      final f = player.playQueue([ten[0], ten[1]]);
      final g = player.addToQueue([x]);
      await Future.wait([f, g]);
      expect(ids(player.state.queue), ['t0', 'x', 't1']);
    });

    test('nothing to add is a no-op', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([]);
      expect(player.state.queue, hasLength(10));
    });

    test('turning shuffle on keeps queued songs next', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([x, y]);
      player.setShuffle(true);
      expect(ids(player.state.queue).sublist(0, 3), ['t3', 'x', 'y']);
    });

    test('with shuffle on, the new songs come after the current one', () async {
      player.setShuffle(true);
      await player.playQueue(ten, startIndex: 5);
      final current = player.state.index;
      await player.addToQueue([x, y]);
      final q = ids(player.state.queue);
      expect(q.indexOf('x'), greaterThan(current));
      expect(q.indexOf('y'), greaterThan(current));
      expect(player.state.current, ten[5]);

      player.setShuffle(false);
      expect(ids(player.state.queue).sublist(5, 8), ['t5', 'x', 'y']);
      expect(player.state.current, ten[5]);
    });

    test('on an empty queue it becomes the queue without starting', () async {
      await player.addToQueue([x]);
      expect(ids(player.state.queue), ['x']);
      expect(player.state.index, 0);
      expect(player.state.playing, isFalse);
    });
  });

  test('queueEpoch changes with each playQueue call, not with edits', () async {
    final e0 = player.queueEpoch;
    final f = player.playQueue(ten);
    final e1 = player.queueEpoch;
    expect(e1, isNot(e0));
    await f;
    await player.addToQueue([x]);
    await player.addToQueue([y]);
    expect(player.queueEpoch, e1);
  });
  group('checked edits', () {
    test('removeAtIf removes only on a matching epoch and id', () async {
      await player.playQueue(ten);
      final e = player.stateEpoch;
      expect(await player.removeAtIf(2, 't3', e), isFalse);
      expect(await player.removeAtIf(2, 't2', e + 1), isFalse);
      expect(await player.removeAtIf(10, 't2', e), isFalse);
      expect(await player.removeAtIf(-1, 't2', e), isFalse);
      expect(player.state.queue, hasLength(10));
      expect(await player.removeAtIf(2, 't2', e), isTrue);
      expect(ids(player.state.queue), isNot(contains('t2')));
      expect(player.state.queue, hasLength(9));
    });

    test('playAtIf plays only on a matching epoch and id', () async {
      await player.playQueue(ten);
      final e = player.stateEpoch;
      expect(await player.playAtIf(4, 't5', e), isFalse);
      expect(await player.playAtIf(4, 't4', e - 1), isFalse);
      expect(player.state.current?.id, 't0');
      expect(await player.playAtIf(4, 't4', e), isTrue);
      expect(player.state.current?.id, 't4');
    });

    test('moveIf moves only on a matching epoch, id and target', () async {
      await player.playQueue(ten.take(3).toList());
      final e = player.stateEpoch;
      expect(player.moveIf(0, 2, 't1', e), isFalse);
      expect(player.moveIf(0, 2, 't0', e + 1), isFalse);
      expect(player.moveIf(0, 3, 't0', e), isFalse);
      expect(player.moveIf(0, -1, 't0', e), isFalse);
      expect(ids(player.state.queue), ['t0', 't1', 't2']);
      expect(player.moveIf(1, 1, 't1', e), isTrue);
      expect(player.moveIf(0, 2, 't0', e), isTrue);
      expect(ids(player.state.queue), ['t1', 't2', 't0']);
      expect(player.state.current?.id, 't0');
    });

    group('behind commands still in the lock', () {
      late _GatedResolver resolver;
      late PlayerService gated;

      setUp(() {
        resolver = _GatedResolver();
        gated = PlayerService(FakeAudioBackend(), resolver, random: Random(3));
      });
      tearDown(() => gated.dispose());

      Future<void> holdLock() async {
        resolver.gate = Completer<void>();
        unawaited(gated.next());
        await Future<void>.delayed(Duration.zero);
      }

      void releaseLock() {
        resolver.gate!.complete();
        resolver.gate = null;
      }

      test('checks the queue a pending removeAt left', () async {
        await gated.playQueue(ten.take(5).toList());
        final e = gated.stateEpoch;
        await holdLock();
        unawaited(gated.removeAt(0));
        final missed = gated.removeAtIf(2, 't2', e);
        final hit = gated.removeAtIf(1, 't2', e);
        releaseLock();
        expect(await missed, isFalse);
        expect(await hit, isTrue);
        expect(ids(gated.state.queue), ['t1', 't3', 't4']);
      });

      test('stateEpoch waits for a pending playQueue to land', () async {
        await gated.playQueue(ten.take(3).toList());
        final old = gated.stateEpoch;
        expect(old, gated.queueEpoch);
        await holdLock();
        final pending = gated.playQueue([x, y]);
        expect(gated.queueEpoch, old + 1);
        expect(gated.stateEpoch, old);
        expect(ids(gated.state.queue), ['t0', 't1', 't2']);
        final newEpochOldId = gated.removeAtIf(1, 't1', old + 1);
        final oldEpoch = gated.playAtIf(0, 't0', old);
        releaseLock();
        await pending;
        expect(await newEpochOldId, isFalse);
        expect(await oldEpoch, isFalse);
        expect(gated.stateEpoch, old + 1);
        expect(ids(gated.state.queue), ['x', 'y']);
        expect(gated.state.current?.id, 'x');
      });
    });
  });
}
