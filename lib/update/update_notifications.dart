import 'dart:async';

import 'package:flutter/services.dart';

import '../core/log.dart';
import '../data/settings_repository.dart';
import '../downloads/android_download_notifier.dart'
    show ensureNotificationPermission;
import 'release.dart';

/// The Android update notification (SON-28). A background job
/// (UpdateCheckWorker.kt) checks GitHub about every 6 hours, even with
/// Songies closed, and shows "Songies X is available" once per version.
/// This is the app's side of it.
abstract class UpdateNotifications {
  /// Keeps the background check quiet about [v] (the prompt's "Not now").
  Future<void> skip(AppVersion v);

  /// Whether Songies was just opened by tapping the notification; asking
  /// clears it.
  Future<bool> takeOpenRequest();

  /// A tap on the notification while Songies is already running.
  Stream<void> get openRequests;

  /// Asks for Android 13's notification permission, once ever.
  Future<void> askPermissionOnce();
}

class ChannelUpdateNotifications implements UpdateNotifications {
  ChannelUpdateNotifications({
    required this._settings,
    Future<void> Function()? askPermission,
    this._channel = const MethodChannel('songies/update_notifier'),
  }) : _askPermission = askPermission ?? ensureNotificationPermission {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openUpdate') _opens.add(null);
    });
  }

  final SettingsRepository _settings;
  final Future<void> Function() _askPermission;
  final MethodChannel _channel;
  final _opens = StreamController<void>.broadcast();

  @override
  Future<void> skip(AppVersion v) async {
    try {
      await _channel.invokeMethod<void>('skip', {'version': v.toString()});
    } catch (e) {
      AppLog.w('update notification: skip failed: $e');
    }
  }

  @override
  Future<bool> takeOpenRequest() async {
    try {
      return await _channel.invokeMethod<bool>('takeOpenRequest') ?? false;
    } catch (e) {
      AppLog.w('update notification: open request failed: $e');
      return false;
    }
  }

  @override
  Stream<void> get openRequests => _opens.stream;

  @override
  Future<void> askPermissionOnce() async {
    try {
      if (await _settings.getBool(kUpdateNotifyAsked, fallback: false)) return;
      await _settings.setBool(kUpdateNotifyAsked, true);
      await _askPermission();
    } catch (e) {
      AppLog.w('update notification: permission request failed: $e');
    }
  }
}
