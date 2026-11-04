import 'package:flutter/foundation.dart';

/// The Sentry DSN, passed with `--dart-define=SENTRY_DSN=…` on tagged releases.
const String kSentryDsn = String.fromEnvironment('SENTRY_DSN');

/// The release name (`songies@X.Y.Z+N`), passed with
/// `--dart-define=SENTRY_RELEASE=…`.
const String kSentryRelease = String.fromEnvironment('SENTRY_RELEASE');

/// Whether this build can report crashes at all: a release build with a DSN.
bool crashReportingBuilt({
  bool releaseMode = kReleaseMode,
  String dsn = kSentryDsn,
}) => releaseMode && dsn.isNotEmpty;
