import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/audio_handler.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';

import '../helpers/fake_audio_backend.dart';

Track track(String id, {int durationMs = 0, String? artworkRef}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist $id',
  album: 'Album $id',
  durationMs: durationMs,
  artworkRef: artworkRef,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver implements TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

Future<void> settle() => pumpEventQueue();

void main() {
  final art = ArtCache(Directory.systemTemp.absolute);
  final a = track('a', durationMs: 180000, artworkRef: 'abc.jpg');
  final b = track('b');
  final c = track('c');

  late FakeAudioBackend backend;
  late PlayerService player;
  late SongiesAudioHandler handler;

  setUp(() {
    backend = FakeAudioBackend();
    player = PlayerService(backend, _Resolver());
    handler = SongiesAudioHandler(player, art);
  });

  tearDown(() async {
    handler.dispose();
    await player.dispose();
  });

  group('playbackState', () {
    test(
      'while playing: pause control, order, compact view, seek, index',
      () async {
        await player.playQueue([a, b, c], startIndex: 1);
        backend.setPosition(const Duration(seconds: 30));
        await settle();

        final s = handler.playbackState.value;
        expect(s.playing, isTrue);
        expect(s.processingState, AudioProcessingState.ready);
        expect(s.updatePosition, const Duration(seconds: 30));
        expect(s.queueIndex, 1);
        expect(s.systemActions, {MediaAction.seek});
        expect(s.androidCompactActionIndices, [0, 1, 2]);
        expect(s.controls.map((e) => e.action), [
          MediaAction.skipToPrevious,
          MediaAction.pause,
          MediaAction.skipToNext,
          MediaAction.custom,
          MediaAction.custom,
        ]);
        expect(s.controls[3].customAction?.name, 'shuffle');
        expect(s.controls[3].androidIcon, 'drawable/ic_shuffle');
        expect(s.controls[4].customAction?.name, 'repeat');
        expect(s.controls[4].androidIcon, 'drawable/ic_repeat');
      },
    );

    test('while paused: play control', () async {
      await player.playQueue([a, b]);
      await player.pause();
      await settle();

      final s = handler.playbackState.value;
      expect(s.playing, isFalse);
      expect(s.processingState, AudioProcessingState.ready);
      expect(s.controls[1].action, MediaAction.play);
    });

    test('empty queue is idle with no controls', () async {
      await settle();
      final s = handler.playbackState.value;
      expect(s.processingState, AudioProcessingState.idle);
      expect(s.controls, isEmpty);
      expect(s.queueIndex, isNull);
    });

    test('buffering is reported', () async {
      await player.playQueue([a]);
      backend.setBuffering(true);
      await settle();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
    });

    test('ordinary progress does not republish; a jump does', () async {
      await player.playQueue([a]);
      await settle();
      final before = handler.playbackState.value;

      backend.setPosition(const Duration(milliseconds: 200));
      await settle();
      expect(identical(handler.playbackState.value, before), isTrue);

      backend.setPosition(const Duration(seconds: 90));
      await settle();
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 90),
      );
    });

    test('progress mode republishes every second of progress', () async {
      handler.dispose();
      handler = SongiesAudioHandler(player, art, publishProgress: true);
      await player.playQueue([a]);
      await settle();
      final first = handler.playbackState.value;

      backend.setPosition(const Duration(milliseconds: 800));
      await settle();
      expect(identical(handler.playbackState.value, first), isTrue);

      backend.setPosition(const Duration(milliseconds: 1200));
      await settle();
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(milliseconds: 1200),
      );

      final second = handler.playbackState.value;
      backend.setPosition(const Duration(milliseconds: 1600));
      await settle();
      expect(identical(handler.playbackState.value, second), isTrue);

      backend.setPosition(const Duration(milliseconds: 2300));
      await settle();
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(milliseconds: 2300),
      );
    });

    test('default mode leaves progress to the system', () async {
      await player.playQueue([a]);
      await settle();
      final first = handler.playbackState.value;

      backend.setPosition(const Duration(milliseconds: 800));
      await settle();
      expect(identical(handler.playbackState.value, first), isTrue);
    });

    test('shuffle and repeat toggles show in the controls', () async {
      await player.playQueue([a, b]);
      player.setShuffle(true);
      player.cycleRepeat();
      await settle();

      final s = handler.playbackState.value;
      expect(s.shuffleMode, AudioServiceShuffleMode.all);
      expect(s.repeatMode, AudioServiceRepeatMode.all);
      expect(s.controls[3].androidIcon, 'drawable/ic_shuffle_on');
      expect(s.controls[4].androidIcon, 'drawable/ic_repeat_on');

      player.cycleRepeat();
      await settle();
      expect(
        handler.playbackState.value.controls[4].androidIcon,
        'drawable/ic_repeat_one_on',
      );
    });
  });

  group('mediaItem', () {
    test('current track: title, artist, album, duration, file art', () async {
      await player.playQueue([a, b]);
      await settle();

      final item = handler.mediaItem.value!;
      expect(item.id, 'a');
      expect(item.title, 'Title a');
      expect(item.artist, 'Artist a');
      expect(item.album, 'Album a');
      expect(item.duration, const Duration(minutes: 3));
      expect(item.artUri, Uri.file(art.fileFor('abc.jpg').path));
      expect(item.artUri!.scheme, 'file');
    });

    test('changes with the track; no artwork means no artUri', () async {
      await player.playQueue([a, b]);
      await player.next();
      await settle();

      final item = handler.mediaItem.value!;
      expect(item.id, 'b');
      expect(item.artUri, isNull);
      expect(item.duration, isNull);
    });

    test('picks up the duration the backend reports', () async {
      await player.playQueue([b]);
      backend.setDuration(const Duration(seconds: 200));
      await settle();
      expect(handler.mediaItem.value!.duration, const Duration(seconds: 200));
    });

    test('is cleared when the queue empties', () async {
      await player.playQueue([a]);
      await settle();
      await player.playQueue([]);
      await settle();
      expect(handler.mediaItem.value, isNull);
    });
  });

  group('commands delegate to PlayerService', () {
    test('customAction shuffle toggles shuffle', () async {
      await player.playQueue([a, b, c]);
      await handler.customAction('shuffle');
      expect(player.state.shuffle, isTrue);
      await handler.customAction('shuffle');
      expect(player.state.shuffle, isFalse);
    });

    test('customAction repeat cycles repeat', () async {
      await handler.customAction('repeat');
      expect(player.state.repeat, RepeatMode.all);
      await handler.customAction('repeat');
      expect(player.state.repeat, RepeatMode.one);
      await handler.customAction('repeat');
      expect(player.state.repeat, RepeatMode.off);
    });

    test('skipToNext / skipToPrevious', () async {
      await player.playQueue([a, b, c]);
      await handler.skipToNext();
      expect(player.state.index, 1);
      await handler.skipToPrevious();
      expect(player.state.index, 0);
    });

    test('seek', () async {
      await player.playQueue([a]);
      await handler.seek(const Duration(seconds: 42));
      expect(backend.calls.last, 'seek:42000');
      expect(player.state.position, const Duration(seconds: 42));
    });

    test('play and pause', () async {
      await player.playQueue([a]);
      await handler.pause();
      expect(player.state.playing, isFalse);
      await handler.play();
      expect(player.state.playing, isTrue);
    });
  });

  group('idle stop', () {
    // Each case builds everything inside fakeAsync so timers are virtual.
    void inFakeAsync(
      void Function(
        FakeAsync async,
        PlayerService player,
        SongiesAudioHandler handler,
      )
      body,
    ) {
      fakeAsync((async) {
        final be = FakeAudioBackend();
        final p = PlayerService(be, _Resolver());
        final h = SongiesAudioHandler(
          p,
          art,
          idleStop: const Duration(milliseconds: 50),
        );
        body(async, p, h);
        h.dispose();
      });
    }

    test('paused past the window stops the service but keeps the queue', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b]);
        async.flushMicrotasks();
        p.pause();
        async.flushMicrotasks();
        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.ready,
        );

        async.elapse(const Duration(milliseconds: 80));

        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        expect(h.playbackState.value.playing, isFalse);
        expect(p.state.queue, [a, b]);
        expect(p.state.index, 0);
      });
    });

    test('playing within the window cancels the stop', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b]);
        async.flushMicrotasks();
        p.pause();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 30));
        p.play();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.ready,
        );
        expect(h.playbackState.value.playing, isTrue);
      });
    });

    test('keeps counting across extra paused-state updates', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b]);
        async.flushMicrotasks();
        p.pause();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 30));
        p.setShuffle(true); // another state emission while still paused
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 30));

        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
      });
    });

    test('playing again after the stop brings the session back', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b]);
        async.flushMicrotasks();
        p.pause();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 80));
        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.idle,
        );

        p.play();
        async.flushMicrotasks();

        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.ready,
        );
        expect(h.playbackState.value.playing, isTrue);
        expect(h.mediaItem.value!.id, 'a');
      });
    });

    test('a queue edit while stopped does not resurrect the notification', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b, c]);
        async.flushMicrotasks();
        p.pause();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 80));

        p.move(2, 1);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
      });
    });

    test('stop() while playing pauses and goes idle, queue intact', () {
      inFakeAsync((async, p, h) {
        p.playQueue([a, b]);
        async.flushMicrotasks();
        h.stop();
        async.flushMicrotasks();

        expect(p.state.playing, isFalse);
        expect(p.state.queue, [a, b]);
        expect(
          h.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
      });
    });
  });
}
