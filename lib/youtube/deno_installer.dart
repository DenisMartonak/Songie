import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/result.dart';
import 'ytdlp_installer.dart';

const denoReleaseBase =
    'https://github.com/denoland/deno/releases/latest/download/';

/// Downloads with progress; the same shape as [httpDownload].
typedef ProgressDownload = Future<List<int>> Function(
  Uri uri, {
  void Function(int received, int? total)? onProgress,
});

/// Installs Deno into Songies' `bin` folder, as the JavaScript runtime yt-dlp
/// needs for age-restricted songs (desktop only). Like [YtDlpInstaller]: the
/// zip is checked against its published SHA-256 before anything is written,
/// and a failure leaves nothing behind.
class DenoInstaller {
  DenoInstaller(
    this.binDir, {
    required this._download,
    required this.isWindows,
    ProcessRunFn? runProcess,
    this.versionTimeout = const Duration(seconds: 30),
  }) : _run = runProcess ?? _defaultRun;

  final Directory binDir;
  final bool isWindows;
  final Duration versionTimeout;
  final ProgressDownload _download;
  final ProcessRunFn _run;

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8);

  String get _asset => isWindows
      ? 'deno-x86_64-pc-windows-msvc.zip'
      : 'deno-x86_64-unknown-linux-gnu.zip';

  String get _exe => isWindows ? 'deno.exe' : 'deno';

  /// Where Deno is installed; the same path `JsRuntimeFinder.songiesDeno`
  /// looks at.
  File get binary => File(p.join(binDir.path, _exe));

  static const _verifyMsg = 'Deno download failed verification';

  /// Downloads, verifies and installs the latest Deno. Returns its version
  /// line (`deno 2.x.y (stable)`).
  Future<Result<String>> install({
    void Function(int received, int? total)? onProgress,
  }) async {
    final tmp = File('${binary.path}.download');
    try {
      final List<int> sums;
      final List<int> zip;
      try {
        sums = await _download(Uri.parse('$denoReleaseBase$_asset.sha256sum'));
        zip = await _download(
          Uri.parse('$denoReleaseBase$_asset'),
          onProgress: onProgress,
        );
      } on Object catch (e) {
        return Err(
          Failure(FailureKind.network, 'Could not download Deno', cause: e),
        );
      }
      final expected = _expectedHash(utf8.decode(sums, allowMalformed: true));
      if (expected == null || sha256.convert(zip).toString() != expected) {
        return const Err(Failure(FailureKind.io, _verifyMsg));
      }
      final entry = ZipDecoder()
          .decodeBytes(zip)
          .files
          .where((f) => f.isFile && p.basename(f.name) == _exe)
          .firstOrNull;
      if (entry == null) return const Err(Failure(FailureKind.io, _verifyMsg));
      await binDir.create(recursive: true);
      await tmp.writeAsBytes(entry.content, flush: true);
      if (!isWindows) {
        final c = await _run('chmod', ['+x', tmp.path]);
        if (c.exitCode != 0) {
          await _cleanup(tmp);
          return const Err(
            Failure(FailureKind.io, 'Could not make Deno executable'),
          );
        }
      }
      ProcessResult? v;
      try {
        v = await _run(tmp.path, ['--version']).timeout(versionTimeout);
      } on TimeoutException {
        v = null;
      }
      final version = '${v?.stdout ?? ''}'.trim().split('\n').first.trim();
      if (v == null || v.exitCode != 0 || version.isEmpty) {
        await _cleanup(tmp);
        return const Err(
          Failure(FailureKind.io, 'Installed Deno does not run'),
        );
      }
      await tmp.rename(binary.path);
      return Ok(version);
    } on Object catch (e) {
      await _cleanup(tmp);
      return Err(Failure(FailureKind.io, 'Could not install Deno', cause: e));
    }
  }

  /// Deletes the installed Deno, if any.
  Future<void> remove() => _cleanup(binary);

  /// The first SHA-256 in [sums]: Linux's `<hex>  <file>` line and the
  /// Windows build's PowerShell `Get-FileHash` table both carry one.
  static String? _expectedHash(String sums) =>
      RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(sums)?.group(0)?.toLowerCase();

  Future<void> _cleanup(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on Object {
      // best effort
    }
  }
}
