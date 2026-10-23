import 'dart:async';
import 'dart:convert';

import '../core/result.dart';
import 'yt_json.dart';
import 'yt_models.dart';
import 'ytdlp_runner.dart';

const ytStreamFormat = 'bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio';

/// Maps yt-dlp stderr (from a failed run) to an error kind, using only the
/// `ERROR:` lines; warnings are ignored.
YtErrorKind classifyYtDlpStderr(String stderr) {
  final errors = stderr
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trimLeft().startsWith('ERROR:'))
      .join('\n');
  if (errors.isEmpty) return YtErrorKind.unknown;
  const notFound = [
    'The playlist does not exist',
    'This video is unavailable',
    'Private video',
    'removed for violating',
    // Region-blocked and age-restricted videos: unplayable for this user, but
    // yt-dlp itself works, so playback skips them like private videos.
    'available in your country',
    'Sign in to confirm your age',
    'age-restricted',
  ];
  if (notFound.any(errors.contains)) return YtErrorKind.notFound;
  // A malformed playlist id; elsewhere a 400 means yt-dlp's request is stale.
  if (RegExp(r'\[youtube:tab\][^\n]*HTTP Error 400').hasMatch(errors)) {
    return YtErrorKind.notFound;
  }
  final http4xx = RegExp(r'HTTP Error 4\d\d').hasMatch(errors);
  if (http4xx && errors.contains('[generic]')) return YtErrorKind.notFound;
  if (errors.contains('Unable to connect') ||
      errors.contains('getaddrinfo') ||
      errors.contains('unreachable') ||
      (errors.contains('Unable to download') && !http4xx)) {
    return YtErrorKind.network;
  }
  return YtErrorKind.extractor;
}

class YtDlpClient {
  YtDlpClient(this._runner);

  final YtDlpRunner _runner;

  static const playlistTimeout = Duration(minutes: 10);
  static const streamTimeout = Duration(seconds: 60);

  Future<Result<YtPlaylist>> fetchPlaylist(String canonicalUrl) async {
    final run = await _run([
      '--flat-playlist',
      '-J',
      canonicalUrl,
    ], playlistTimeout);
    if (run is Err<YtDlpRun>) return Err(run.failure);
    final out = (run as Ok<YtDlpRun>).value.stdout;
    try {
      final d = jsonDecode(out);
      if (d is! Map || d['entries'] is! List) {
        return Err(
          ytFailure(
            YtErrorKind.notAPlaylist,
            'response has no playlist entries',
          ),
        );
      }
      return Ok(playlistFromMap(d));
    } on FormatException catch (e) {
      return Err(ytFailure(YtErrorKind.extractor, 'bad JSON: ${e.message}'));
    } catch (e) {
      return Err(ytFailure(YtErrorKind.extractor, 'bad JSON: $e', cause: e));
    }
  }

  Future<Result<YtStream>> resolveStream(String videoId) async {
    final run = await _run([
      '-J',
      '--no-playlist',
      '-f',
      ytStreamFormat,
      'https://music.youtube.com/watch?v=$videoId',
    ], streamTimeout);
    if (run is Err<YtDlpRun>) return Err(run.failure);
    try {
      return Ok(parseStreamJson((run as Ok<YtDlpRun>).value.stdout));
    } catch (e) {
      return Err(ytFailure(YtErrorKind.extractor, 'bad JSON: $e', cause: e));
    }
  }

  /// Runs yt-dlp; Ok only for exit code 0 (stderr is ignored then).
  Future<Result<YtDlpRun>> _run(List<String> args, Duration timeout) async {
    final YtDlpRun r;
    try {
      r = await _runner.run(args, timeout: timeout);
    } on YtDlpMissing catch (e) {
      return Err(ytFailure(YtErrorKind.missingBinary, e.message, cause: e));
    } on TimeoutException catch (e) {
      return Err(ytFailure(YtErrorKind.network, 'timed out', cause: e));
    } catch (e) {
      return Err(ytFailure(YtErrorKind.unknown, '$e', cause: e));
    }
    if (r.exitCode != 0) {
      return Err(
        ytFailure(classifyYtDlpStderr(r.stderr), _lastError(r.stderr)),
      );
    }
    return Ok(r);
  }

  String _lastError(String stderr) {
    final lines = stderr
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trimLeft().startsWith('ERROR:'))
        .toList();
    return lines.isEmpty ? stderr.trim() : lines.last.trim();
  }
}
