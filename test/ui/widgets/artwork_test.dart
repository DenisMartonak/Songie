import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/library/art_cache.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/widgets/artwork.dart';

void main() {
  testWidgets('a cover that arrives after it was drawn shows once art '
      'arrivals say so', (tester) async {
    final dir = Directory.systemTemp.createTempSync('artwork_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final arrivals = StreamController<int>.broadcast();
    addTearDown(arrivals.close);
    const ref = 'cover.jpg';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artCacheProvider.overrideWithValue(ArtCache(dir)),
          artArrivalsProvider.overrideWith((_) => arrivals.stream),
        ],
        child: MaterialApp(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          home: const Artwork(ref, size: 40),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: 50)),
    );
    await tester.pump();
    final first = tester.widget<Image>(find.byType(Image)).key;

    await tester.runAsync(() async {
      File(p.join(dir.path, ref)).writeAsBytesSync([0xFF, 0xD8]);
      arrivals.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    // A new key: the image is resolved again instead of keeping its error.
    expect(tester.widget<Image>(find.byType(Image)).key, isNot(first));
  });
}
