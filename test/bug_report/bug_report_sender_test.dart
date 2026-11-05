import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songies/bug_report/bug_report.dart';
import 'package:songies/bug_report/bug_report_sender.dart';

const _hook = 'https://discord.example/api/webhooks/1/x';

BugReport _report({int logBytes = 100, int? shotBytes}) => BugReport(
  description: 'It broke when I pressed play',
  device: const DeviceSummary(
    platform: 'linux',
    os: 'Linux 6',
    model: 'desktop',
  ),
  version: '1.1.3+7',
  time: DateTime.utc(2026, 11, 5),
  log: Uint8List.fromList(List.filled(logBytes, 0x61)),
  screenshot: shotBytes == null
      ? null
      : (fileName: 'shot.png', bytes: Uint8List(shotBytes)),
);

void main() {
  test('refuses when the webhook is empty', () async {
    var called = false;
    final s = BugReportSender(
      client: MockClient((_) async {
        called = true;
        return http.Response('', 204);
      }),
      webhook: '',
    );
    expect(await s.send(_report()), BugReportSendResult.notBuilt);
    expect(called, isFalse);
  });

  test(
    'send posts multipart with payload_json, the log file and the screenshot',
    () async {
      late http.BaseRequest seen;
      late String body;
      final s = BugReportSender(
        client: MockClient((req) async {
          seen = req;
          body = latin1.decode(req.bodyBytes);
          return http.Response('', 204);
        }),
        webhook: _hook,
      );
      expect(await s.send(_report(shotBytes: 10)), BugReportSendResult.sent);
      expect(seen.url.toString(), _hook);
      expect(seen.method, 'POST');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      expect(body, contains('name="payload_json"'));
      expect(body, contains('name="files[0]"; filename="songies-log.txt"'));
      expect(body, contains('name="files[1]"; filename="shot.png"'));
      expect(body, contains('"allowed_mentions"'));
    },
  );

  test('send trims the log so log + 7 MB image stays under 10 MB', () async {
    var size = 0;
    final s = BugReportSender(
      client: MockClient((req) async {
        size = req.bodyBytes.length;
        return http.Response('', 204);
      }),
      webhook: _hook,
    );
    final r = _report(logBytes: 2 * 1024 * 1024, shotBytes: maxScreenshotBytes);
    expect(await s.send(r), BugReportSendResult.sent);
    expect(size, lessThan(10 * 1024 * 1024));
    expect(size, greaterThan(maxScreenshotBytes));
  });

  test(
    'send returns failed on 429, 500 and a socket error, no cooldown',
    () async {
      for (final h in <Future<http.Response> Function(http.Request)>[
        (_) async => http.Response('', 429),
        (_) async => http.Response('', 500),
        (_) async => throw const SocketException('no network'),
      ]) {
        final s = BugReportSender(client: MockClient(h), webhook: _hook);
        expect(await s.send(_report()), BugReportSendResult.failed);
      }
      var fail = true;
      final s = BugReportSender(
        client: MockClient(
          (_) async => fail ? http.Response('', 500) : http.Response('', 204),
        ),
        webhook: _hook,
      );
      expect(await s.send(_report()), BugReportSendResult.failed);
      fail = false;
      expect(await s.send(_report()), BugReportSendResult.sent);
    },
  );

  test(
    'a second send within 60 s of a success is tooSoon; after 60 s it sends',
    () async {
      var now = DateTime.utc(2026, 11, 5, 12);
      var calls = 0;
      final s = BugReportSender(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 204);
        }),
        webhook: _hook,
        now: () => now,
      );
      expect(await s.send(_report()), BugReportSendResult.sent);
      now = now.add(const Duration(seconds: 59));
      expect(await s.send(_report()), BugReportSendResult.tooSoon);
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      expect(await s.send(_report()), BugReportSendResult.sent);
      expect(calls, 2);
    },
  );

  test('the webhook URL appears in no log line or exception text', () async {
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => lines.add(m ?? '');
    addTearDown(() => debugPrint = old);
    for (final h in <Future<http.Response> Function(http.Request)>[
      (_) async => http.Response('', 500),
      (r) async => throw http.ClientException('failed', r.url),
    ]) {
      final s = BugReportSender(client: MockClient(h), webhook: _hook);
      expect(await s.send(_report()), BugReportSendResult.failed);
    }
    expect(lines, isNotEmpty);
    for (final l in lines) {
      expect(l, isNot(contains('discord')));
      expect(l, isNot(contains('webhooks')));
    }
  });
}
