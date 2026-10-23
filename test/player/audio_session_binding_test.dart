import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/audio_session_binding.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';

import '../helpers/fake_audio_backend.dart';

class _Resolver implements TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

Track _track(String id) => Track(
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

AudioInterruptionEvent _begin(AudioInterruptionType t) =>
    AudioInterruptionEvent(true, t);
AudioInterruptionEvent _end(AudioInterruptionType t) =>
    AudioInterruptionEvent(false, t);

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  late StreamController<void> noisy;
  late StreamController<AudioInterruptionEvent> interruptions;
  late AudioSessionBinding binding;

  setUp(() async {
    backend = FakeAudioBackend();
    player = PlayerService(backend, _Resolver());
    noisy = StreamController<void>();
    interruptions = StreamController<AudioInterruptionEvent>();
    binding = bindAudioSession(
      becomingNoisy: noisy.stream,
      interruptions: interruptions.stream,
      player: player,
    );
    await player.playQueue([_track('a')]);
    backend.clearCalls();
  });

  tearDown(() async {
    await binding.cancel();
    await noisy.close();
    await interruptions.close();
    await player.dispose();
  });

  Future<void> send(AudioInterruptionEvent e) async {
    interruptions.add(e);
    await pumpEventQueue();
  }

  test('becoming noisy pauses playback', () async {
    noisy.add(null);
    await pumpEventQueue();

    expect(backend.calls, ['pause']);
    expect(player.state.playing, isFalse);
  });

  test('pause interruption pauses, and its end resumes', () async {
    await send(_begin(AudioInterruptionType.pause));
    expect(player.state.playing, isFalse);
    expect(backend.calls, ['pause']);

    await send(_end(AudioInterruptionType.pause));
    expect(player.state.playing, isTrue);
    expect(backend.calls, ['pause', 'play']);
  });

  test('ducking is left alone', () async {
    await send(_begin(AudioInterruptionType.duck));
    await send(_end(AudioInterruptionType.duck));

    expect(backend.calls, isEmpty);
    expect(player.state.playing, isTrue);
  });

  test('an interruption that ends as unknown does not resume', () async {
    await send(_begin(AudioInterruptionType.pause));
    await send(_end(AudioInterruptionType.unknown));

    expect(player.state.playing, isFalse);
    expect(backend.calls, ['pause']);
  });

  test(
    'an unknown (permanent) interruption pauses and never resumes',
    () async {
      await send(_begin(AudioInterruptionType.unknown));
      await send(_end(AudioInterruptionType.unknown));

      expect(player.state.playing, isFalse);
      expect(backend.calls, ['pause']);
    },
  );

  test('does not resume playback that was already paused', () async {
    await player.pause();
    backend.clearCalls();

    await send(_begin(AudioInterruptionType.pause));
    await send(_end(AudioInterruptionType.pause));

    expect(backend.calls, isEmpty);
    expect(player.state.playing, isFalse);
  });

  test(
    'a finished interruption does not resume a later manual pause',
    () async {
      await send(_begin(AudioInterruptionType.pause));
      await send(_end(AudioInterruptionType.pause));
      await player.pause();
      backend.clearCalls();

      await send(_end(AudioInterruptionType.pause));

      expect(backend.calls, isEmpty);
      expect(player.state.playing, isFalse);
    },
  );

  test('cancel stops reacting to events', () async {
    await binding.cancel();

    noisy.add(null);
    await send(_begin(AudioInterruptionType.pause));

    expect(backend.calls, isEmpty);
    expect(player.state.playing, isTrue);
  });
}
