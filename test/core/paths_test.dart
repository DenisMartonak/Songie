import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/paths.dart';

void main() {
  test(
    'at() lays out appData and ensureCreated makes every directory',
    () async {
      final tmp = await Directory.systemTemp.createTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final paths = AppPaths.at(Directory('${tmp.path}/data'));
      await paths.ensureCreated();
      for (final d in [
        paths.root,
        paths.art,
        paths.libraryLocal,
        paths.libraryYt,
        paths.fonts,
        paths.bin,
        paths.logs,
      ]) {
        expect(d.existsSync(), isTrue, reason: d.path);
      }
      expect(paths.db.path.endsWith('songies.db'), isTrue);
      expect(paths.logs.path.endsWith('logs'), isTrue);
    },
  );
}
