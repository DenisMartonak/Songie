import 'dart:async';
import 'dart:math';

import '../core/log.dart';
import '../data/database.dart';
import '../player/heard_time.dart';
import '../player/play_rules.dart';
import '../player/player_service.dart';
import 'clients.dart';
import 'innertube_client.dart';
import 'player_stream_source.dart';
import 'transport.dart';
import 'yt_session.dart';

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
    Future<YtSession?> Function()? session,
    Future<PlaybackTracking?> Function(String videoId, YtSession s)?
    accountTracking,
    Random? random,
    // Named parameters can't be private initializing formals.
    // ignore: prefer_initializing_formals
  }) : _session = session,
       // ignore: prefer_initializing_formals
       _accountTracking = accountTracking,
       _random = random ?? Random.secure() {
    _sub = states.listen(_onState);
  }

  static const _cpnChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  final InnertubeStreamSource _src;
  final InnertubeTransport _transport;
  final Random _random;
  // Async because the keyring is read on demand (ensureSession); null unless
  // signed in.
  final Future<YtSession?> Function()? _session;
  final Future<PlaybackTracking?> Function(String videoId, YtSession s)?
  _accountTracking;
  late final StreamSubscription<PlayerState> _sub;

  String? _trackId;
  final _heard = HeardTime();
  Duration? _lastPos;
  bool _reported = false;

  void dispose() => _sub.cancel();

  /// A short song counts as heard when it got within this of its end:
  /// ticks are sparse, so the last one rarely lands exactly on the duration.
  static const _endTolerance = Duration(seconds: 1);

  Track? _track;
  Duration? _length;

  void _onState(PlayerState s) {
    final t = s.current;
    if (t?.id != _trackId) {
      // Natural end or skip: judge the song we are leaving on what was heard.
      _finish();
      _trackId = t?.id;
      _heard.reset();
      _reported = false;
      _lastPos = null;
    }
    _track = t;
    if (t == null) return;
    _length =
        s.duration ??
        (t.durationMs <= 0 ? null : Duration(milliseconds: t.durationMs));
    final last = _lastPos;
    _lastPos = s.position;
    if (_reported) return;
    _heard.onState(playing: s.playing, position: s.position);
    if (s.playing && reachedPlay(_heard.heard, _length)) {
      _report();
    } else if (!s.playing && last != null) {
      // Stopped or completed: the end of a short song may land here.
      _finish();
    }
  }

  /// Reports the current track if its heard time makes a play, allowing the
  /// end tolerance for songs shorter than the threshold.
  void _finish() {
    if (_reported || _track == null) return;
    final length = _length;
    final adjusted = length == null ? null : length - _endTolerance;
    if (reachedPlay(_heard.heard, adjusted)) _report();
  }

  void _report() {
    final t = _track;
    final videoId = t != null && t.source == 'yt' ? t.ytVideoId : null;
    if (videoId == null) return;
    final anonymous = _src.trackingFor(videoId);
    // Signed out, the stream's own tracking is all there is.
    if (anonymous == null && _session == null) return;
    _reported = true;
    final heard = _heard.heard;
    unawaited(_run(videoId, anonymous, heard, _lastPos ?? heard));
  }

  /// A qualified play: signed in, one account-attributed `player` call gives
  /// the tracking URLs; anything failing falls back to the anonymous ones.
  Future<void> _run(
    String videoId,
    PlaybackTracking? anonymous,
    Duration heard,
    Duration position,
  ) async {
    YtSession? session;
    PlaybackTracking? tracking;
    try {
      session = await _session?.call();
      final account = _accountTracking;
      if (session != null && account != null) {
        tracking = await account(videoId, session);
      }
    } catch (_) {
      // No error text: it could be about the session.
      AppLog.w('Play report $videoId: account tracking failed');
    }
    if (tracking == null) {
      session = null;
      tracking = anonymous;
    }
    if (tracking == null) return;
    await _send(videoId, tracking, heard, position, session);
  }

  Future<void> _send(
    String videoId,
    PlaybackTracking tracking,
    Duration heard,
    Duration position,
    YtSession? session,
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
    final plain = {'User-Agent': kPlayerClients.first.userAgent};
    Map<String, String>? signed;
    if (session != null) {
      try {
        signed = {...plain, ...InnertubeClient.signedInHeaders(session)};
      } on FormatException {
        // Unusable cookie: report anonymously rather than not at all.
        AppLog.w('Play report $videoId: unusable session, sent signed out');
      }
    }
    for (final url in [playback, watchtime]) {
      // R8: the session goes only to YouTube itself, over https.
      final withSession = signed != null && sessionAllowed(url);
      try {
        final r = await _transport.get(url, withSession ? signed : plain);
        if (r.status >= 400) {
          AppLog.w('Play report $videoId ${url.path}: HTTP ${r.status}');
        }
      } catch (e) {
        // Signed in, the error text could echo a header: its type only.
        AppLog.w(
          withSession
              ? 'Play report $videoId ${url.path} failed (${e.runtimeType})'
              : 'Play report $videoId ${url.path} failed: $e',
        );
      }
    }
  }

  /// Whether signed-in headers may go to [url]: https, and the host is
  /// `youtube.com` or a subdomain of it (R8).
  static bool sessionAllowed(Uri url) {
    final host = url.host.toLowerCase();
    return url.scheme == 'https' &&
        (host == 'youtube.com' || host.endsWith('.youtube.com'));
  }

  static Uri _with(Uri u, Map<String, String> extra) =>
      u.replace(queryParameters: {...u.queryParameters, ...extra});
}
