import '../core/log.dart';
import '../core/result.dart';
import '../player/stream_source.dart';
import '../youtube/yt_models.dart';
import 'clients.dart';
import 'innertube_client.dart';

/// The `playbackTracking` URLs of a `player` response, for play reports.
class PlaybackTracking {
  const PlaybackTracking({
    required this.playbackUrl,
    required this.watchtimeUrl,
  });

  /// `videostatsPlaybackUrl.baseUrl` (`/api/stats/playback`).
  final Uri playbackUrl;

  /// `videostatsWatchtimeUrl.baseUrl` (`/api/stats/watchtime`).
  final Uri watchtimeUrl;
}

/// Instant streams from Innertube's `player` endpoint, trying each of
/// [kPlayerClients] in order (the last one that worked first).
///
/// The answer is `notFound` only when every client tried says the *video*
/// is unavailable (UNPLAYABLE, ERROR, or LOGIN_REQUIRED for age); any other
/// outcome is a plain `Err` so [FallbackStreamSource] moves on to yt-dlp.
class InnertubeStreamSource implements StreamSource {
  InnertubeStreamSource(
    this._client, {
    List<ClientIdentity> clients = kPlayerClients,
  }) : _clients = clients,
       assert(clients.isNotEmpty);

  final InnertubeClient _client;
  final List<ClientIdentity> _clients;

  /// The client that last returned a playable url this session.
  ClientIdentity? _preferred;

  /// Set once a bootstrap request succeeded, so a response that carries no
  /// visitor id doesn't cost an extra request on every play.
  bool _bootstrapped = false;
  Future<void>? _bootstrapping;

  static const _maxTracked = 50;

  /// DateTime's largest epoch, in seconds.
  static const _maxEpochS = 8640000000000;
  // Insertion-ordered (a map literal is a LinkedHashMap): oldest first.
  final _tracking = <String, PlaybackTracking>{};

  @override
  String get name => 'innertube';

  /// The `playbackTracking` of the last `player` response for [videoId].
  PlaybackTracking? trackingFor(String videoId) => _tracking[videoId];

  @override
  Future<Result<YtStream>> resolveStream(String videoId) async {
    // Never throws: anything unexpected falls through to the next source.
    try {
      return await _resolve(videoId);
    } catch (e) {
      return Err(
        ytFailure(YtErrorKind.extractor, 'innertube $videoId: $e', cause: e),
      );
    }
  }

  Future<Result<YtStream>> _resolve(String videoId) async {
    await _ensureVisitor();
    final preferred = _preferred;
    final order = [
      ?preferred,
      ..._clients.where((c) => !identical(c, preferred)),
    ];
    final reasons = <String>[];
    var allVideoLevel = true;
    for (final c in order) {
      final r = await _client.call(c, 'player', {
        'videoId': videoId,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
      });
      final _Outcome o;
      switch (r) {
        case Err(:final failure):
          o = _Outcome.fail(failure.message);
        case Ok(:final value):
          o = _parse(c, videoId, value);
      }
      if (o.stream != null) {
        _preferred = c;
        return Ok(o.stream!);
      }
      reasons.add('${c.name}: ${o.reason}');
      if (!o.videoLevel) allVideoLevel = false;
    }
    final detail = 'innertube $videoId: ${reasons.join('; ')}';
    if (allVideoLevel) return Err(ytFailure(YtErrorKind.notFound, detail));
    return Err(ytFailure(YtErrorKind.extractor, detail));
  }

  /// `player` without a visitor id answers "Sign in to confirm you're not a
  /// bot", so one WEB_REMIX request fetches one first (InnertubeClient
  /// stores the id from any response). `browse FEmusic_home` is the request
  /// verified to hand out a working id (docs/innertube-notes.md).
  Future<void> _ensureVisitor() async {
    if (_bootstrapped || await _client.visitorData() != null) return;
    final running = _bootstrapping ??= _bootstrap();
    await running;
  }

  Future<void> _bootstrap() async {
    try {
      final r = await _client.call(kWebRemix, 'browse', {
        'browseId': 'FEmusic_home',
      });
      switch (r) {
        case Ok():
          _bootstrapped = true;
        case Err(:final failure):
          AppLog.w('Visitor id bootstrap failed: ${failure.message}');
      }
    } finally {
      _bootstrapping = null;
    }
  }

  _Outcome _parse(ClientIdentity c, String videoId, Map<String, Object?> j) {
    final ps = _map(j['playabilityStatus']);
    final status = ps?['status'];
    final reason = ps?['reason'] is String ? ps!['reason']! as String : '';
    if (status != 'OK') {
      final label = '$status${reason.isEmpty ? '' : ' "$reason"'}';
      return _isVideoLevel(status, reason)
          ? _Outcome.unavailable(label)
          : _Outcome.fail(label);
    }
    _rememberTracking(videoId, _map(j['playbackTracking']));
    final formats = _map(j['streamingData'])?['adaptiveFormats'];
    if (formats is! List) return const _Outcome.fail('no formats');
    final url = _bestAudio(formats);
    if (url == null) return const _Outcome.fail('no plain audio url');
    final expire = int.tryParse(url.queryParameters['expire'] ?? '');
    // Out of DateTime's range (or nonsense): unknown, the resolver's TTL.
    final validExpire = expire != null && expire > 0 && expire <= _maxEpochS;
    return _Outcome.ok(
      YtStream(
        url: url,
        headers: {'User-Agent': c.userAgent},
        expiresAt: !validExpire
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true),
      ),
    );
  }

  /// Whether a non-OK status is about the video itself (removed, private,
  /// region-blocked, age-restricted) rather than this client being refused.
  static bool _isVideoLevel(Object? status, String reason) {
    final r = reason.toLowerCase();
    return switch (status) {
      'UNPLAYABLE' || 'ERROR' => !r.contains('reload'),
      'LOGIN_REQUIRED' => RegExp(
        r'\bage\b|age-restrict|inappropriate for some users',
      ).hasMatch(r),
      _ => false,
    };
  }

  /// Audio-only formats with a plain `url`: opus first, then m4a, then any
  /// other, the highest bitrate within each (yt-dlp's
  /// `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`).
  static Uri? _bestAudio(List<Object?> formats) {
    ({int rank, int bitrate, Uri url})? best;
    for (final f in formats) {
      if (f is! Map) continue;
      final mime = f['mimeType'];
      final url = f['url'];
      if (mime is! String || !mime.startsWith('audio/')) continue;
      // signatureCipher-only formats need the JS player: skipped.
      if (url is! String) continue;
      final u = Uri.tryParse(url);
      if (u == null) continue;
      final rank = mime.contains('opus')
          ? 2
          : mime.startsWith('audio/mp4')
          ? 1
          : 0;
      final bitrate = f['bitrate'] is num ? (f['bitrate']! as num).toInt() : 0;
      if (best == null ||
          rank > best.rank ||
          (rank == best.rank && bitrate > best.bitrate)) {
        best = (rank: rank, bitrate: bitrate, url: u);
      }
    }
    return best?.url;
  }

  void _rememberTracking(String videoId, Map<String, Object?>? t) {
    Uri? base(String key) {
      final v = _map(t?[key])?['baseUrl'];
      return v is String ? Uri.tryParse(v) : null;
    }

    final playback = base('videostatsPlaybackUrl');
    final watchtime = base('videostatsWatchtimeUrl');
    _tracking.remove(videoId);
    if (playback == null || watchtime == null) return;
    _tracking[videoId] = PlaybackTracking(
      playbackUrl: playback,
      watchtimeUrl: watchtime,
    );
    while (_tracking.length > _maxTracked) {
      _tracking.remove(_tracking.keys.first);
    }
  }

  static Map<String, Object?>? _map(Object? v) =>
      v is Map ? v.cast<String, Object?>() : null;
}

class _Outcome {
  const _Outcome.ok(YtStream this.stream) : reason = 'ok', videoLevel = false;
  const _Outcome.fail(this.reason) : stream = null, videoLevel = false;
  const _Outcome.unavailable(this.reason) : stream = null, videoLevel = true;

  final YtStream? stream;
  final String reason;
  final bool videoLevel;
}
