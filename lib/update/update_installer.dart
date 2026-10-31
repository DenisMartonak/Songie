import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/log.dart';
import '../data/database.dart';
import '../providers.dart';
import 'android_update_installer.dart';

/// What came of handing a verified download to the platform.
sealed class InstallOutcome {
  const InstallOutcome();
}

/// The app is about to quit, or the system install screen is open.
class Installing extends InstallOutcome {
  const Installing();
}

/// Android: "Install unknown apps" is off for Songies.
class NeedsPermission extends InstallOutcome {
  const NeedsPermission();
}

/// The file is not an update of this app (wrong signer, or not newer).
class Rejected extends InstallOutcome {
  const Rejected(this.reason);
  final String reason;
}

/// Linux: not running from an AppImage whose folder can be written.
class CannotReplace extends InstallOutcome {
  const CannotReplace();
}

class InstallFailed extends InstallOutcome {
  const InstallFailed(this.error);
  final Object error;
}

/// Installs an already-verified update file on this platform.
abstract class UpdateInstaller {
  /// False when only a manual update (the download page) is possible.
  Future<bool> canSelfUpdate();

  Future<InstallOutcome> install(File file);

  /// Android's "Install unknown apps" screen; a no-op on desktop.
  Future<void> openPermissionSettings();
}

/// Starts processes for the desktop installers; faked in tests.
abstract class UpdateProcessLauncher {
  /// Starts [exe] so it outlives this process.
  Future<void> startDetached(String exe, List<String> args);

  /// Runs [exe] to completion and returns its exit code.
  Future<int> run(String exe, List<String> args);
}

class SystemProcessLauncher implements UpdateProcessLauncher {
  const SystemProcessLauncher();

  @override
  Future<void> startDetached(String exe, List<String> args) =>
      Process.start(exe, args, mode: ProcessStartMode.detached);

  @override
  Future<int> run(String exe, List<String> args) async =>
      (await Process.run(exe, args)).exitCode;
}

/// Runs the downloaded Inno Setup installer silently, then quits so it can
/// replace the files. The installer starts Songies again when it finishes.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    required this.quit,
    this.launcher = const SystemProcessLauncher(),
  });

  final Future<Never> Function() quit;
  final UpdateProcessLauncher launcher;

  @override
  Future<bool> canSelfUpdate() async => true;

  @override
  Future<InstallOutcome> install(File file) async {
    try {
      await launcher.startDetached(file.path, const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
      ]);
    } on Object catch (e) {
      AppLog.w('update: starting the installer failed: $e');
      return InstallFailed(e);
    }
    return quit();
  }

  @override
  Future<void> openPermissionSettings() async {}
}

/// Swaps the running AppImage (named by `APPIMAGE`) for the download: the
/// copy is staged next to it as `.<name>.part`, made executable and renamed
/// over it, so the file is never half-written. Then the new one is started.
class LinuxUpdateInstaller implements UpdateInstaller {
  LinuxUpdateInstaller({
    required this.env,
    required this.quit,
    this.launcher = const SystemProcessLauncher(),
  });

  final Map<String, String> env;
  final Future<Never> Function() quit;
  final UpdateProcessLauncher launcher;

  /// The running AppImage, or null when not started from one.
  File? get _appImage {
    final path = env['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  String _partPath(File appImage) =>
      p.join(p.dirname(appImage.path), '.${p.basename(appImage.path)}.part');

  @override
  Future<bool> canSelfUpdate() async {
    final appImage = _appImage;
    if (appImage == null) return false;
    // Writability is only known by trying. The probe has its own unique
    // name, so a re-check never touches a staged copy of a running install.
    final name = p.basename(appImage.path);
    final probe = File(
      p.join(
        p.dirname(appImage.path),
        '.$name.probe-$pid-${Random().nextInt(1 << 32)}',
      ),
    );
    try {
      await probe.create(exclusive: true);
    } on FileSystemException {
      return false;
    }
    await _deleteQuietly(probe);
    return true;
  }

  @override
  Future<InstallOutcome> install(File file) async {
    final appImage = _appImage;
    if (appImage == null) return const CannotReplace();
    final part = File(_partPath(appImage));
    try {
      await file.copy(part.path);
    } on FileSystemException catch (e) {
      AppLog.w('update: cannot stage the AppImage: $e');
      await _deleteQuietly(part);
      return const CannotReplace();
    }
    try {
      final code = await launcher.run('chmod', ['755', part.path]);
      if (code != 0) throw ProcessException('chmod', [part.path], '', code);
      await part.rename(appImage.path);
    } on Object catch (e) {
      AppLog.w('update: swapping the AppImage failed: $e');
      await _deleteQuietly(part);
      return InstallFailed(e);
    }
    // The download is now a duplicate of the installed file.
    await _deleteQuietly(file);
    try {
      await launcher.startDetached(appImage.path, const []);
    } on Object catch (e) {
      // Already swapped: the next manual start runs the new version.
      AppLog.w('update: relaunching the AppImage failed: $e');
      return InstallFailed(e);
    }
    return quit();
  }

  @override
  Future<void> openPermissionSettings() async {}
}

/// Platforms with no self-update: the download page only.
class ManualUpdateInstaller implements UpdateInstaller {
  const ManualUpdateInstaller();

  @override
  Future<bool> canSelfUpdate() async => false;

  @override
  Future<InstallOutcome> install(File file) async => const CannotReplace();

  @override
  Future<void> openPermissionSettings() async {}
}

Future<void> _deleteQuietly(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } on FileSystemException {
    // Best effort.
  }
}

/// Opens the release page in the browser, for a manual update.
Future<void> openDownloadPage(Uri htmlUrl) async {
  await launchUrl(htmlUrl, mode: LaunchMode.externalApplication);
}

/// Closes the database so nothing is mid-write, then exits for the installer.
Future<Never> quitForUpdate(AppDatabase db) async {
  try {
    await db.close();
  } on Object catch (e) {
    AppLog.w('update: closing the database before the update failed: $e');
  }
  exit(0);
}

final updateInstallerProvider = Provider<UpdateInstaller>((ref) {
  Future<Never> quit() => quitForUpdate(ref.read(databaseProvider));
  if (Platform.isAndroid) return AndroidUpdateInstaller();
  if (Platform.isWindows) return WindowsUpdateInstaller(quit: quit);
  if (Platform.isLinux) {
    return LinuxUpdateInstaller(env: Platform.environment, quit: quit);
  }
  return const ManualUpdateInstaller();
});
