import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/crash_reporting/crash_config.dart';

void main() {
  test('crashReportingBuilt needs release mode and a DSN', () {
    expect(crashReportingBuilt(releaseMode: false, dsn: 'x'), isFalse);
    expect(crashReportingBuilt(releaseMode: true, dsn: ''), isFalse);
    expect(crashReportingBuilt(releaseMode: true, dsn: 'x'), isTrue);
  });
}
