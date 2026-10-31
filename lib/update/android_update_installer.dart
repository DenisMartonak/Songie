import 'dart:io';

import 'package:flutter/services.dart';

import '../core/log.dart';
import 'update_installer.dart';

/// Hands a verified APK to Android's install screen through `songies/updater`
/// (`UpdaterPlugin.kt`). It fails closed: the APK is installed only when the
/// native side confirms the same signer and a higher versionCode.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('songies/updater');

  final MethodChannel _channel;

  @override
  Future<bool> canSelfUpdate() async => true;

  @override
  Future<InstallOutcome> install(File file) async {
    final args = {'path': file.path};
    final Map<String, Object?>? info;
    try {
      info = await _channel.invokeMapMethod<String, Object?>('inspect', args);
    } on Object catch (e) {
      AppLog.w('update: inspecting the APK failed: $e');
      return InstallFailed(e);
    }
    final sameSigner = info?['sameSigner'];
    final versionCode = info?['versionCode'];
    final installed = info?['installedVersionCode'];
    if (sameSigner is! bool || versionCode is! int || installed is! int) {
      return _reject(file, 'the update could not be read');
    }
    if (!sameSigner) {
      return _reject(file, 'the update is not signed with Songies\' key');
    }
    if (versionCode <= installed) {
      return _reject(file, 'the update is not newer than this version');
    }
    try {
      final allowed = await _channel.invokeMethod<bool>('canInstall');
      if (allowed != true) return const NeedsPermission();
      await _channel.invokeMethod<void>('install', args);
    } on Object catch (e) {
      AppLog.w('update: opening the installer failed: $e');
      return InstallFailed(e);
    }
    return const Installing();
  }

  @override
  Future<void> openPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  /// A file that fails a check is deleted, so it can never be installed.
  Future<InstallOutcome> _reject(File file, String reason) async {
    AppLog.w('update: rejected ${file.path}: $reason');
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort; it is still never installed.
    }
    return Rejected(reason);
  }
}
