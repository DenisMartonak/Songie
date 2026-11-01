import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/result.dart';
import '../player/stream_source.dart';
import 'yt_json.dart';
import 'yt_models.dart';
import 'ytdlp_cookies.dart';
import '../innertube/yt_session.dart';
import 'ytdlp_runner.dart';

const ytStreamFormat = 'bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio';

/// Maps yt-dlp stderr (from a failed run) to an error kind, using only the
/// `ERROR:` lines; warnings are ignored. A full disk is recognised anywhere,
/// since it may surface only as a Python traceback.
YtErrorKind classifyYtDlpStderr(String stderr) {
  if (stderr.contains('No space left on device') ||
      stderr.contains('Errno 28')) {
    return YtErrorKind.diskFull;
  }
  final errors = stderr
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trimLeft().startsWith('ERROR:'))
      .join('\n');
  if (errors.isEmpty) return YtErrorKind.unknown;
  if (errors.contains('HTTP Error 429')) return YtErrorKind.throttled;
  // Playable with a signed-in account, so never a reason to flag the song.
  if (errors.contains('Sign in to confirm your age') ||
      errors.contains('age-restricted')) {
    return YtErrorKind.ageRestricted;
  }
  const notFound = [
    'The playlist does not exist',
    'This video is unavailable',
    'Private video',
    'removed for violating',
    // Region-blocked videos: unplayable for this user, but yt-dlp itself
    // works, so playback skips them like private videos.
    'available in your country',
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

class YtDlpClient implements StreamSource {
  /// Signed-in runs write their cookies file into [cookiesDir] (the system
  /// temp folder when null).
  YtDlpClient(this._runner, {Directory? cookiesDir, DateTime Function()? now})
    // ignore: prefer_initializing_formals
    : _cookiesDir = cookiesDir,
      _now = now ?? DateTime.now;

  final YtDlpRunner _runner;
  final Directory? _cookiesDir;
  final DateTime Function() _now;
  static final _random = Random.secure();

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

  @override
  String get name => 'yt-dlp';

  /// With [auth], the run goes out signed in (see [_run]).
  @override
  Future<Result<YtStream>> resolveStream(
    String videoId, {
    YtDlpAuth? auth,
  }) async {
    final run = await _run(
      [
        '-J',
        '--no-playlist',
        '-f',
        ytStreamFormat,
        'https://music.youtube.com/watch?v=$videoId',
      ],
      streamTimeout,
      auth: auth,
    );
    if (run is Err<YtDlpRun>) return Err(run.failure);
    try {
      return Ok(parseStreamJson((run as Ok<YtDlpRun>).value.stdout));
    } catch (e) {
      return Err(ytFailure(YtErrorKind.extractor, 'bad JSON: $e', cause: e));
    }
  }

  /// Downloads [videoId]'s audio into [outDir] as `<id>.<ext>`, resuming a
  /// partial file. [onProgress] gets byte counts (total may be an estimate,
  /// or null). If yt-dlp prints nothing for [stallTimeout], the run is
  /// cancelled and the result is a network error.
  Future<Result<YtDownload>> download(
    String videoId,
    Directory outDir, {
    required String processId,
    void Function(int downloaded, int? total)? onProgress,
    Duration stallTimeout = const Duration(minutes: 2),
    YtDlpAuth? auth,
  }) async {
    Object? done;
    int? lastDownloaded;
    var stalled = false;
    Timer? stall;
    void arm() {
      stall?.cancel();
      stall = Timer(stallTimeout, () {
        stalled = true;
        unawaited(_runner.cancel(processId));
      });
    }

    void onLine(String line) {
      arm();
      if (line.startsWith(_progressPrefix)) {
        final f = line.substring(_progressPrefix.length).split(' ');
        final downloaded = _naInt(f.elementAtOrNull(0));
        if (downloaded == null || downloaded == lastDownloaded) return;
        lastDownloaded = downloaded;
        final total =
            _naInt(f.elementAtOrNull(1)) ?? _naInt(f.elementAtOrNull(2));
        onProgress?.call(downloaded, total);
      } else if (line.startsWith(_donePrefix)) {
        done = _parseDone(line);
      }
    }

    arm();
    final Result<YtDlpRun> run;
    try {
      run = await _run(
        [
          '-f',
          ytStreamFormat,
          '--no-playlist',
          '--continue',
          '--no-mtime',
          '--newline',
          '--progress',
          '--progress-template',
          'download:$_progressPrefix%(progress.downloaded_bytes)s '
              '%(progress.total_bytes)s %(progress.total_bytes_estimate)s',
          '-o',
          p.join(outDir.path, '%(id)s.%(ext)s'),
          '--print',
          'after_move:$_donePrefix'
              '%(.{filepath,title,artist,track,album,duration})j',
          'https://music.youtube.com/watch?v=$videoId',
        ],
        null,
        onLine: onLine,
        processId: processId,
        auth: auth,
      );
    } finally {
      stall?.cancel();
    }
    if (stalled) {
      return Err(
        ytFailure(
          YtErrorKind.network,
          'no output for ${stallTimeout.inSeconds} s',
        ),
      );
    }
    if (run is Err<YtDlpRun>) return Err(run.failure);
    // Streamed lines can be lost (Android posts them apart from the reply);
    // stdout holds everything.
    if (done == null) {
      final line = (run as Ok<YtDlpRun>).value.stdout
          .split(RegExp(r'\r?\n'))
          .lastWhere((l) => l.startsWith(_donePrefix), orElse: () => '');
      if (line.isNotEmpty) done = _parseDone(line);
    }
    final d = done;
    final path = d is Map ? _naString(d['filepath']) : null;
    if (d is! Map || path == null) {
      return Err(ytFailure(YtErrorKind.unknown, 'yt-dlp reported no file'));
    }
    final file = File(path);
    if (!file.existsSync()) {
      return Err(ytFailure(YtErrorKind.unknown, 'downloaded file is missing'));
    }
    final artist = _naString(d['artist']);
    final cleaned = artist == null ? null : cleanArtist(artist);
    final duration = d['duration'];
    return Ok(
      YtDownload(
        path: path,
        bytes: file.lengthSync(),
        title: _naString(d['track']) ?? _naString(d['title']),
        artist: cleaned == null || cleaned.isEmpty ? null : cleaned,
        album: _naString(d['album']),
        durationMs: duration is num ? (duration * 1000).round() : null,
      ),
    );
  }

  /// Stops the [download] started with [processId], if it is still running.
  Future<void> cancel(String processId) => _runner.cancel(processId);

  /// The JSON of a `songies-done` line, or null when it does not parse.
  static Object? _parseDone(String line) {
    try {
      return jsonDecode(line.substring(_donePrefix.length));
    } on FormatException {
      return null;
    }
  }

  static const _progressPrefix = 'songies-progress ';
  static const _donePrefix = 'songies-done ';

  /// A yt-dlp template number, where `NA` means unknown.
  static int? _naInt(String? s) =>
      s == null ? null : num.tryParse(s.trim())?.round();

  /// A non-empty string value other than yt-dlp's `NA`.
  static String? _naString(Object? v) =>
      v is String && v.trim().isNotEmpty && v != 'NA' ? v : null;

  /// Runs yt-dlp; Ok only for exit code 0 (stderr is ignored then).
  ///
  /// With [auth] the session's cookies go in a file only this user can read,
  /// deleted when the run ends, and the runtime args are added. An age error
  /// then means the account itself was refused (`ageRestrictedAccount`), and
  /// cookie values are scrubbed from the failure.
  Future<Result<YtDlpRun>> _run(
    List<String> args,
    Duration? timeout, {
    void Function(String line)? onLine,
    String? processId,
    YtDlpAuth? auth,
  }) async {
    if (auth == null) {
      return _runPlain(args, timeout, onLine: onLine, processId: processId);
    }
    final String text;
    try {
      text = netscapeCookies(auth.session, _now());
    } on FormatException {
      return Err(
        ytFailure(YtErrorKind.ageRestrictedAccount, 'invalid session cookie'),
      );
    }
    final file = await _writeCookies(text);
    final Result<YtDlpRun> r;
    try {
      r = await _runPlain(
        ['--cookies', file.path, ...auth.runtimeArgs, ...args],
        timeout,
        onLine: onLine,
        processId: processId,
      );
    } finally {
      try {
        await file.delete();
      } catch (e) {
        AppLog.w('Could not delete a yt-dlp cookies file: $e');
      }
    }
    if (r is! Err<YtDlpRun>) return r;
    final f = r.failure;
    var kind = ytErrorKindOf(f) ?? YtErrorKind.unknown;
    if (kind == YtErrorKind.ageRestricted) {
      kind = YtErrorKind.ageRestrictedAccount;
    }
    final detail = f.message.substring(f.message.indexOf(':', 6) + 1);
    return Err(ytFailure(kind, _scrub(detail, auth.session)));
  }

  /// A new cookies file holding [text], readable only by this user.
  Future<File> _writeCookies(String text) async {
    final dir = _cookiesDir ?? Directory.systemTemp;
    await dir.create(recursive: true);
    final name = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File(p.join(dir.path, 'cookies-$name.txt'));
    await file.writeAsString('');
    if (!Platform.isWindows && !Platform.isAndroid) {
      await Process.run('chmod', ['600', file.path]);
    }
    await file.writeAsString(text, flush: true);
    return file;
  }

  static String _scrub(String text, YtSession session) {
    var out = text;
    for (final v in session.cookies.values) {
      // Short values (flags like "1") would mangle ordinary text.
      if (v.length >= 4) out = out.replaceAll(v, '<redacted>');
    }
    return out;
  }

  Future<Result<YtDlpRun>> _runPlain(
    List<String> args,
    Duration? timeout, {
    void Function(String line)? onLine,
    String? processId,
  }) async {
    final YtDlpRun r;
    try {
      r = await _runner.run(
        args,
        timeout: timeout,
        onLine: onLine,
        processId: processId,
      );
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
