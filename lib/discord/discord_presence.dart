import 'dart:async';

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'discord_ipc.dart';

/// The Discord application whose name shows as "Listening to …". Public
/// (every Rich Presence client sends it); empty means Discord status is not
/// set up in this build. Paste the Application ID from
/// discord.com/developers between the quotes.
const String kDiscordClientId = String.fromEnvironment(
  'SONGIES_DISCORD_CLIENT_ID',
  defaultValue: '',
);

/// The Rich Presence art asset (uploaded to the Discord application) shown
/// for songs without a public cover, and as the small badge.
const String kDiscordLogoAsset = 'songies';

/// Shows the playing song on the user's Discord profile while [enabled] is
/// on: title, artist, a progress bar and, for YouTube songs, the cover and a
/// "Listen on YouTube Music" button. Paused or stopped clears it.
///
/// Works only from player and setting changes: it tries to reach Discord
/// when there is something to show, never on a timer of its own, and sends
/// at most one update per [settle] (Discord allows 5 per 20 s).
class DiscordPresence {
  DiscordPresence({
    required Stream<PlayerState> states,
    required Stream<bool> enabled,
    required this._rpc,
    required this._clientId,
    DateTime Function()? now,
    this.settle = const Duration(seconds: 1),
  }) : _now = now ?? DateTime.now {
    _stateSub = states.listen((s) {
      _state = s;
      // Position ticks arrive several times a second; only a new song, a
      // pause or resume, or a seek changes what Discord shows.
      final want = _enabled ? _wanted(s) : null;
      final seen = _seen;
      final same = want == null
          ? seen == null
          : seen != null && seen.sameAs(want);
      if (same) return;
      _seen = want;
      _changed();
    });
    _enabledSub = enabled.listen((on) {
      _enabled = on;
      _seen = on ? _wanted(_state) : null;
      _changed();
    });
  }

  /// How long changes gather before one update is sent.
  final Duration settle;

  /// A seek that moves the song's start by more than this updates the bar.
  static const Duration seekTolerance = Duration(seconds: 3);

  /// After failing to reach Discord, the next try waits at least this long.
  static const Duration retryAfter = Duration(seconds: 15);

  final DiscordRpc _rpc;
  final String _clientId;
  final DateTime Function() _now;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<bool> _enabledSub;

  PlayerState? _state;
  bool _enabled = false;

  /// What the latest player state asks Discord to show.
  _Shown? _seen;
  Timer? _timer;
  Future<void> _sending = Future<void>.value();

  /// What Discord shows now: null for nothing.
  _Shown? _shown;
  DateTime? _lastFailedConnect;

  void _changed() {
    _timer?.cancel();
    _timer = Timer(settle, () {
      _sending = _sending.then((_) => _sync()).catchError((Object e) {
        AppLog.w('Updating the Discord status failed: $e');
      });
    });
  }

  Future<void> _sync() async {
    final want = _enabled ? _wanted(_state) : null;
    if (want == null) {
      if (_shown != null && _rpc.connected) await _rpc.setActivity(null);
      _shown = null;
      // Turned off: let go of Discord entirely.
      if (!_enabled) await _rpc.disconnect();
      return;
    }
    if (_shown != null && _shown!.sameAs(want)) return;
    if (!_rpc.connected) {
      final last = _lastFailedConnect;
      if (last != null && _now().difference(last) < retryAfter) return;
      if (!await _rpc.connect(_clientId)) {
        _lastFailedConnect = _now();
        _shown = null;
        return;
      }
      _lastFailedConnect = null;
    }
    if (await _rpc.setActivity(want.activity)) {
      _shown = want;
    } else {
      _shown = null;
    }
  }

  _Shown? _wanted(PlayerState? s) {
    final track = s?.current;
    if (s == null || track == null || !s.playing) return null;
    final start = _now().subtract(s.position);
    return _Shown(
      trackId: track.id,
      start: start,
      activity: discordActivity(track, start: start, duration: s.duration),
    );
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _stateSub.cancel();
    await _enabledSub.cancel();
    await _sending;
    await _rpc.disconnect();
  }
}

class _Shown {
  _Shown({required this.trackId, required this.start, required this.activity});

  final String trackId;
  final DateTime start;
  final Map<String, Object?> activity;

  bool sameAs(_Shown other) =>
      trackId == other.trackId &&
      start.difference(other.start).abs() <= DiscordPresence.seekTolerance;
}

/// The `SET_ACTIVITY` payload for [track], started at [start].
Map<String, Object?> discordActivity(
  Track track, {
  required DateTime start,
  Duration? duration,
}) {
  final videoId = track.source == 'yt' ? track.ytVideoId : null;
  final cover = videoId == null
      ? null
      : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
  final artist = track.artist.trim();
  final album = track.album?.trim();
  return {
    // "Listening to Songies", with a progress bar from the timestamps.
    'type': 2,
    'details': _fit(track.title),
    if (artist.isNotEmpty) 'state': _fit(artist),
    'timestamps': {
      'start': start.millisecondsSinceEpoch,
      if (duration != null && duration > Duration.zero)
        'end': start.add(duration).millisecondsSinceEpoch,
    },
    'assets': {
      'large_image': cover ?? kDiscordLogoAsset,
      'large_text': _fit(album != null && album.isNotEmpty ? album : 'Songies'),
      if (cover != null) ...{
        'small_image': kDiscordLogoAsset,
        'small_text': 'Songies',
      },
    },
    if (videoId != null)
      'buttons': [
        {
          'label': 'Listen on YouTube Music',
          'url': 'https://music.youtube.com/watch?v=$videoId',
        },
      ],
  };
}

/// Discord takes 2 to 128 characters per text field.
String _fit(String text) {
  final t = text.trim();
  if (t.length < 2) return t.padRight(2);
  return t.length <= 128 ? t : '${t.substring(0, 127)}…';
}
