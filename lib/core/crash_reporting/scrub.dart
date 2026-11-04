import 'package:sentry_flutter/sentry_flutter.dart';

/// Where an absolute path starts: a `file://` URL, a Windows drive or UNC
/// path, or a POSIX folder songs and app data live in.
const _pathStart =
    r'(?:file://|[A-Za-z]:[\\/]|\\\\|/(?:home|storage|data|tmp|media|mnt|run/media)/)';

/// A path inside quotes, which may hold spaces (`'/home/d/My Song.mp3'`).
final _quotedPath = RegExp('(["\'`])$_pathStart[^"\'`\\n]*\\1');

/// A bare path, which ends at the next whitespace or quote.
final _barePath = RegExp('$_pathStart[^\\s"\'`]*');

/// Breadcrumb categories worth keeping; the last is the SDK's own lifecycle one.
const _keptCategories = {'navigation', 'player', 'app.lifecycle'};

/// Replaces absolute file paths in [text] with `<path>`.
String scrubPaths(String text) => text
    .replaceAllMapped(_quotedPath, (m) => '${m[1]}<path>${m[1]}')
    .replaceAll(_barePath, '<path>');

Object? _scrubValue(Object? value) {
  if (value is String) return scrubPaths(value);
  if (value is Map) {
    return {for (final e in value.entries) e.key: _scrubValue(e.value)};
  }
  if (value is List) return [for (final v in value) _scrubValue(v)];
  return value;
}

Breadcrumb _scrubCrumb(Breadcrumb crumb) {
  final message = crumb.message;
  if (message != null) crumb.message = scrubPaths(message);
  final data = crumb.data;
  if (data != null) {
    crumb.data = {for (final e in data.entries) e.key: _scrubValue(e.value)};
  }
  return crumb;
}

/// `beforeSend`: hides file paths in the event's text and removes the user,
/// server name and request data.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  for (final e in event.exceptions ?? const <SentryException>[]) {
    final value = e.value;
    if (value != null) e.value = scrubPaths(value);
  }
  final message = event.message;
  if (message != null) {
    message.formatted = scrubPaths(message.formatted);
    final template = message.template;
    if (template != null) message.template = scrubPaths(template);
    final params = message.params;
    if (params != null) message.params = _scrubValue(params) as List;
  }
  for (final c in event.breadcrumbs ?? const <Breadcrumb>[]) {
    _scrubCrumb(c);
  }
  event.user = null;
  event.serverName = null;
  event.request = null;
  return event;
}

/// `beforeBreadcrumb`: keeps navigation, player and lifecycle crumbs (scrubbed)
/// and drops everything else.
Breadcrumb? filterBreadcrumb(Breadcrumb? crumb, Hint hint) {
  if (crumb == null || !_keptCategories.contains(crumb.category)) return null;
  return _scrubCrumb(crumb);
}
