import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/result.dart';

const ytDlpReleaseBase =
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download/';

/// Runs an executable to completion (used for `chmod` and `--version`).
typedef ProcessRunFn = Future<ProcessResult> Function(
  String executable,
  List<String> args,
);

Future<ProcessResult> _defaultRunProcess(String exe, List<String> args) =>
    Process.run(
      exe,
      args,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

/// Real download function: GET with redirects (GitHub release assets redirect).
///
/// A stalled connection fails with a [TimeoutException] instead of hanging:
/// [connectionTimeout] bounds the connect and [stallTimeout] any wait for the
/// response headers or the next body chunk, so a slow link still succeeds as
/// long as bytes keep arriving. [totalTimeout], when given, bounds the whole
/// download. [onProgress] gets the bytes received so far and the
/// Content-Length (null when the server sends none).
Future<List<int>> httpDownload(
  Uri uri, {
  Duration connectionTimeout = const Duration(seconds: 30),
  Duration stallTimeout = const Duration(seconds: 60),
  Duration? totalTimeout,
  void Function(int received, int? total)? onProgress,
}) async {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  Future<List<int>> body() async {
    final req = await client.getUrl(uri);
    req.followRedirects = true;
    req.maxRedirects = 10;
    final res = await req.close().timeout(stallTimeout);
    if (res.statusCode != 200) {
      await res.drain<void>().timeout(stallTimeout);
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final b = BytesBuilder(copy: false);
    final total = res.contentLength < 0 ? null : res.contentLength;
    await for (final chunk in res.timeout(stallTimeout)) {
      b.add(chunk);
      onProgress?.call(b.length, total);
    }
    return b.takeBytes();
  }

  try {
    final done = body();
    return await (totalTimeout == null ? done : done.timeout(totalTimeout));
  } finally {
    // force: a timed-out request must not keep its socket open.
    client.close(force: true);
  }
}

class YtDlpInstaller {
  YtDlpInstaller(
    this.binDir, {
    required this.download,
    required this.isWindows,
    ProcessRunFn? runProcess,
    this.versionTimeout = const Duration(seconds: 30),
  }) : _run = runProcess ?? _defaultRunProcess;

  /// Limit for the post-install `--version` check of the downloaded binary.
  final Duration versionTimeout;

  final Directory binDir;
  final Future<List<int>> Function(Uri) download;
  final bool isWindows;
  final ProcessRunFn _run;

  String get _asset => isWindows ? 'yt-dlp.exe' : 'yt-dlp_linux';
  File get binary =>
      File(p.join(binDir.path, isWindows ? 'yt-dlp.exe' : 'yt-dlp'));

  static const _verifyMsg = 'yt-dlp download failed verification';

  /// Downloads, verifies and installs the latest release. Returns the new
  /// version string. On any failure the existing binary is left untouched.
  Future<Result<String>> installOrUpdate() async {
    final tmp = File('${binary.path}.download');
    try {
      final List<int> sums;
      final List<int> data;
      try {
        sums = await download(Uri.parse('${ytDlpReleaseBase}SHA2-256SUMS'));
        data = await download(Uri.parse('$ytDlpReleaseBase$_asset'));
      } on Object catch (e) {
        return Err(
          Failure(FailureKind.network, 'Could not download yt-dlp', cause: e),
        );
      }

      final expected = _expectedHash(utf8.decode(sums, allowMalformed: true));
      if (expected == null ||
          sha256.convert(data).toString().toLowerCase() != expected) {
        return const Err(Failure(FailureKind.io, _verifyMsg));
      }

      await binDir.create(recursive: true);
      await tmp.writeAsBytes(data, flush: true);
      if (!isWindows) {
        final c = await _run('chmod', ['+x', tmp.path]);
        if (c.exitCode != 0) {
          await _cleanup(tmp);
          return Err(
            Failure(FailureKind.io, 'Could not make yt-dlp executable'),
          );
        }
      }
      ProcessResult? v;
      try {
        v = await _run(tmp.path, ['--version']).timeout(versionTimeout);
      } on TimeoutException {
        v = null;
      }
      final version = '${v?.stdout ?? ''}'.trim();
      if (v == null || v.exitCode != 0 || version.isEmpty) {
        await _cleanup(tmp);
        return const Err(
          Failure(FailureKind.io, 'Installed yt-dlp does not run'),
        );
      }
      await tmp.rename(binary.path);
      return Ok(version);
    } on FileSystemException catch (e) {
      await _cleanup(tmp);
      return Err(Failure(FailureKind.io, 'Could not install yt-dlp', cause: e));
    } on Object catch (e) {
      await _cleanup(tmp);
      return Err(
        Failure(FailureKind.unknown, 'Could not install yt-dlp', cause: e),
      );
    }
  }

  String? _expectedHash(String sums) {
    for (final line in const LineSplitter().convert(sums)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts.last.replaceFirst(RegExp(r'^\*'), '');
      if (name == _asset) return parts.first.toLowerCase();
    }
    return null;
  }

  Future<void> _cleanup(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on Object {
      // best effort
    }
  }
}
