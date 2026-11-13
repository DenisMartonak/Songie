import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:songies/player/player_inputs.dart';
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
/// audio-focus interruptions. All changes go through [inputs] (built on
/// [player] when null), so its playing flag stays in step and, while this
/// device is a room guest, the pause is a local hold: only this device goes
/// quiet, and it plays with the room again when the user resumes it or the
/// interruption ends with resume.
///
/// Ducking is left to the platform. After an interruption, playback resumes
/// only if it was playing when the interruption began (a room guest: if it
/// was not held yet) and the interruption ended with type
/// [AudioInterruptionType.pause].
AudioSessionBinding bindAudioSession({
  required Stream<void> becomingNoisy,
  required Stream<AudioInterruptionEvent> interruptions,
  required PlayerService player,
  PlayerInputs? inputs,
}) {
  final input = inputs ?? PlayerInputs(player);
  var wasPlaying = false;
  return AudioSessionBinding._([
    becomingNoisy.listen((_) => input.hold()),
    interruptions.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) return;
        if (input.holdsForInterruption) {
          wasPlaying = true;
          input.hold();
        }
      } else {
        if (event.type == AudioInterruptionType.duck) return;
        final resume = wasPlaying && event.type == AudioInterruptionType.pause;
        wasPlaying = false;
        if (resume) input.resumeAfterHold();
      }
    }),
  ]);
}
