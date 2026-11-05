import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../data/settings_repository.dart';
import '../ids.dart';
import '../log.dart';
import 'crash_config.dart';
import 'scrub.dart';

/// Starts and stops crash reporting to follow the "Send crash reports"
/// setting. Starts and closes run one at a time: a toggle that arrives while
/// one is pending is applied after it, so two starts never overlap.
class CrashReporter {
  CrashReporter({
    required this._built,
    required this._start,
    required this._close,
  });

  /// The reporter for this build: Sentry, started only in a release build
  /// with a DSN. Sentry keeps its files under [dataRoot], and reports carry
  /// the install id kept in [settings].
  factory CrashReporter.sentry({
    required String dataRoot,
    required SettingsRepository settings,
  }) => CrashReporter(
    built: crashReportingBuilt(),
    start: () async => startSentry(
      dataRoot: dataRoot,
      installId: await crashInstallId(settings),
    ),
    close: Sentry.close,
  );

  final bool _built;
  final Future<void> Function() _start;
  final Future<void> Function() _close;

  bool _wanted = false;
  bool _running = false;

  /// The last start failed; only a change from off to on tries again.
  bool _failed = false;
  Future<void>? _busy;
  StreamSubscription<bool>? _sub;

  /// Whether reporting is started.
  bool get running => _running;

  /// Starts or stops reporting to match [on]. Completes once the reporter
  /// has caught up with the latest setting.
  Future<void> applySetting(bool on) {
    _wanted = on;
    if (!on) _failed = false;
    if (_busy == null && (!_built || _running == _wanted || _failed)) {
      return Future.value();
    }
    return _busy ??= _settle();
  }

  Future<void> _settle() async {
    // Yield first, so [_busy] is set before the `finally` below clears it.
    await Future<void>.value();
    try {
      while (_running != _wanted) {
        if (_wanted) {
          try {
            await _start();
            _running = true;
          } catch (e, s) {
            AppLog.w('Crash reporting did not start', e, s);
            _failed = true;
            // The SDK may be partly up; close it so "stopped" is true. The
            // next switch from off to on tries again.
            try {
              await _close();
            } catch (e, s) {
              AppLog.w('Crash reporting did not close cleanly', e, s);
            }
            return;
          }
        } else {
          try {
            await _close();
          } catch (e, s) {
            AppLog.w('Crash reporting did not close cleanly', e, s);
          }
          _running = false;
        }
      }
    } finally {
      _busy = null;
    }
  }

  /// Applies every value [setting] emits. Does nothing in a build that can't
  /// report.
  void follow(Stream<bool> setting) {
    if (!_built) return;
    _sub?.cancel();
    _sub = setting.listen(
      (on) => unawaited(applySetting(on)),
      onError: (Object e, StackTrace s) =>
          AppLog.w('Crash report setting unreadable', e, s),
    );
  }

  /// Stops following the setting and stops reporting.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await applySetting(false);
  }
}

/// This device's random crash report id, made on first use and kept in
/// [settings].
Future<String> crashInstallId(SettingsRepository settings) async {
  final stored = await settings.getString(kCrashInstallId);
  if (stored != null && stored.isNotEmpty) return stored;
  final id = newId();
  await settings.setString(kCrashInstallId, id);
  return id;
}

/// Starts Sentry (see [configureSentry]) and tags every report, native
/// crashes included, with [installId] as the only user field.
Future<void> startSentry({
  required String dataRoot,
  required String installId,
}) async {
  await SentryFlutter.init((o) => configureSentry(o, dataRoot: dataRoot));
  await Sentry.configureScope((s) => s.setUser(SentryUser(id: installId)));
}

/// Sentry options with nothing personal: scrubbed events, only navigation,
/// player and lifecycle breadcrumbs, no screenshots and no tracing. Native
/// crashes (with minidumps) and Android ANRs are reported. On desktop the
/// native crash files live in `<dataRoot>/sentry`, not the working folder.
void configureSentry(SentryFlutterOptions o, {required String dataRoot}) {
  o
    ..nativeDatabasePath = p.join(dataRoot, 'sentry')
    ..dsn = kSentryDsn
    ..release = kSentryRelease
    ..environment = 'production'
    ..sendDefaultPii = false
    ..beforeSend = scrubEvent
    ..beforeBreadcrumb = filterBreadcrumb
    ..anrEnabled = true
    ..enableNativeCrashHandling = true
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    ..tracesSampleRate = null
    // Native breadcrumbs skip beforeBreadcrumb, so they must stay off.
    ..enableAutoNativeBreadcrumbs = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableAppLifecycleBreadcrumbs = true;
}
