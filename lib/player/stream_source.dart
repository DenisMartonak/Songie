import '../core/log.dart';
import '../core/result.dart';
import '../youtube/yt_models.dart';

/// One way of turning a YouTube video id into a playable audio stream.
abstract class StreamSource {
  /// Short route name for logs (`innertube`, `yt-dlp`).
  String get name;

  Future<Result<YtStream>> resolveStream(String videoId);
}

/// The playback routes in order: Innertube, then yt-dlp. With [forceYtDlp]
/// (the dev-only `--dart-define=SONGIES_FORCE_YTDLP=true`, read in
/// `main.dart`) Innertube is left out, to time or test the yt-dlp route.
List<StreamSource> playbackSources({
  required StreamSource innertube,
  required StreamSource ytDlp,
  bool forceYtDlp = false,
}) => forceYtDlp ? [ytDlp] : [innertube, ytDlp];

/// Tries [StreamSource]s in order; any failure moves on to the next source,
/// so a failing fast route only costs time, never an error by itself. That
/// includes an earlier source's `notFound` (Innertube's verdict is a
/// heuristic): only the LAST source (yt-dlp) can confirm a video is
/// unavailable (ruling R12, superseding R2's stop-on-notFound). An
/// `ageRestricted` answer stops the chain: no anonymous route can play it.
/// When every source fails, the last source's result is returned.
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
          final notFound = ytErrorKindOf(failure) == YtErrorKind.notFound;
          AppLog.i(
            notFound
                ? 'stream $videoId unavailable via ${s.name} in '
                      '${sw.elapsedMilliseconds} ms: ${failure.message}'
                : 'stream $videoId: ${s.name} failed after '
                      '${sw.elapsedMilliseconds} ms: ${failure.message}',
          );
          last = r;
          // Anonymous yt-dlp would get the same answer, seconds later;
          // AgeRestrictedStreamSource retries signed in instead.
          if (ytErrorKindOf(failure) == YtErrorKind.ageRestricted) return r;
      }
    }
    return last!;
  }
}
