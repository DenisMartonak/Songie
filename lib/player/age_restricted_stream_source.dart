import '../core/log.dart';
import '../core/result.dart';
import '../innertube/yt_session.dart';
import '../youtube/js_runtime.dart';
import '../youtube/yt_models.dart';
import '../youtube/ytdlp_client.dart';
import '../youtube/ytdlp_cookies.dart';
import 'stream_source.dart';

/// Loads the signed-in YouTube session; null when signed out.
typedef SessionLoader = Future<YtSession?> Function();

/// What a signed-in retry of an age-restricted song runs with. Shared by
/// playback and downloads, so both follow the same rule.
class AgeRestrictedAuth {
  AgeRestrictedAuth(this._session, this._runtimes);

  final SessionLoader _session;
  final JsRuntimeFinder _runtimes;

  /// The cookies and runtime to retry with, or why there is no retry:
  /// `ageRestricted` when signed out, `needsRuntime` when yt-dlp has no
  /// JavaScript runtime.
  Future<Result<YtDlpAuth>> forRetry(String videoId) async {
    final session = await _session();
    if (session == null) {
      return Err(ytFailure(YtErrorKind.ageRestricted, '$videoId: signed out'));
    }
    final runtime = await _runtimes.find();
    if (runtime == null) {
      return Err(ytFailure(YtErrorKind.needsRuntime, '$videoId: no runtime'));
    }
    return Ok(YtDlpAuth(session, runtime.args));
  }
}

/// Plays age-restricted songs signed in. Everything goes through [_inner]
/// (the anonymous routes) first, exactly as before; only an `ageRestricted`
/// answer leads to one more yt-dlp run with the session's cookies.
class AgeRestrictedStreamSource implements StreamSource {
  AgeRestrictedStreamSource(this._inner, this._ytDlp, this._auth);

  final StreamSource _inner;
  final YtDlpClient _ytDlp;
  final AgeRestrictedAuth _auth;

  @override
  String get name => '${_inner.name}+age';

  @override
  Future<Result<YtStream>> resolveStream(String videoId) async {
    final r = await _inner.resolveStream(videoId);
    if (r is! Err<YtStream> ||
        ytErrorKindOf(r.failure) != YtErrorKind.ageRestricted) {
      return r;
    }
    final auth = await _auth.forRetry(videoId);
    if (auth is Err<YtDlpAuth>) return Err(auth.failure);
    final sw = Stopwatch()..start();
    final retry = await _ytDlp.resolveStream(
      videoId,
      auth: (auth as Ok<YtDlpAuth>).value,
    );
    AppLog.i(
      'stream $videoId: signed-in yt-dlp '
      '${retry is Ok ? 'played' : 'failed'} in ${sw.elapsedMilliseconds} ms',
    );
    return retry;
  }
}
