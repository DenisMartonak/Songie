import 'dart:async';
import 'dart:math';

import '../core/log.dart';
import '../player/play_rules.dart';
import '../player/player_service.dart';
import 'clients.dart';
import 'player_stream_source.dart';
import 'transport.dart';

/// Tells YouTube a song was played, like the web app does, so the signed-out
/// feed becomes personal. Only reacts to player state, so it does nothing
/// while nothing plays: no timers, no polling.
///
/// Heard time is the sum of small forward position steps while playing; a
/// seek (a big jump either way) and paused time add nothing. Each queue
/// track is reported at most once until another track becomes current.
class PlayReporter {
  PlayReporter(
    Stream<PlayerState> states,
    this._src,
    this._transport, {
    // Kept for the plan's signature; reports carry no wall-clock value.
    // ignore: avoid_unused_constructor_parameters
    DateTime Function()? now,
    Random? random,
  }) : _random = random ?? Random.secure() {
    _sub = states.listen(_onState);
  }

  /// Position steps larger than this are seeks, not listening.
  static const _maxStep = Duration(seconds: 5);
  static const _cpnChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  final InnertubeStreamSource _src;
  final InnertubeTransport _transport;
  final Random _random;
  late final StreamSubscription<PlayerState> _sub;

  String? _trackId;
  Duration _heard = Duration.zero;
  Duration? _lastPos;
  bool _reported = false;

  void dispose() => _sub.cancel();

  void _onState(PlayerState s) {
    final t = s.current;
    if (t?.id != _trackId) {
      _trackId = t?.id;
      _heard = Duration.zero;
      _reported = false;
      _lastPos = null;
    }
    if (t == null) return;
    final last = _lastPos;
    _lastPos = s.position;
    if (_reported) return;
    if (s.playing && last != null) {
      final step = s.position - last;
      if (step > Duration.zero && step <= _maxStep) _heard += step;
    }
    final length =
        s.duration ??
        (t.durationMs <= 0 ? null : Duration(milliseconds: t.durationMs));
    if (!s.playing || !reachedPlay(_heard, length)) return;
    final videoId = t.source == 'yt' ? t.ytVideoId : null;
    if (videoId == null) return;
    final tracking = _src.trackingFor(videoId);
    if (tracking == null) return;
    _reported = true;
    unawaited(_send(videoId, tracking, _heard, s.position));
  }

  Future<void> _send(
    String videoId,
    PlaybackTracking tracking,
    Duration heard,
    Duration position,
  ) async {
    final cpn = String.fromCharCodes(
      List.generate(
        16,
        (_) => _cpnChars.codeUnitAt(_random.nextInt(_cpnChars.length)),
      ),
    );
    final base = {'ver': '2', 'cpn': cpn};
    final playback = _with(tracking.playbackUrl, base);
    final watchtime = _with(tracking.watchtimeUrl, {
      ...base,
      'st': '0',
      'et': heard.inSeconds.toString(),
      'cmt': position.inSeconds.toString(),
    });
    // The user agent of the VISIONOS client, the first of kPlayerClients;
    // which client served the stream isn't exposed.
    final headers = {'User-Agent': kPlayerClients.first.userAgent};
    for (final url in [playback, watchtime]) {
      try {
        final r = await _transport.get(url, headers);
        if (r.status >= 400) {
          AppLog.w('Play report $videoId ${url.path}: HTTP ${r.status}');
        }
      } catch (e) {
        AppLog.w('Play report $videoId ${url.path} failed: $e');
      }
    }
  }

  static Uri _with(Uri u, Map<String, String> extra) =>
      u.replace(queryParameters: {...u.queryParameters, ...extra});
}
