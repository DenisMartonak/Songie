import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/log.dart';

void main() {
  test('rotates at 2 MB', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.deleteSync(recursive: true));
    await AppLog.init(dir);
    final line = 'x' * 1024;
    for (var i = 0; i < 2100; i++) {
      AppLog.i(line);
    }
    await AppLog.flush();
    expect(File('${dir.path}/songies.log.1').existsSync(), isTrue);
    expect(
      File('${dir.path}/songies.log').lengthSync(),
      lessThan(2 * 1024 * 1024),
    );
  });
}
