import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/activity_publisher.dart';
import 'package:songies/player/player_service.dart';

import '../helpers/fake_activity_backend.dart';

Track track(String id, {String source = 'yt'}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  ytVideoId: source == 'yt' ? 'v$id' : null,
  title: 'Song $id',
  artist: 'Artist $id',
  durationMs: 200000,
  unavailable: false,
  searchText: 'song $id',
);

void main() {
  late FakeActivityBackend backend;
  late StreamController<PlayerState> states;
  late PlayerState state;
  late StreamController<Object?> roomChanges;
  String? room;
  late int topCalls;

  /// What the stats give for the top 10 (a test may make it fail or hang).
  late Future<TopSummary?> Function() topAnswer;
  late ActivityPublisher publisher;

  void play(Track? t, {bool playing = true}) {
    state = t == null
        ? const PlayerState()
        : PlayerState(queue: [t], index: 0, playing: playing);
    states.add(state);
  }

  NowPlaying? published() => backend.rowOf('me')?.now;

  void start(FakeAsync async) {
    backend = FakeActivityBackend(now: () => DateTime(2026).add(async.elapsed))
      ..me = 'me';
    states = StreamController<PlayerState>.broadcast();
    roomChanges = StreamController<Object?>.broadcast();
    state = const PlayerState();
    room = null;
    topCalls = 0;
    topAnswer = () async => const TopSummary(artists: ['Beyonce'], songs: []);
    publisher = ActivityPublisher(
      backend: backend,
      states: states.stream,
      current: () => state,
      roomCode: () => room,
      roomChanges: roomChanges.stream,
      top: () {
        topCalls++;
        return topAnswer();
      },
      now: () => DateTime(2026).add(async.elapsed),
    );
    publisher.signedIn();
    async.flushMicrotasks();
  }

  void stop(FakeAsync async) {
    publisher.dispose();
    async.flushMicrotasks();
  }

  test('a song change publishes after 2 s; pausing clears', () {
    fakeAsync((async) {
      start(async);
      play(track('a'));
      async.elapse(const Duration(milliseconds: 1900));
      expect(published(), isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(
        published(),
        const NowPlaying(title: 'Song a', artist: 'Artist a', videoId: 'va'),
      );
      play(track('a'), playing: false);
      async.elapse(const Duration(seconds: 3));
      expect(published(), isNull);
      // A local song is shared without a video id.
      play(track('l', source: 'local'));
      async.elapse(const Duration(seconds: 3));
      expect(published()!.videoId, isNull);
      stop(async);
    });
  });

  test('a long song is published again every 5 minutes', () {
    fakeAsync((async) {
      start(async);
      play(track('a'));
      async.elapse(const Duration(seconds: 3));
      backend.calls.clear();
      async.elapse(const Duration(minutes: 5));
      expect(backend.calls, contains('publishNowPlaying'));
      // Position ticks with nothing new publish nothing extra.
      backend.calls.clear();
      for (var i = 0; i < 5; i++) {
        states.add(state);
      }
      async.elapse(const Duration(seconds: 3));
      expect(backend.calls, isNot(contains('publishNowPlaying')));
      stop(async);
    });
  });

  test('starting to host publishes the room code without a song change', () {
    fakeAsync((async) {
      start(async);
      play(track('a'));
      async.elapse(const Duration(seconds: 3));
      room = 'ABCD2345';
      roomChanges.add(null);
      async.elapse(const Duration(seconds: 3));
      expect(backend.rowOf('me')!.roomCode, 'ABCD2345');
      room = null;
      roomChanges.add(null);
      async.elapse(const Duration(seconds: 3));
      expect(backend.rowOf('me')!.roomCode, isNull);
      stop(async);
    });
  });

  test('sharing off: nothing is published', () {
    fakeAsync((async) {
      start(async);
      publisher.setSharing(listening: false, top: false);
      async.flushMicrotasks();
      backend.calls.clear();
      play(track('a'));
      async.elapse(const Duration(minutes: 70));
      expect(backend.calls, isNot(contains('publishNowPlaying')));
      expect(backend.calls, isNot(contains('publishTop')));
      // Back on: what plays goes out again.
      publisher.setSharing(listening: true, top: true);
      async.elapse(const Duration(seconds: 3));
      expect(published()!.title, 'Song a');
      stop(async);
    });
  });

  test('top is published at sign-in and not again within the hour', () {
    fakeAsync((async) {
      start(async);
      expect(topCalls, 1);
      expect(backend.rowOf('me')!.top!.artists, ['Beyonce']);
      play(track('a'));
      async.elapse(const Duration(minutes: 50));
      expect(topCalls, 1);
      async.elapse(const Duration(minutes: 15));
      expect(topCalls, 2);
      stop(async);
    });
  });

  test('a failing top 10 neither escapes nor holds up a switch change', () {
    fakeAsync((async) {
      start(async);
      topAnswer = () async => throw StateError('stats broke');
      async.elapse(const Duration(hours: 2));
      // A top 10 that never comes does not hold up saving a switch.
      topAnswer = () => Completer<TopSummary?>().future;
      var saved = false;
      publisher.setSharing(top: false).then((_) => saved = true);
      async.flushMicrotasks();
      expect(saved, isTrue);
      saved = false;
      publisher.setSharing(top: true).then((_) => saved = true);
      async.flushMicrotasks();
      expect(saved, isTrue);
      stop(async);
    });
  });

  test('signing out clears now playing and stops', () {
    fakeAsync((async) {
      start(async);
      play(track('a'));
      async.elapse(const Duration(seconds: 3));
      expect(published(), isNotNull);
      publisher.signedOut();
      async.flushMicrotasks();
      expect(published(), isNull);
      backend.calls.clear();
      play(track('b'));
      async.elapse(const Duration(minutes: 10));
      expect(backend.calls, isEmpty);
      stop(async);
    });
  });
}
