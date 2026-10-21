import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:songies/core/log.dart';
import 'package:songies/player/audio_backend.dart';

/// Registers the desktop engine (libmpv via media_kit; a no-op on Android) and
/// configures the platform audio session for music. Call before `runApp`.
Future<void> initAudioPlatform() async {
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
}

/// [AudioBackend] over `just_audio` (ExoPlayer on Android, libmpv on desktop).
///
/// It never pauses or resumes on its own: audio-session events are exposed as
/// [becomingNoisy] and [interruptions] so the player service stays the owner of
/// the playing flag (see `bindAudioSession`).
class JustAudioBackend implements AudioBackend {
  JustAudioBackend() {
    _subs = [
      _player.playerStateStream.listen((s) {
        _playing = s.playing;
        _processing = s.processingState;
        _emit();
      }),
      _player.positionStream.listen((p) {
        _position = p;
        _emit();
      }),
      _player.durationStream.listen((d) {
        _duration = d;
        _emit();
      }),
    ];
  }

  final AudioPlayer _player = AudioPlayer();
  late final List<StreamSubscription<Object?>> _subs;
  final StreamController<BackendState> _controller =
      StreamController<BackendState>.broadcast();

  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(
      BackendState(
        playing: _playing,
        buffering:
            _processing == ProcessingState.loading ||
            _processing == ProcessingState.buffering,
        completed: _processing == ProcessingState.completed,
        position: _position,
        duration: _duration,
      ),
    );
  }

  @override
  Stream<BackendState> get states => _controller.stream;

  /// Headphones unplugged / Bluetooth lost (Android).
  Stream<void> get becomingNoisy => Stream.fromFuture(
    AudioSession.instance,
  ).asyncExpand((s) => s.becomingNoisyEventStream);

  /// Another app took or released audio focus.
  Stream<AudioInterruptionEvent> get interruptions => Stream.fromFuture(
    AudioSession.instance,
  ).asyncExpand((s) => s.interruptionEventStream);

  @override
  Future<void> setSource(AudioSourceRef s) async {
    final source = switch (s) {
      FileSource(:final path) => AudioSource.file(path),
      UrlSource(:final url) => AudioSource.uri(url),
    };
    await _player.setAudioSource(source);
  }

  /// Starts playback. just_audio completes this future only when playback
  /// stops again, so it is deliberately not awaited.
  @override
  Future<void> play() async {
    _player.play().catchError((Object e, StackTrace st) {
      AppLog.w('just_audio play failed', e, st);
    });
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration d) => _player.seek(d);

  /// Unloads the source; a later [setSource] reuses the same player.
  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _controller.close();
    await _player.dispose();
  }
}
