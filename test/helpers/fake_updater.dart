import 'dart:async';
import 'dart:io';

import 'package:songies/update/release.dart';
import 'package:songies/update/update_checker.dart';
import 'package:songies/update/update_downloader.dart';
import 'package:songies/update/update_installer.dart' as inst;

/// Release 1.1.0 with a Linux AppImage and its checksums.
final testRelease = Release(
  version: const AppVersion(1, 1, 0),
  notes: 'Faster search and a new theme.',
  htmlUrl: Uri.parse('https://github.com/DenisMartonak/Songie/releases/v1.1.0'),
  assets: [
    ReleaseAsset(
      name: 'songies-1.1.0-x86_64.AppImage',
      url: Uri.parse('https://example.invalid/songies-1.1.0-x86_64.AppImage'),
      size: 10,
    ),
    ReleaseAsset(
      name: 'SHA256SUMS',
      url: Uri.parse('https://example.invalid/SHA256SUMS'),
      size: 100,
    ),
  ],
);

Release releaseWithNotes(String notes) => Release(
  version: testRelease.version,
  notes: notes,
  htmlUrl: testRelease.htmlUrl,
  assets: testRelease.assets,
);

UpdateAvailable availableFor(Release r) => UpdateAvailable(r, r.assets.first);

/// An [UpdateChecker] whose answers the test scripts. Never touches the
/// network or the settings table.
class FakeUpdateChecker implements UpdateChecker {
  Future<UpdateCheck?> Function() onStartup = () async => null;
  Future<UpdateCheck> Function() onNow = () async => const UpToDate();

  int startupCalls = 0;
  int nowCalls = 0;
  final List<AppVersion> skipped = [];

  @override
  Future<UpdateCheck?> checkAtStartup() {
    startupCalls++;
    return onStartup();
  }

  @override
  Future<UpdateCheck> checkNow() {
    nowCalls++;
    return onNow();
  }

  @override
  Future<void> skip(AppVersion v) async => skipped.add(v);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [UpdateDownloader] that plays back a scripted stream.
class FakeUpdateDownloader implements UpdateDownloader {
  /// By default: half way, then done with [file].
  Stream<DownloadProgress> Function(UpdateCancel? cancel)? onDownload;

  File file = File('/nonexistent/songies-1.1.0-x86_64.AppImage');
  int calls = 0;
  UpdateCancel? lastCancel;

  @override
  Stream<DownloadProgress> download(
    Release r,
    ReleaseAsset a, {
    UpdateCancel? cancel,
  }) {
    calls++;
    lastCancel = cancel;
    return onDownload?.call(cancel) ??
        Stream.fromIterable([
          const DownloadProgress(5, 10),
          DownloadDone(file, 10),
        ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [inst.UpdateInstaller] that records what it was asked to do.
class FakeUpdateInstaller implements inst.UpdateInstaller {
  bool selfUpdate = true;

  /// What [install] answers; a never-completing future stands in for a
  /// desktop install that quits the app.
  Future<inst.InstallOutcome> Function() onInstall = () async =>
      const inst.Installing();

  final List<File> installs = [];
  int permissionOpens = 0;

  @override
  Future<bool> canSelfUpdate() async => selfUpdate;

  @override
  Future<inst.InstallOutcome> install(File file) {
    installs.add(file);
    return onInstall();
  }

  @override
  Future<void> openPermissionSettings() async => permissionOpens++;
}
