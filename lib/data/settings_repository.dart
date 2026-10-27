import 'dart:io';

import 'package:drift/drift.dart';

import 'database.dart';

/// Wi-Fi only *downloads* (the key predates the streaming switch).
const kWifiOnly = 'wifi_only';

/// Wi-Fi only streaming: refuse to stream on mobile data. Device-local,
/// off by default on every platform.
const kWifiOnlyStreaming = 'wifi_only_streaming';
const kYtdlpUseSystem = 'ytdlp_use_system';
const kReduceMotion = 'reduce_motion';

/// YouTube's anonymous visitor id (`visitorData`), sent on every Innertube
/// request. Device-local: never synced, never tied to an account.
const kYtVisitorData = 'yt_visitor_data';

/// Set once the user accepts YouTube's terms (the EU consent sheet); from
/// then on Innertube requests carry the `SOCS=CAI` cookie. Device-local.
const kYtConsentGiven = 'yt_consent_given';

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
