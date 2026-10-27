import '../core/log.dart';
import '../core/result.dart';
import '../youtube/yt_models.dart';

/// One way of turning a YouTube video id into a playable audio stream.
abstract class StreamSource {
  /// Short route name for logs (`innertube`, `yt-dlp`).
  String get name;

  Future<Result<YtStream>> resolveStream(String videoId);
}

/// Tries [StreamSource]s in order. A video that is unavailable (`notFound`)
/// ends the search at once; any other failure moves on to the next source,
/// so a failing fast route only costs time, never an error by itself.
class FallbackStreamSource implements StreamSource {
  FallbackStreamSource(this._sources) : assert(_sources.isNotEmpty);

  final List<StreamSource> _sources;

  @override
  String get name => _sources.map((s) => s.name).join('>');

  @override
  Future<Result<YtStream>> resolveStream(String videoId) async {
    final sw = Stopwatch()..start();
    Result<YtStream>? last;
    for (final s in _sources) {
      Result<YtStream> r;
      try {
        r = await s.resolveStream(videoId);
      } catch (e, st) {
        AppLog.w('stream $videoId: ${s.name} threw', e, st);
        r = Err(
          ytFailure(YtErrorKind.extractor, '${s.name} threw: $e', cause: e),
        );
      }
      switch (r) {
        case Ok():
          AppLog.i(
            'stream $videoId via ${s.name} in ${sw.elapsedMilliseconds} ms',
          );
          return r;
        case Err(:final failure):
          if (ytErrorKindOf(failure) == YtErrorKind.notFound) {
            AppLog.i(
              'stream $videoId unavailable via ${s.name} in '
              '${sw.elapsedMilliseconds} ms: ${failure.message}',
            );
            return r;
          }
          AppLog.i(
            'stream $videoId: ${s.name} failed after '
            '${sw.elapsedMilliseconds} ms: ${failure.message}',
          );
          last = r;
      }
    }
    return last!;
  }
}
