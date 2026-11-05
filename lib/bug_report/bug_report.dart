import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/crash_reporting/scrub.dart';
import '../core/log.dart';

/// Where bug reports go: a Discord webhook given at build time with
/// `--dart-define=BUG_REPORT_WEBHOOK=...`. A secret: never log or print it.
const String kBugReportWebhook = String.fromEnvironment('BUG_REPORT_WEBHOOK');

/// Whether this build can send bug reports (it was given a webhook).
bool bugReportsBuilt({String webhook = kBugReportWebhook}) =>
    webhook.isNotEmpty;

/// The biggest log sent: its newest 2 MB.
const int maxLogBytes = 2 * 1024 * 1024;

/// What the report says about the device. Never a host or user name.
class DeviceSummary {
  const DeviceSummary({
    required this.platform,
    required this.os,
    required this.model,
  });

  final String platform;
  final String os;
  final String model;
}

/// The device's platform, OS version and model. Android asks the platform for
/// the manufacturer and model; desktop has no model, so it says 'desktop'.
Future<DeviceSummary> readDeviceSummary() async {
  var model = 'desktop';
  var os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  if (Platform.isAndroid) {
    os = 'Android ${Platform.operatingSystemVersion}';
    try {
      final m = await const MethodChannel('songies/device')
          .invokeMethod<String>('model');
      model = (m == null || m.isEmpty) ? 'unknown' : m;
    } catch (_) {
      model = 'unknown';
    }
  }
  return DeviceSummary(
    platform: Platform.operatingSystem,
    os: os,
    model: model,
  );
}

/// One bug report, ready to be sent.
class BugReport {
  const BugReport({
    required this.description,
    this.name,
    required this.device,
    required this.version,
    required this.time,
    this.installId,
    required this.log,
    this.screenshot,
  });

  final String description;
  final String? name;
  final DeviceSummary device;

  /// App version and build, e.g. `1.1.3+7`.
  final String version;
  final DateTime time;

  /// The crash-reporting install id, only if one already exists.
  final String? installId;
  final Uint8List log;
  final ({String fileName, Uint8List bytes})? screenshot;
}

/// The app log (rotated, then current) with paths scrubbed from every line,
/// cut to its newest [maxBytes] on a whole line. Empty when there is no log.
Uint8List collectLog(Directory logsDir, {int maxBytes = maxLogBytes}) {
  final raw = readLogFiles(logsDir);
  if (raw == null) return Uint8List(0);
  final text = utf8
      .decode(raw, allowMalformed: true)
      .split('\n')
      .map(scrubPaths)
      .join('\n');
  return trimToNewest(utf8.encode(text), maxBytes);
}

/// The last [maxBytes] of [bytes], starting on a line start when it had to cut.
Uint8List trimToNewest(List<int> bytes, int maxBytes) {
  if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
  var start = bytes.length - maxBytes;
  final nl = bytes.indexOf(10, start - 1);
  if (nl >= 0 && nl < bytes.length - 1) start = nl + 1;
  return Uint8List.fromList(bytes.sublist(start));
}

String _cap(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

/// The Discord message for [r]: one embed, no mentions, and metadata for the
/// attached files (the log, then the screenshot).
Map<String, Object?> discordPayload(BugReport r) {
  final name = r.name?.trim();
  final d = r.device;
  return {
    'content': null,
    'allowed_mentions': {'parse': <String>[]},
    'embeds': [
      {
        'title': 'Bug report',
        'description': _cap(r.description, 4096),
        'timestamp': r.time.toUtc().toIso8601String(),
        'fields': [
          {
            'name': 'Name',
            'value': _cap(name == null || name.isEmpty ? '-' : name, 1024),
            'inline': true,
          },
          {'name': 'Version', 'value': _cap(r.version, 1024), 'inline': true},
          {
            'name': 'Device',
            'value': _cap('${d.model}, ${d.os} (${d.platform})', 1024),
            'inline': false,
          },
          {
            'name': 'Install id',
            'value': _cap(r.installId ?? '-', 1024),
            'inline': false,
          },
        ],
      },
    ],
    'attachments': [
      {'id': 0, 'filename': 'songies-log.txt'},
      if (r.screenshot != null) {'id': 1, 'filename': r.screenshot!.fileName},
    ],
  };
}
