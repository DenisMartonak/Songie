import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
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
    expect(await f.fetchBest(['https://img/a.jpg']), isNull);
  });

  List<int> png(int w, int h, {img.Color? color}) {
    final image = img.Image(width: w, height: h);
    if (color != null) img.fill(image, color: color);
    return img.encodePng(image);
  }

  ThumbnailFetcher fetcherFor(Map<String, Object> responses) =>
      ThumbnailFetcher(ArtCache(Directory('${tmp.path}/art')), (u) async {
        final r = responses[u.toString()];
        if (r is List<int>) return r;
        throw HttpException('HTTP 404', uri: u);
      });

  Future<img.Image> stored(ThumbnailFetcher f, String ref) async =>
      img.decodeJpg(File('${tmp.path}/art/$ref').readAsBytesSync())!;

  test('fetchBest skips a 404 and stores a 720x720 yt2- square', () async {
    final f = fetcherFor({'https://b/2': png(1280, 720)});
    final ref = await f.fetchBest(['https://b/1', 'https://b/2']);
    expect(ref, startsWith('yt2-'));
    final im = await stored(f, ref!);
    expect((im.width, im.height), (720, 720));
  });

  test('the 120x90 placeholder counts as a miss', () async {
    final f = fetcherFor({
      'https://b/1': png(120, 90),
      'https://b/2': png(640, 360),
    });
    final ref = await f.fetchBest(['https://b/1', 'https://b/2']);
    expect((await stored(f, ref!)).width, 360);
    expect(await f.fetchBest(['https://b/1']), isNull);
  });

  test('all candidates missing gives null', () async {
    expect(
      await fetcherFor({}).fetchBest(['https://b/1', 'https://b/2']),
      isNull,
    );
  });

  test('letterbox bars of a 640x480 image are cropped away', () async {
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(
      image,
      x1: 0,
      y1: 60,
      x2: 639,
      y2: 419,
      color: img.ColorRgb8(220, 40, 40),
    );
    final f = fetcherFor({'https://b/1': img.encodePng(image)});
    final im = await stored(f, (await f.fetchBest(['https://b/1']))!);
    for (final (x, y) in [
      (0, 0),
      (im.width - 1, 0),
      (0, im.height - 1),
      (im.width - 1, im.height - 1),
    ]) {
      expect(im.getPixel(x, y).r, greaterThan(100), reason: '($x,$y)');
    }
  });
}
