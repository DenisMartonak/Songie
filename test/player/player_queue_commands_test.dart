import 'dart:math';

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

  group('playNext', () {
    test('inserts right after the current song', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.playNext([x, y]);

      expect(player.state.queue, hasLength(12));
      expect(player.state.index, 3);
      expect(player.state.current, ten[3]);
      expect(player.state.queue[4], x);
      expect(player.state.queue[5], y);
      expect(player.state.queue[6], ten[4]);
    });

    test('the inserted songs play next', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.playNext([x]);
      backend.clearCalls();
      await player.next();
      expect(backend.sources, ['/music/x.mp3']);
    });

    test('with shuffle on, they still play next and stay next to the '
        'current song when shuffle is turned off', () async {
      player.setShuffle(true);
      await player.playQueue(ten, startIndex: 3);
      await player.playNext([x, y]);
      expect(player.state.queue[1], x);
      expect(player.state.queue[2], y);

      player.setShuffle(false);
      expect(ids(player.state.queue), [
        't0', 't1', 't2', 't3', 'x', 'y', 't4', 't5', 't6', 't7', 't8', 't9', //
      ]);
      expect(player.state.current, ten[3]);
    });

    test('runs after an earlier playQueue that is still starting', () async {
      final f = player.playQueue([ten[0], ten[1]]);
      final g = player.playNext([x]);
      await Future.wait([f, g]);
      expect(ids(player.state.queue), ['t0', 'x', 't1']);
    });

    test('on an empty queue it becomes the queue without starting', () async {
      await player.playNext([x, y]);
      expect(ids(player.state.queue), ['x', 'y']);
      expect(player.state.index, 0);
      expect(player.state.playing, isFalse);
      expect(backend.sources, isEmpty);
    });

    test('nothing to add is a no-op', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.playNext([]);
      expect(player.state.queue, hasLength(10));
    });
  });

  group('addToQueue', () {
    test('appends to the end', () async {
      await player.playQueue(ten, startIndex: 3);
      await player.addToQueue([x, y]);
      expect(player.state.queue, hasLength(12));
      expect(ids(player.state.queue).sublist(10), ['x', 'y']);
      expect(player.state.index, 3);
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
      expect(ids(player.state.queue).sublist(10), ['x', 'y']);
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
    await player.playNext([y]);
    expect(player.queueEpoch, e1);
  });
}
