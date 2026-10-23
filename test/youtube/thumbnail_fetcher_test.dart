import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/youtube/thumbnail_fetcher.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('songies_thumb_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a download that never finishes gives up after the timeout', () async {
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = old);
    final f = ThumbnailFetcher(
      ArtCache(Directory('${tmp.path}/art')),
      (u) => Completer<List<int>>().future,
      timeout: const Duration(milliseconds: 50),
    );
    expect(await f.fetch('https://img/a.jpg'), isNull);
  });
}
