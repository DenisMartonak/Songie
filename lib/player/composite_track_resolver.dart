import 'dart:async';

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../youtube/yt_models.dart';
import 'audio_backend.dart';
import 'stream_resolver.dart';
import 'track_resolver.dart';

/// Local file first, then a YouTube stream for `source == 'yt'` tracks.
class CompositeTrackResolver extends TrackResolver {
  CompositeTrackResolver(
    this._local,
    this._streams, {
    this.onStreamMetadata,
  }); // ignore: prefer_initializing_formals

  final LocalTrackResolver _local;
  final StreamResolver _streams;
  final Future<void> Function(Track t, YtStream s)? onStreamMetadata;

  static bool _streamable(Track t) =>
      t.source == 'yt' && t.ytVideoId != null && !t.unavailable;

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    final local = await _local.resolve(t);
    if (local is Ok<AudioSourceRef>) return local;
    if (t.unavailable) {
      return const Err(
        Failure(FailureKind.notFound, 'This track is unavailable on YouTube'),
      );
    }
    final videoId = t.ytVideoId;
    if (t.source != 'yt' || videoId == null) return local;
    final r = await _streams.resolveStream(videoId);
    switch (r) {
      case Ok(:final value):
        _reportMetadata(t, value);
        return Ok(UrlSource(value.url, headers: value.headers));
      case Err(:final failure):
        return Err(failure);
    }
  }

  void _reportMetadata(Track t, YtStream s) {
    final cb = onStreamMetadata;
    if (cb == null) return;
    unawaited(
      Future.sync(() => cb(t, s)).catchError((Object e, StackTrace st) {
        AppLog.w('Updating metadata of ${t.id} failed', e, st);
      }),
    );
  }

  @override
  Future<void> prefetch(Track t) async {
    if (!_streamable(t)) return;
    if (await _local.resolve(t) is Ok<AudioSourceRef>) return;
    await _streams.prefetch(t.ytVideoId!);
  }

  @override
  void invalidate(Track t) {
    final id = t.ytVideoId;
    if (t.source == 'yt' && id != null) _streams.invalidate(id);
  }
}
