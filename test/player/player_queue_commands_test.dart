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
      expect(backend.sources, ['/music/x.mp3', '/music/y.mp3', '/music/t4.mp3']);
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
}
