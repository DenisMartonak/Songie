import 'dart:io';

import 'package:path/path.dart' as p;

/// Where yt-dlp's JavaScript runtime comes from.
enum JsRuntimeKind {
  /// The Deno Songies installed in its own `bin` folder.
  songiesDeno,

  /// `deno` on PATH.
  systemDeno,

  /// `node` on PATH.
  systemNode,

  /// youtubedl-android's QuickJS, which it passes to yt-dlp by itself.
  bundled,
}

/// A runtime yt-dlp can solve YouTube's JavaScript challenge with, and the
/// arguments that point yt-dlp at it.
class JsRuntime {
  const JsRuntime(this.kind, this.args);

  final JsRuntimeKind kind;
  final List<String> args;
}

/// Finds a [JsRuntime]: Songies' own Deno first, then `deno` and `node` on
/// PATH. On Android the bundled QuickJS is always there.
class JsRuntimeFinder {
  JsRuntimeFinder({
    required this.binDir,
    required this.isAndroid,
    required this.isWindows,
    Map<String, String>? environment,
    bool Function(String path)? exists,
  }) : _environment = environment ?? Platform.environment,
       _exists = exists ?? ((path) => File(path).existsSync());

  final Directory binDir;
  final bool isAndroid;
  final bool isWindows;
  final Map<String, String> _environment;
  final bool Function(String path) _exists;

  p.Context get _path => isWindows ? p.windows : p.posix;

  String _exe(String name) => isWindows ? '$name.exe' : name;

  /// Where Songies installs Deno.
  File get songiesDeno => File(_path.join(binDir.path, _exe('deno')));

  Future<JsRuntime?> find() async {
    if (isAndroid) return const JsRuntime(JsRuntimeKind.bundled, []);
    final own = songiesDeno.path;
    if (_exists(own)) {
      return JsRuntime(JsRuntimeKind.songiesDeno, [
        '--js-runtimes',
        'deno:$own',
      ]);
    }
    if (_onPath('deno')) {
      return const JsRuntime(JsRuntimeKind.systemDeno, [
        '--js-runtimes',
        'deno',
      ]);
    }
    if (_onPath('node')) {
      return const JsRuntime(JsRuntimeKind.systemNode, [
        '--js-runtimes',
        'node',
      ]);
    }
    return null;
  }

  bool _onPath(String name) {
    // Windows keeps it as `Path`; the key's case varies.
    final path = _environment.entries
        .where((e) => e.key.toUpperCase() == 'PATH')
        .map((e) => e.value)
        .firstOrNull;
    if (path == null) return false;
    return path
        .split(isWindows ? ';' : ':')
        .where((d) => d.isNotEmpty)
        .any((d) => _exists(_path.join(d, _exe(name))));
  }
}
