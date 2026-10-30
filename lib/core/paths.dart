import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Locations under `<appData>`.
class AppPaths {
  AppPaths._(this.root)
    : art = Directory(p.join(root.path, 'art')),
      libraryLocal = Directory(p.join(root.path, 'library', 'local')),
      libraryYt = Directory(p.join(root.path, 'library', 'yt')),
      fonts = Directory(p.join(root.path, 'fonts')),
      bin = Directory(p.join(root.path, 'bin')),
      logs = Directory(p.join(root.path, 'logs')),
      sync = Directory(p.join(root.path, 'sync')),
      db = File(p.join(root.path, 'songies.db'));

  final Directory root;
  final Directory art;
  final Directory libraryLocal;
  final Directory libraryYt;
  final Directory fonts;
  final Directory bin;
  final Directory logs;
  final Directory sync;
  final File db;

  /// Paths rooted at an explicit directory (tests).
  static AppPaths at(Directory root) => AppPaths._(root);

  /// Android: app-specific external dir; Windows: `%APPDATA%\Songies`;
  /// Linux: `$XDG_DATA_HOME/songies` or `~/.local/share/songies`.
  static Future<AppPaths> resolve() async {
    final Directory root;
    if (Platform.isAndroid) {
      root =
          await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      root = (appData != null && appData.isNotEmpty)
          ? Directory(p.join(appData, 'Songies'))
          : await getApplicationSupportDirectory();
    } else if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        root = Directory(p.join(xdg, 'songies'));
      } else if (home != null && home.isNotEmpty) {
        root = Directory(p.join(home, '.local', 'share', 'songies'));
      } else {
        root = await getApplicationSupportDirectory();
      }
    } else {
      root = await getApplicationSupportDirectory();
    }
    return AppPaths._(root);
  }

  Future<void> ensureCreated() async {
    for (final d in [
      root,
      art,
      libraryLocal,
      libraryYt,
      fonts,
      bin,
      logs,
      sync,
    ]) {
      await d.create(recursive: true);
    }
  }
}
