import 'package:flutter_test/flutter_test.dart';
import 'package:songies/bug_report/bug_report.dart';
import 'package:songies/remote/device_name.dart';

Future<DeviceSummary> _pixel() async =>
    const DeviceSummary(platform: 'android', os: 'Android', model: 'Pixel 8');

Future<DeviceSummary> _desktop() async =>
    const DeviceSummary(platform: 'linux', os: 'Linux', model: 'desktop');

void main() {
  test('the stored name wins', () async {
    expect(
      await remoteDeviceName(
        storedName: () async => 'Kitchen',
        isAndroid: true,
        readDevice: _pixel,
        hostname: 'localhost',
      ),
      'Kitchen',
    );
  });

  test('Android uses the model', () async {
    expect(
      await remoteDeviceName(
        storedName: () async => null,
        isAndroid: true,
        readDevice: _pixel,
        hostname: 'localhost',
      ),
      'Pixel 8',
    );
  });

  test('desktop uses the hostname', () async {
    expect(
      await remoteDeviceName(
        storedName: () async => null,
        isAndroid: false,
        readDevice: _desktop,
        hostname: 'deno-pc',
      ),
      'deno-pc',
    );
  });

  test('a blank stored name is ignored', () async {
    expect(
      await remoteDeviceName(
        storedName: () async => '   ',
        isAndroid: false,
        readDevice: _desktop,
        hostname: 'deno-pc',
      ),
      'deno-pc',
    );
  });

  test('a failing read falls back instead of throwing', () async {
    expect(
      await remoteDeviceName(
        storedName: () async => throw StateError('db closed'),
        isAndroid: true,
        readDevice: () async => throw StateError('no channel'),
        hostname: 'localhost',
      ),
      isNotEmpty,
    );
  });
}
