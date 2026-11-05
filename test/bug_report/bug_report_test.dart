import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/bug_report/bug_report.dart';

BugReport _report({String description = 'It broke', String? name = 'Sam'}) =>
    BugReport(
      description: description,
      name: name,
      device: const DeviceSummary(
        platform: 'android',
        os: 'Android 14',
        model: 'Google Pixel 8',
      ),
      version: '1.1.3+7',
      time: DateTime.utc(2026, 11, 5, 12),
      installId: 'abc-123',
      log: Uint8List(0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readDeviceSummary', () {
    const channel = MethodChannel('songies/device');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test(
      'Android: model, release and API level come from the channel',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => {
                'model': 'Google Pixel 8',
                'release': '14',
                'sdk': 34,
              },
            );
        final d = await readDeviceSummary(isAndroid: true);
        expect(d.model, 'Google Pixel 8');
        expect(d.os, 'Android 14 (API 34)');
        expect(d.os, isNot(contains('Linux')));
      },
    );

    test('Android: a failing channel says unknown', () async {
      final d = await readDeviceSummary(isAndroid: true);
      expect(d.model, 'unknown');
      expect(d.os, startsWith('Android'));
    });

    test(
      'Linux: the model is the os-release PRETTY_NAME, else Linux',
      () async {
        final dir = Directory.systemTemp.createTempSync('osrel');
        addTearDown(() => dir.deleteSync(recursive: true));
        final f = File('${dir.path}/os-release')
          ..writeAsStringSync('NAME="Fedora"\nPRETTY_NAME="Fedora Linux 44"\n');
        expect(
          (await readDeviceSummary(isLinux: true, osReleasePath: f.path)).model,
          'Fedora Linux 44',
        );
        expect(
          (await readDeviceSummary(
            isLinux: true,
            osReleasePath: '${dir.path}/missing',
          )).model,
          'Linux',
        );
      },
    );

    test('parseOsReleasePrettyName handles quotes and absence', () {
      expect(
        parseOsReleasePrettyName("PRETTY_NAME='Arch Linux'\n"),
        'Arch Linux',
      );
      expect(parseOsReleasePrettyName('PRETTY_NAME=Plain\n'), 'Plain');
      expect(parseOsReleasePrettyName('NAME=x\n'), isNull);
    });
  });

  group('redactDeviceNames', () {
    test('replaces each name and ignores empty or very short ones', () {
      expect(
        redactDeviceNames('Synced with mira-pc ok', ['mira-pc', '', 'ab']),
        'Synced with <device> ok',
      );
      expect(redactDeviceNames('ab cd', ['ab']), 'ab cd');
    });
  });

  test('bugReportsBuilt is false for an empty webhook', () {
    expect(bugReportsBuilt(webhook: ''), isFalse);
    expect(
      bugReportsBuilt(webhook: 'https://discord.example/api/webhooks/1/x'),
      isTrue,
    );
  });

  group('collectLog', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bugreport_log'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('joins rotated + current, scrubs paths and keeps the newest 2 MB', () {
      File('${dir.path}/songies.log.1').writeAsStringSync('old line\n');
      File(
        '${dir.path}/songies.log',
      ).writeAsStringSync('opened /home/sam/Music/secret.mp3 ok\nnew line\n');
      final text = utf8.decode(collectLog(dir));
      expect(text.indexOf('old line'), lessThan(text.indexOf('new line')));
      expect(text, isNot(contains('sam')));
      expect(text, isNot(contains('secret.mp3')));

      final big = List.generate(40000, (i) => 'line $i ${'x' * 80}').join('\n');
      File('${dir.path}/songies.log').writeAsStringSync('$big\nlast line\n');
      final bytes = collectLog(dir);
      expect(bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
      final trimmed = utf8.decode(bytes);
      expect(trimmed, endsWith('last line\n'));
      expect(trimmed, isNot(contains('old line')));
      expect(trimmed, startsWith('line '), reason: 'starts on a whole line');
    });

    test('replaces the given device names with <device>', () {
      File('${dir.path}/songies.log')
          .writeAsStringSync('Synced with mira-pc\nSynced with Den Laptop\n');
      final text = utf8.decode(
        collectLog(dir, deviceNames: ['mira-pc', 'Den Laptop']),
      );
      expect(text, 'Synced with <device>\nSynced with <device>\n');
    });

    test('is empty when there are no log files', () {
      expect(collectLog(dir), isEmpty);
    });
  });

  group('discordPayload', () {
    test('has the description, fields and no mentions', () {
      final p = discordPayload(_report());
      expect(p['allowed_mentions'], {'parse': <String>[]});
      final embeds = p['embeds']! as List;
      expect(embeds, hasLength(1));
      final e = embeds.single as Map;
      expect(e['title'], 'Bug report');
      expect(e['description'], 'It broke');
      expect(e['timestamp'], '2026-11-05T12:00:00.000Z');
      final fields = {
        for (final f in e['fields'] as List) (f as Map)['name']: f['value'],
      };
      expect(fields['Name'], 'Sam');
      expect(fields['Version'], '1.1.3+7');
      expect(fields['Device'], contains('Google Pixel 8'));
      expect(fields['Device'], contains('Android 14'));
      expect(fields['Install id'], 'abc-123');
    });

    test('truncates long text to Discord limits', () {
      final p = discordPayload(
        _report(description: 'd' * 6000, name: 'n' * 300),
      );
      final e = (p['embeds']! as List).single as Map;
      final d = e['description'] as String;
      expect(d.length, lessThanOrEqualTo(4096));
      expect(d, endsWith('…'));
      for (final f in e['fields'] as List) {
        expect(((f as Map)['value'] as String).length, lessThanOrEqualTo(1024));
      }
    });

    test('lists the attachments', () {
      final r = BugReport(
        description: 'x' * 10,
        device: const DeviceSummary(platform: 'linux', os: 'Linux', model: 'd'),
        version: '1.1.3+7',
        time: DateTime.utc(2026),
        log: Uint8List(1),
        screenshot: (fileName: 'shot.png', bytes: Uint8List(1)),
      );
      final a = discordPayload(r)['attachments']! as List;
      expect(a.map((x) => (x as Map)['filename']), [
        'songies-log.txt',
        'shot.png',
      ]);
      expect(a.map((x) => (x as Map)['id']), [0, 1]);
      final none = discordPayload(_report())['attachments']! as List;
      expect(none, hasLength(1));
    });
  });
}
