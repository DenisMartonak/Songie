import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/media_controls.dart';
import 'package:songies/player/player_inputs.dart';
import 'package:songies/player/player_service.dart';

/// Windows: mirrors [PlayerService] into the System Media Transport Controls
/// (volume flyout, lock screen) and routes its buttons and the keyboard media
/// keys back to the service.
class SmtcBinding implements MediaControlsBinding {
  SmtcBinding._(this._smtc, this._player, this._inputs, this._art) {
    _subs = [
      _smtc.buttonPressStream.listen(_onButton),
      _player.states.listen(_onState),
    ];
    _onState(_player.state);
  }

  static Future<SmtcBinding> start(
    PlayerService player,
    ArtCache art, {
    PlayerInputs? inputs,
  }) async {
    await SMTCWindows.initialize();
    final smtc = SMTCWindows(
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: false,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
    );
    return SmtcBinding._(smtc, player, inputs ?? PlayerInputs(player), art);
  }

  /// A position update this far from where the last one projects to counts as
  /// a seek and is pushed to the timeline.
  static const Duration _seekJump = Duration(seconds: 1);

  final SMTCWindows _smtc;
  final PlayerService _player;

  /// Where the buttons go (the room, while a guest).
  final PlayerInputs _inputs;
  final ArtCache _art;
  late final List<StreamSubscription<Object?>> _subs;

  (String, Duration?, String?)? _metadataKey;
  (String, Duration?)? _timelineKey;
  PlaybackStatus? _status;

  /// What the last timeline push said; SMTC advances the position by itself
  /// while playing, so only changes in continuity need another push.
  bool _pushedPlaying = false;
  Duration _pushedPosition = Duration.zero;
  DateTime _pushedAt = DateTime.now();

  @override
  Stream<void> get openNowPlayingRequests => const Stream.empty();

  void _onButton(PressedButton button) {
    switch (button) {
      case PressedButton.play:
        _inputs.play();
      case PressedButton.pause:
        _inputs.pause();
      case PressedButton.next:
        _inputs.next();
      case PressedButton.previous:
        _inputs.previous();
      default:
        break;
    }
  }

  void _onState(PlayerState s) {
    final track = s.current;
    if (track == null) {
      if (_metadataKey != null) {
        _metadataKey = null;
        _timelineKey = null;
        _smtc.clearMetadata();
      }
      _setStatus(PlaybackStatus.stopped);
      return;
    }

    final duration =
        s.duration ??
        (track.durationMs > 0
            ? Duration(milliseconds: track.durationMs)
            : null);

    final metadataKey = (track.id, duration, track.artworkRef);
    if (metadataKey != _metadataKey) {
      _metadataKey = metadataKey;
      final ref = track.artworkRef;
      _smtc.updateMetadata(
        MusicMetadata(
          title: track.title,
          artist: track.artist,
          album: track.album,
          // SMTC takes a URI, not a bare path.
          thumbnail: ref == null ? null : _art.fileFor(ref).uri.toString(),
        ),
      );
    }

    final now = DateTime.now();
    final projected =
        _pushedPosition +
        (_pushedPlaying ? now.difference(_pushedAt) : Duration.zero);
    final timelineKey = (track.id, duration);
    if (timelineKey != _timelineKey ||
        s.playing != _pushedPlaying ||
        (s.position - projected).abs() > _seekJump) {
      _timelineKey = timelineKey;
      _pushedPlaying = s.playing;
      _pushedPosition = s.position;
      _pushedAt = now;
      final end = (duration ?? Duration.zero).inMilliseconds;
      _smtc.updateTimeline(
        PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: end,
          positionMs: s.position.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: end,
        ),
      );
    }

    _setStatus(s.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
  }

  void _setStatus(PlaybackStatus status) {
    if (status == _status) return;
    _status = status;
    _smtc.setPlaybackStatus(status);
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _smtc.dispose();
  }
}
