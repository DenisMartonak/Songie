import 'dart:async';

import '../core/connectivity.dart';
import '../core/log.dart';
import '../core/result.dart';
import '../data/settings_repository.dart';
import '../youtube/yt_models.dart';
import '../youtube/ytdlp_client.dart';
import 'audio_backend.dart';

const _expiryMargin = Duration(minutes: 10);
const _unknownExpiryTtl = Duration(hours: 1);

/// Resolves YouTube video ids to playable stream URLs, cached in memory only.
class StreamResolver {
  StreamResolver(
    this._client,
    this._net,
    this._settings, {
    DateTime Function()? now,
    bool? wifiOnlyFallback,
  }) : _now = now ?? DateTime.now,
       _wifiOnlyFallback = wifiOnlyFallback ?? wifiOnlyDefault() {
    // URLs are tied to the device's IP, so any network change invalidates them.
    _sub = _net.changes.listen((_) => _clear());
  }

  final YtDlpClient _client;
  final NetworkStatus _net;
  final SettingsRepository _settings;
  final DateTime Function() _now;
  final bool _wifiOnlyFallback;
  late final StreamSubscription<NetworkKind> _sub;

  final Map<String, ({YtStream stream, DateTime validUntil})> _cache = {};
  final Map<String, Future<Result<YtStream>>> _inFlight = {};
  // The running fetch of each id; a fetch that is no longer current (it was
  // invalidated or the network changed) does not write the cache.
  final Map<String, Object> _tokens = {};

  void _clear() {
    _tokens.clear();
    _cache.clear();
    _inFlight.clear();
  }

  /// Drops the cached stream of [videoId] (e.g. after the engine rejected it).
  void invalidate(String videoId) {
    _cache.remove(videoId);
    _inFlight.remove(videoId);
    _tokens.remove(videoId);
  }

  void dispose() {
    _sub.cancel();
    _cache.clear();
    _inFlight.clear();
  }

  Future<Result<UrlSource>> resolve(String videoId) async {
    final r = await resolveStream(videoId);
    return switch (r) {
      Ok(:final value) => Ok(UrlSource(value.url, headers: value.headers)),
      Err(:final failure) => Err(failure),
    };
  }

  /// Like [resolve] but returns the whole stream info (rough metadata too).
  Future<Result<YtStream>> resolveStream(String videoId) async {
    final net = await _net.current();
    if (net == NetworkKind.offline) {
      return const Err(Failure(FailureKind.network, "You're offline"));
    }
    if (net == NetworkKind.mobile &&
        await _settings.getBool(kWifiOnly, fallback: _wifiOnlyFallback)) {
      return const Err(
        Failure(
          FailureKind.network,
          'Wi-Fi only is on — connect to Wi-Fi to stream',
        ),
      );
    }
    final cached = _cache[videoId];
    if (cached != null) {
      if (_now().isBefore(cached.validUntil)) return Ok(cached.stream);
      _cache.remove(videoId);
    }
    final existing = _inFlight[videoId];
    if (existing != null) return existing;
    final token = Object();
    _tokens[videoId] = token;
    final future = _fetch(videoId, token);
    _inFlight[videoId] = future;
    return future;
  }

  Future<Result<YtStream>> _fetch(String videoId, Object token) async {
    try {
      final r = await _client.resolveStream(videoId);
      switch (r) {
        case Ok(:final value):
          if (identical(_tokens[videoId], token)) {
            final exp = value.expiresAt;
            _cache[videoId] = (
              stream: value,
              validUntil: exp != null
                  ? exp.subtract(_expiryMargin)
                  : _now().add(_unknownExpiryTtl),
            );
          }
          return r;
        case Err(:final failure):
          if (ytErrorKindOf(failure) == YtErrorKind.network) {
            return Err(
              Failure(
                FailureKind.network,
                ytErrorUserMessage(failure),
                cause: failure.cause,
              ),
            );
          }
          return r;
      }
    } finally {
      if (identical(_tokens[videoId], token)) {
        _tokens.remove(videoId);
        _inFlight.remove(videoId);
      }
    }
  }

  /// Warms the cache; failures are only logged.
  Future<void> prefetch(String videoId) async {
    try {
      final r = await resolveStream(videoId);
      if (r is Err<YtStream>) {
        AppLog.w('Prefetch of $videoId failed: ${r.failure.message}');
      }
    } catch (e, s) {
      AppLog.w('Prefetch of $videoId failed', e, s);
    }
  }
}
