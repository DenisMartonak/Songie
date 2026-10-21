import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:songies/player/player_service.dart';

/// Active link between audio-session events and a [PlayerService].
class AudioSessionBinding {
  AudioSessionBinding._(this._subs);

  final List<StreamSubscription<Object?>> _subs;

  Future<void> cancel() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
  }
}

/// Pauses [player] when audio becomes noisy, and pauses/resumes it around
/// audio-focus interruptions. All changes go through [PlayerService] commands
/// so its playing flag stays in step.
///
/// Ducking is left to the platform. After an interruption, playback resumes
/// only if it was playing when the interruption began and the interruption
/// ended with type [AudioInterruptionType.pause].
AudioSessionBinding bindAudioSession({
  required Stream<void> becomingNoisy,
  required Stream<AudioInterruptionEvent> interruptions,
  required PlayerService player,
}) {
  var wasPlaying = false;
  return AudioSessionBinding._([
    becomingNoisy.listen((_) => player.pause()),
    interruptions.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) return;
        if (player.state.playing) {
          wasPlaying = true;
          player.pause();
        }
      } else {
        if (event.type == AudioInterruptionType.duck) return;
        final resume = wasPlaying && event.type == AudioInterruptionType.pause;
        wasPlaying = false;
        if (resume) player.play();
      }
    }),
  ]);
}
