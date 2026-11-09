import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:songies/core/log.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/audio_handler.dart';
import 'package:songies/player/player_inputs.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/smtc_binding.dart';

/// Connects [PlayerService] to the operating system's media controls:
/// the Android notification / lock screen / headset buttons and Linux MPRIS
/// (both through `audio_service`), and Windows SMTC.
abstract class MediaControlsBinding {
  /// Picks the implementation for the current platform. On a platform without
  /// system media controls the binding does nothing.
  /// The buttons go through [inputs] (to the room while this device is a
  /// guest); straight to [player] without it.
  static Future<MediaControlsBinding> create(
    PlayerService player,
    ArtCache art, {
    PlayerInputs? inputs,
  }) async {
    if (Platform.isAndroid || Platform.isLinux) {
      return _AudioServiceBinding.start(player, art, inputs);
    }
    if (Platform.isWindows) {
      return SmtcBinding.start(player, art, inputs: inputs);
    }
    return _NoopBinding();
  }

  /// Fires when the user taps the system media notification; the app should
  /// show Now Playing. Never fires on platforms without such a notification.
  Stream<void> get openNowPlayingRequests;

  Future<void> dispose();
}

class _NoopBinding implements MediaControlsBinding {
  @override
  Stream<void> get openNowPlayingRequests => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// Android and Linux: a [SongiesAudioHandler] registered with `audio_service`.
class _AudioServiceBinding implements MediaControlsBinding {
  _AudioServiceBinding._(this._handler, PlayerService player) {
    if (Platform.isAndroid) {
      _permissionSub = player.states.listen((s) {
        if (!s.playing) return;
        _permissionSub?.cancel();
        _permissionSub = null;
        unawaited(_requestNotificationPermission());
      });
    }
  }

  static Future<_AudioServiceBinding> start(
    PlayerService player,
    ArtCache art,
    PlayerInputs? inputs,
  ) async {
    final handler = await AudioService.init(
      // MPRIS shows the last published position as-is, so Linux must keep
      // publishing progress; Android's MediaSession projects it itself.
      builder: () => SongiesAudioHandler(
        player,
        art,
        publishProgress: Platform.isLinux,
        inputs: inputs,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.songies.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_stat_songies',
      ),
    );
    return _AudioServiceBinding._(handler, player);
  }

  final SongiesAudioHandler _handler;
  StreamSubscription<PlayerState>? _permissionSub;

  /// Android 13+ needs POST_NOTIFICATIONS for the media notification to show.
  /// Asked once, the first time playback starts, and never awaited by playback.
  static Future<void> _requestNotificationPermission() async {
    try {
      await Permission.notification.request();
    } catch (e, s) {
      AppLog.w('Notification permission request failed', e, s);
    }
  }

  @override
  Stream<void> get openNowPlayingRequests =>
      AudioService.notificationClicked.where((clicked) => clicked);

  @override
  Future<void> dispose() async {
    await _permissionSub?.cancel();
    _permissionSub = null;
    _handler.dispose();
  }
}
