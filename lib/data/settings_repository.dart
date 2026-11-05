import 'dart:io';

import 'package:drift/drift.dart';

import 'database.dart';

/// Wi-Fi only *downloads* (the key predates the streaming switch).
const kWifiOnly = 'wifi_only';

/// Wi-Fi only streaming: refuse to stream on mobile data. Device-local,
/// off by default on every platform.
const kWifiOnlyStreaming = 'wifi_only_streaming';

/// When the update check last ran, in milliseconds since the epoch.
const kUpdateLastCheckMs = 'update_last_check_ms';

/// The version the user chose "Not now" for.
const kUpdateSkippedVersion = 'update_skipped_version';
const kYtdlpUseSystem = 'ytdlp_use_system';
const kReduceMotion = 'reduce_motion';

/// YouTube's anonymous visitor id (`visitorData`), sent on every Innertube
/// request. Device-local: never synced, never tied to an account.
const kYtVisitorData = 'yt_visitor_data';

/// Set once the user accepts YouTube's terms (the EU consent sheet); from
/// then on Innertube requests carry the `SOCS=CAI` cookie. Device-local.
const kYtConsentGiven = 'yt_consent_given';

/// This device's name as shown to paired devices. Device-local; unset means
/// the default (hostname on desktop, `Android` on Android).
const kDeviceName = 'device_name';

/// Cached display name of the signed-in YouTube account. Device-local, not
/// secret; removed on sign out.
const kYtAccountName = 'yt_account_name';

/// Non-secret marker: a YouTube session is stored. Lets startup skip the
/// keyring entirely. Device-local.
const kYtSignedIn = 'yt_signed_in';

/// The equalizer preset (an `EqPreset` name). Device-local, Off by default.
const kEqPreset = 'eq_preset';

/// Show the playing song on Discord (desktop only). Device-local, off by
/// default.
const kDiscordPresence = 'discord_presence';

/// Send anonymous crash reports (release builds only). Device-local, on by
/// default.
const kCrashReports = 'crash_reports';

/// A random id sent with crash reports so Sentry can count the devices a
/// problem hits. Device-local; never the sync device identity.
const kCrashInstallId = 'crash_install_id';

/// Set once YouTube songs flagged unavailable before age-restricted songs had
/// their own error were unflagged for one more check. Device-local.
const kUnavailableRecheckDone = 'unavailable_recheck_done';

/// Default of the Wi-Fi only downloads setting: on for Android (metered data), off on
/// desktop. [isAndroid] exists so tests don't depend on the host.
bool wifiOnlyDefault({bool? isAndroid}) => isAndroid ?? Platform.isAndroid;

/// Typed access to the device-local `Settings` table (not synced).
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$SettingsTable, Setting> _row(String key) =>
      _db.select(_db.settings)..where((s) => s.key.equals(key));

  Future<String?> getString(String key) async =>
      (await _row(key).getSingleOrNull())?.value;

  Future<void> setString(String key, String? v) async {
    if (v == null) {
      await (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();
      return;
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: v));
  }

  /// Emits the current value (null when unset), then every change.
  Stream<String?> watchString(String key) =>
      _row(key).watchSingleOrNull().map((r) => r?.value).distinct();

  Future<bool> getBool(String key, {required bool fallback}) async =>
      _parse(await getString(key), fallback);

  Future<void> setBool(String key, bool v) => setString(key, v ? '1' : '0');

  /// Emits the current value, then every change.
  Stream<bool> watchBool(String key, {required bool fallback}) =>
      _row(key)
          .watchSingleOrNull()
          .map((r) => _parse(r?.value, fallback))
          .distinct();

  static bool _parse(String? v, bool fallback) =>
      v == null ? fallback : v == '1' || v == 'true';
}
