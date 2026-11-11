import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity.dart';
import '../core/log.dart';
import '../data/settings_repository.dart';
import '../providers.dart';
import 'release.dart';
import 'update_checker.dart';
import 'update_downloader.dart';
import 'update_installer.dart' as inst;

/// Where the in-app update stands; what the update dialog shows.
sealed class UpdateState {
  const UpdateState();
}

/// Nothing to show (also after a silent startup check).
class Idle extends UpdateState {
  const Idle();
}

/// A check started from Settings is running.
class Checking extends UpdateState {
  const Checking();
}

class Available extends UpdateState {
  const Available(this.release, this.asset);
  final Release release;
  final ReleaseAsset asset;
}

class NoUpdate extends UpdateState {
  const NoUpdate();
}

/// A check from Settings failed (offline, timeout, bad answer).
class CheckError extends UpdateState {
  const CheckError();
}

class Downloading extends UpdateState {
  const Downloading(this.received, this.total);
  final int received;

  /// 0 when unknown.
  final int total;
}

/// Android, Wi-Fi only on and on mobile data: the user may download anyway.
class WaitingForWifi extends UpdateState {
  const WaitingForWifi();
}

/// Downloaded and verified; waits for the user to tap Install now.
class ReadyToInstall extends UpdateState {
  const ReadyToInstall(this.file);
  final File file;
}

/// The installer has taken over (desktop: the app is quitting; Android: the
/// system install screen is open).
class Installing extends UpdateState {
  const Installing();
}

/// Android: "Install unknown apps" is off for Songies.
class NeedsPermission extends UpdateState {
  const NeedsPermission();
}

class Failed extends UpdateState {
  const Failed(this.message);

  /// Plain words for the user; never an exception's text.
  final String message;
}

/// Only a manual update (the release page) is possible.
class ManualOnly extends UpdateState {
  const ManualOnly(this.htmlUrl);
  final Uri htmlUrl;
}

/// How long a check may take before it counts as failed: a guard on top of
/// the fetch's own 10 s timeouts.
final updateCheckTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 15),
);

/// Opens the release page in the browser; replaced in tests.
final openDownloadPageProvider = Provider<Future<void> Function(Uri)>(
  (_) => inst.openDownloadPage,
);

const _downloadFailedCopy =
    "Couldn't download the update. Check your connection.";
const _notVerifiedCopy =
    "The download didn't pass its check, so nothing was installed.";
const _rejectedCopy =
    "The download isn't an update of this Songies, so nothing was installed.";
const _installFailedCopy = "Couldn't install the update.";

/// Runs the update flow: check, prompt, download, install. Nothing here
/// throws to the caller.
class UpdateController extends Notifier<UpdateState> {
  /// The release the current prompt is about.
  Release? release;
  ReleaseAsset? _asset;
  File? _file;
  UpdateCancel? _cancel;
  bool _installRunning = false;

  /// Bumped by every check, so a slow startup answer can't override a newer
  /// manual one.
  int _generation = 0;

  @override
  UpdateState build() {
    ref.onDispose(() => _cancel?.cancel());
    return const Idle();
  }

  /// The once-per-run check: silent unless an update is available. Gives up
  /// after [updateCheckTimeoutProvider]; does nothing on platforms without
  /// updates.
  Future<void> startup() async {
    try {
      final checker = ref.read(updateCheckerProvider);
      if (checker == null || state is! Idle) return;
      final gen = ++_generation;
      final result = await _within<UpdateCheck?>(
        checker.checkAtStartup(),
        ref.read(updateCheckTimeoutProvider),
        null,
      );
      if (gen != _generation || state is! Idle) return;
      if (result is UpdateAvailable) await _offer(result, gen);
    } on Object catch (e) {
      AppLog.w('update: startup check failed: $e');
    }
  }

  /// The Settings button: ignores the throttle and the skip.
  Future<void> checkNow() async {
    if (state is Downloading || state is ReadyToInstall) return;
    final checker = ref.read(updateCheckerProvider);
    if (checker == null) {
      state = const NoUpdate();
      return;
    }
    final gen = ++_generation;
    state = const Checking();
    UpdateCheck result;
    try {
      result = await _within<UpdateCheck>(
        checker.checkNow(),
        ref.read(updateCheckTimeoutProvider),
        CheckFailed(TimeoutException('update check')),
      );
    } on Object catch (e) {
      result = CheckFailed(e);
    }
    if (gen != _generation) return;
    switch (result) {
      case UpdateAvailable():
        await _offer(result, gen);
      case UpToDate():
        state = const NoUpdate();
      case CheckFailed(:final error):
        AppLog.w('update: check failed: $error');
        state = const CheckError();
    }
  }

  Future<void> _offer(UpdateAvailable a, int gen) async {
    var self = false;
    try {
      self = await ref.read(inst.updateInstallerProvider).canSelfUpdate();
    } on Object catch (e) {
      AppLog.w('update: cannot tell whether self-update works: $e');
    }
    if (gen != _generation) return;
    release = a.release;
    _asset = a.asset;
    state = self
        ? Available(a.release, a.asset)
        : ManualOnly(a.release.htmlUrl);
  }

  /// Update now: downloads (on Android, only on Wi-Fi when Wi-Fi only is
  /// on), then waits in [ReadyToInstall] for [installNow].
  Future<void> accept() async {
    if (state is! Available && state is! Failed) return;
    if (await _mustWaitForWifi()) {
      state = const WaitingForWifi();
      return;
    }
    await _download();
  }

  /// Download anyway, on mobile data.
  Future<void> downloadAnyway() => _download();

  Future<bool> _mustWaitForWifi() async {
    final isAndroid = ref.read(isAndroidProvider);
    if (!isAndroid) return false;
    try {
      final wifiOnly = await ref
          .read(settingsRepositoryProvider)
          .getBool(kWifiOnly, fallback: wifiOnlyDefault(isAndroid: isAndroid));
      if (!wifiOnly) return false;
      return await ref.read(networkStatusProvider).current() ==
          NetworkKind.mobile;
    } on Object catch (e) {
      // Fail closed: ask, as if on mobile data with Wi-Fi only on.
      AppLog.w('update: cannot read the network: $e');
      return true;
    }
  }

  Future<void> _download() async {
    final r = release;
    final a = _asset;
    if (r == null || a == null || state is Downloading) return;
    final cancel = _cancel = UpdateCancel();
    _file = null;
    state = Downloading(0, a.size);
    UpdateState end = const Failed(_downloadFailedCopy);
    try {
      await for (final p
          in ref
              .read(updateDownloaderProvider)
              .download(r, a, cancel: cancel)) {
        if (cancel.isCancelled) break;
        switch (p) {
          case DownloadDone(:final file):
            _file = file;
            end = ReadyToInstall(file);
          case DownloadFailed(:final kind):
            AppLog.w('update: download failed: ${kind.name}');
            end = switch (kind) {
              DownloadError.checksumMismatch ||
              DownloadError.noChecksum => const Failed(_notVerifiedCopy),
              _ => const Failed(_downloadFailedCopy),
            };
          default:
            state = Downloading(p.received, p.total);
        }
      }
    } on Object catch (e) {
      AppLog.w('update: download failed: $e');
    }
    if (identical(_cancel, cancel)) _cancel = null;
    // A cancel already put the prompt back.
    if (!cancel.isCancelled) state = end;
  }

  /// Stops a running download; the prompt goes back to [Available].
  void cancel() {
    final c = _cancel;
    if (c == null || state is! Downloading) return;
    c.cancel();
    final r = release;
    final a = _asset;
    state = r != null && a != null ? Available(r, a) : const Idle();
  }

  /// Install now: hands the verified file to the platform installer. On
  /// Android it also works from [Installing], since the user may have backed
  /// out of the system install screen.
  Future<void> installNow() async {
    final file = _file;
    if (file == null || _installRunning) return;
    final retry = state is Installing && ref.read(isAndroidProvider);
    if (state is! ReadyToInstall && state is! NeedsPermission && !retry) {
      return;
    }
    // Desktop installers quit the app and never return.
    state = const Installing();
    inst.InstallOutcome outcome;
    _installRunning = true;
    try {
      outcome = await ref.read(inst.updateInstallerProvider).install(file);
    } on Object catch (e) {
      outcome = inst.InstallFailed(e);
    } finally {
      _installRunning = false;
    }
    switch (outcome) {
      case inst.Installing():
        state = const Installing();
      case inst.NeedsPermission():
        state = const NeedsPermission();
      case inst.Rejected(:final reason):
        AppLog.w('update: install rejected: $reason');
        _file = null;
        state = const Failed(_rejectedCopy);
      case inst.InstallFailed(:final error):
        AppLog.w('update: install failed: $error');
        state = const Failed(_installFailedCopy);
      case inst.CannotReplace():
        state = ManualOnly(release?.htmlUrl ?? Uri());
    }
  }

  /// Android's "Install unknown apps" screen.
  Future<void> openPermissionSettings() async {
    try {
      await ref.read(inst.updateInstallerProvider).openPermissionSettings();
    } on Object catch (e) {
      AppLog.w('update: opening the permission screen failed: $e');
    }
  }

  /// Opens the release page, for a manual update.
  Future<void> openDownloadPage() async {
    final url = switch (state) {
      ManualOnly(:final htmlUrl) => htmlUrl,
      _ => release?.htmlUrl,
    };
    // A release without a usable https page link opens nothing.
    if (url == null || url.scheme != 'https') return;
    try {
      await ref.read(openDownloadPageProvider)(url);
    } on Object catch (e) {
      AppLog.w('update: opening the download page failed: $e');
    }
  }

  /// Not now: the startup check stays quiet about this version.
  void notNow() {
    final r = release;
    if (r != null) {
      final checker = ref.read(updateCheckerProvider);
      unawaited(
        checker?.skip(r.version).catchError((Object e) {
          AppLog.w('update: saving the skipped version failed: $e');
        }),
      );
      // The Android notification stays quiet about it too.
      unawaited(ref.read(updateNotificationsProvider)?.skip(r.version));
    }
    state = const Idle();
  }
}

/// [future]'s value, or [fallback] once [limit] has passed. Unlike
/// `Future.timeout`, safe when [future]'s runtime type is narrower than [T],
/// and it leaves no timer behind.
Future<T> _within<T>(Future<T> future, Duration limit, T fallback) {
  final done = Completer<T>();
  final timer = Timer(limit, () {
    if (!done.isCompleted) done.complete(fallback);
  });
  future.then(
    (v) {
      timer.cancel();
      if (!done.isCompleted) done.complete(v);
    },
    onError: (Object e, StackTrace s) {
      timer.cancel();
      if (!done.isCompleted) done.completeError(e, s);
    },
  );
  return done.future;
}
