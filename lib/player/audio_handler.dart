import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/player_service.dart';

/// Bridges [PlayerService] to the platform media session: the Android
/// notification, lock screen and headset buttons, and Linux MPRIS (through
/// `audio_service_mpris`).
///
/// It only mirrors [PlayerService.states] and forwards commands to the
/// service, so the service stays the owner of the playing flag.
class SongiesAudioHandler extends BaseAudioHandler with SeekHandler {
  SongiesAudioHandler(
    this._player,
    this._art, {
    this.idleStop = const Duration(minutes: 10),
    this.publishProgress = false,
  }) {
    _sub = _player.states.listen(_onState);
    _onState(_player.state);
  }

  /// How long playback may stay paused before the session is released.
  final Duration idleStop;

  /// Also republish [playbackState] each time the position has moved by
  /// [_seekJump] since the last publish, driven by the position events the
  /// player already emits (no timer). Needed where the platform plugin does not
  /// project the position itself: Linux MPRIS reports the last published
  /// position verbatim. Android's MediaSession projects it, so it stays off.
  final bool publishProgress;

  static const String shuffleAction = 'shuffle';
  static const String repeatAction = 'repeat';

  /// A position update this far from where the last one projects to counts as
  /// a seek and is always published. Without [publishProgress], ordinary
  /// progress is left to the platform (Android projects it from the clock).
  static const Duration _seekJump = Duration(seconds: 1);

  final PlayerService _player;
  final ArtCache _art;
  late final StreamSubscription<PlayerState> _sub;

  /// The only timer: runs while paused, cancelled on play.
  Timer? _idleTimer;

  /// True after [stop]/the idle timeout until playback starts again; the
  /// session then stays idle even if the paused player changes.
  bool _released = false;
  bool _wasPlaying = false;

  (AudioProcessingState, bool, int, bool, RepeatMode)? _lastKey;
  (String, Duration?, String?)? _lastItemKey;

  /// Stops listening and cancels the idle timer.
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _sub.cancel();
  }

  // --- PlayerService -> media session --------------------------------------

  void _onState(PlayerState s) {
    _publishMediaItem(s);
    _updateIdleTimer(s);
    _publishPlaybackState(s);
  }

  void _publishMediaItem(PlayerState s) {
    final track = s.current;
    final duration = track == null ? null : s.duration ?? _durationOf(track);
    final key = track == null ? null : (track.id, duration, track.artworkRef);
    if (key == _lastItemKey) return;
    _lastItemKey = key;
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    final ref = track.artworkRef;
    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: duration,
        artUri: ref == null ? null : Uri.file(_art.fileFor(ref).path),
      ),
    );
  }

  Duration? _durationOf(Track t) =>
      t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null;

  void _updateIdleTimer(PlayerState s) {
    final startedPlaying = s.playing && !_wasPlaying;
    _wasPlaying = s.playing;
    if (s.current == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      _released = false;
    } else if (s.playing) {
      _idleTimer?.cancel();
      _idleTimer = null;
      // Only a real pause -> play transition brings a released session back;
      // a stale "playing" snapshot arriving after stop() must not.
      if (startedPlaying) _released = false;
    } else if (_idleTimer == null && !_released) {
      _idleTimer = Timer(idleStop, () {
        _idleTimer = null;
        stop();
      });
    }
  }

  void _publishPlaybackState(PlayerState s) {
    if (_released) return;
    final processing = s.current == null
        ? AudioProcessingState.idle
        : s.buffering
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready;
    final key = (processing, s.playing, s.index, s.shuffle, s.repeat);
    final previous = playbackState.value;
    final jumped = (s.position - previous.position).abs() > _seekJump;
    final advanced =
        publishProgress &&
        (s.position - previous.updatePosition).abs() >= _seekJump;
    if (key == _lastKey && !jumped && !advanced) return;
    _lastKey = key;

    playbackState.add(
      PlaybackState(
        processingState: processing,
        playing: s.playing,
        controls: s.current == null ? const [] : _controls(s),
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        updatePosition: s.position,
        queueIndex: s.index < 0 ? null : s.index,
        shuffleMode: s.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (s.repeat) {
          RepeatMode.off => AudioServiceRepeatMode.none,
          RepeatMode.all => AudioServiceRepeatMode.all,
          RepeatMode.one => AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  List<MediaControl> _controls(PlayerState s) => [
    MediaControl.skipToPrevious,
    s.playing ? MediaControl.pause : MediaControl.play,
    MediaControl.skipToNext,
    MediaControl.custom(
      androidIcon: s.shuffle ? 'drawable/ic_shuffle_on' : 'drawable/ic_shuffle',
      label: 'Shuffle',
      name: shuffleAction,
    ),
    MediaControl.custom(
      androidIcon: switch (s.repeat) {
        RepeatMode.off => 'drawable/ic_repeat',
        RepeatMode.all => 'drawable/ic_repeat_on',
        RepeatMode.one => 'drawable/ic_repeat_one_on',
      },
      label: 'Repeat',
      name: repeatAction,
    ),
  ];

  // --- media session -> PlayerService --------------------------------------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case shuffleAction:
        _player.setShuffle(!_player.state.shuffle);
      case repeatAction:
        _player.cycleRepeat();
    }
  }

  /// Pauses and releases the media session (ends the Android foreground
  /// service, so the notification can be dismissed). The queue is kept: the
  /// user can resume from the app, which brings the session back.
  @override
  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _released = true;
    _lastKey = null;
    if (_player.state.playing) await _player.pause();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }
}
