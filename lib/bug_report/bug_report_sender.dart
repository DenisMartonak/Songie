import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/log.dart';
import 'bug_report.dart';

/// The biggest screenshot accepted.
const int maxScreenshotBytes = 7 * 1024 * 1024;

/// Discord accepts 10 MB per message; this leaves room for the form framing.
const int _maxBodyBytes = 10 * 1024 * 1024 - 64 * 1024;

const Duration _cooldown = Duration(seconds: 60);

enum BugReportSendResult { sent, failed, tooSoon, notBuilt }

/// Posts bug reports to the Discord webhook, one successful report a minute.
class BugReportSender {
  BugReportSender({
    required this._client,
    this._webhook = kBugReportWebhook,
    this._now = DateTime.now,
  });

  final http.Client _client;
  final String _webhook;
  final DateTime Function() _now;
  DateTime? _lastSent;

  /// Sends [r]. Never throws; failures are logged without the URL and do not
  /// start the cooldown.
  Future<BugReportSendResult> send(BugReport r) async {
    if (!bugReportsBuilt(webhook: _webhook)) {
      return BugReportSendResult.notBuilt;
    }
    final last = _lastSent;
    if (last != null && _now().difference(last) < _cooldown) {
      return BugReportSendResult.tooSoon;
    }
    try {
      final payload = jsonEncode(discordPayload(r));
      final shot = r.screenshot;
      final budget =
          _maxBodyBytes -
          utf8.encode(payload).length -
          (shot?.bytes.length ?? 0) -
          (shot?.fileName.length ?? 0) * 2;
      final log = trimToNewest(r.log, budget < 0 ? 0 : budget);
      final request = http.MultipartRequest('POST', Uri.parse(_webhook))
        ..fields['payload_json'] = payload
        ..files.add(
          http.MultipartFile.fromBytes(
            'files[0]',
            log,
            filename: 'songies-log.txt',
          ),
        );
      if (shot != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files[1]',
            shot.bytes,
            filename: shot.fileName,
          ),
        );
      }
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastSent = _now();
        return BugReportSendResult.sent;
      }
      AppLog.w('Bug report failed: HTTP ${response.statusCode}');
    } catch (e) {
      // Only the type: the exception text can carry the webhook URL.
      AppLog.w('Bug report failed: ${e.runtimeType}');
    }
    return BugReportSendResult.failed;
  }
}
