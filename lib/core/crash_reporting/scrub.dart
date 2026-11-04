import 'package:sentry_flutter/sentry_flutter.dart';

/// Where an absolute path starts: a `file://` or `content://` URI, a Windows
/// drive or UNC path, `~/`, or a POSIX folder songs and app data live in. A
/// start must begin a token, so URLs and `package:` URIs are left alone.
final _pathStart = RegExp(
  r'file://|content://|(?<![A-Za-z])[A-Za-z]:[\\/]|\\\\'
  r'|(?<![\w:/.~-])(?:~/|/(?:home|storage|sdcard|root|Users|var|opt|proc|data|tmp|media|mnt|run/media)/)',
);

/// A file extension that ends a path whose name may hold spaces.
final _extension = RegExp(
  r'\.(?:mp3|flac|m4a|aac|ogg|opus|wav|wma|webm|mp4|jpg|jpeg|png|webp|json|db|sqlite|lrc)(?!\w)',
  caseSensitive: false,
);

/// Breadcrumb categories worth keeping; the last is the SDK's own lifecycle one.
const _keptCategories = {'navigation', 'player', 'app.lifecycle'};

/// Where the path that starts at [from] in [text] ends.
int _pathEnd(String text, int from, int start) {
  final lineEnd = text.indexOf('\n', from);
  final line = lineEnd < 0 ? text.length : lineEnd;
  // Inside quotes the path runs to the closing quote: one not followed by a
  // letter or digit, so an apostrophe in a name ("Don't Stop") doesn't end it.
  if (start > 0) {
    final q = text[start - 1];
    if (q == '"' || q == "'" || q == '`') {
      for (var i = text.indexOf(q, from); i >= 0 && i < line;) {
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (!RegExp(r'\w').hasMatch(next)) return i;
        i = text.indexOf(q, i + 1);
      }
    }
  }
  // Otherwise through the first file extension on the line (the name may hold
  // spaces), or to the next whitespace or quote.
  final ext = _extension.firstMatch(text.substring(from, line));
  if (ext != null) return from + ext.end;
  var i = from;
  while (i < line && !' \t\r"\'`'.contains(text[i])) {
    i++;
  }
  return i;
}

/// Replaces absolute file paths in [text] with `<path>`.
String scrubPaths(String text) {
  final out = StringBuffer();
  var pos = 0;
  for (final m in _pathStart.allMatches(text)) {
    if (m.start < pos) continue;
    out
      ..write(text.substring(pos, m.start))
      ..write('<path>');
    pos = _pathEnd(text, m.end, m.start);
  }
  out.write(text.substring(pos));
  return out.toString();
}

Object? _scrubValue(Object? value) {
  if (value is String) return scrubPaths(value);
  if (value is Map) {
    return {for (final e in value.entries) e.key: _scrubValue(e.value)};
  }
  if (value is List) return [for (final v in value) _scrubValue(v)];
  return value;
}

/// Scrubs the string, map and list values of [map] in place; typed objects
/// (such as device contexts) are left as they are.
void _scrubMap(Map<String, dynamic> map) {
  for (final key in map.keys.toList()) {
    map[key] = _scrubValue(map[key]);
  }
}

Breadcrumb _scrubCrumb(Breadcrumb crumb) {
  final message = crumb.message;
  if (message != null) crumb.message = scrubPaths(message);
  final data = crumb.data;
  if (data != null) {
    crumb.data = <String, dynamic>{
      for (final e in data.entries) e.key: _scrubValue(e.value),
    };
  }
  return crumb;
}

void _scrubStackTrace(SentryStackTrace? trace) {
  for (final f in trace?.frames ?? const <SentryStackFrame>[]) {
    final absPath = f.absPath;
    if (absPath != null) f.absPath = scrubPaths(absPath);
    final fileName = f.fileName;
    if (fileName != null) f.fileName = scrubPaths(fileName);
    final package = f.package;
    if (package != null) f.package = scrubPaths(package);
  }
}

/// `beforeSend`: hides file paths in everything the event carries as text,
/// keeps only the breadcrumbs `filterBreadcrumb` allows, and removes the user,
/// server name and request data.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  for (final e in event.exceptions ?? const <SentryException>[]) {
    final value = e.value;
    if (value != null) e.value = scrubPaths(value);
    _scrubStackTrace(e.stackTrace);
  }
  for (final t in event.threads ?? const <SentryThread>[]) {
    _scrubStackTrace(t.stacktrace);
  }
  final message = event.message;
  if (message != null) {
    message.formatted = scrubPaths(message.formatted);
    final template = message.template;
    if (template != null) message.template = scrubPaths(template);
    final params = message.params;
    if (params != null) message.params = _scrubValue(params) as List;
  }
  final crumbs = event.breadcrumbs;
  if (crumbs != null) {
    event.breadcrumbs = [for (final c in crumbs) ?filterBreadcrumb(c, hint)];
  }
  final transaction = event.transaction;
  if (transaction != null) event.transaction = scrubPaths(transaction);
  final fingerprint = event.fingerprint;
  if (fingerprint != null) {
    event.fingerprint = [for (final f in fingerprint) scrubPaths(f)];
  }
  final tags = event.tags;
  if (tags != null) {
    event.tags = {for (final e in tags.entries) e.key: scrubPaths(e.value)};
  }
  // `extra` is deprecated, but older code paths may still fill it.
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null) _scrubMap(extra);
  _scrubMap(event.contexts);
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
