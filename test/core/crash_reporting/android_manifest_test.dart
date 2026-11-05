import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android network-event breadcrumbs are off in the manifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final entry = RegExp(
      r'<meta-data\s+android:name="io\.sentry\.breadcrumbs\.network-events"'
      r'\s+android:value="false"\s*/>',
    );
    expect(manifest, matches(entry));
  });
}
