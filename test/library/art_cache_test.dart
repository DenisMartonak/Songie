import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:songies/library/art_cache.dart';

Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tmp;
  late ArtCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('songies_art_');
    cache = ArtCache(Directory('${tmp.path}/art'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('put downscales a 1200x800 PNG to 512x341 JPEG', () async {
    final ref = await cache.put(_png(1200, 800));
    expect(ref, isNotNull);
    expect(ref, endsWith('.jpg'));
    final decoded = img.decodeJpg(cache.fileFor(ref!).readAsBytesSync())!;
    expect(decoded.width, 512);
    expect(decoded.height, 341);
  });

  test('put does not upscale small images', () async {
    final ref = await cache.put(_png(100, 60));
    final decoded = img.decodeJpg(cache.fileFor(ref!).readAsBytesSync())!;
    expect(decoded.width, 100);
    expect(decoded.height, 60);
  });

  test('put downscales portrait images by the longest side', () async {
    final ref = await cache.put(_png(800, 1200));
    final decoded = img.decodeJpg(cache.fileFor(ref!).readAsBytesSync())!;
    expect(decoded.width, 341);
    expect(decoded.height, 512);
  });

  test(
    'put of the same bytes twice returns the same ref without rewriting',
    () async {
      final bytes = _png(1200, 800);
      final first = await cache.put(bytes);
      final file = cache.fileFor(first!);
      final old = DateTime.utc(2020);
      file.setLastModifiedSync(old);
      final second = await cache.put(bytes);
      expect(second, first);
      expect(file.lastModifiedSync().toUtc(), old);
    },
  );

  test('put leaves no .tmp file behind', () async {
    final ref = await cache.put(_png(64, 64));
    final names = cache
        .fileFor(ref!)
        .parent
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(names, [ref]);
  });

  test('put returns null for undecodable bytes', () async {
    expect(await cache.put(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('put returns null for empty bytes', () async {
    expect(await cache.put(Uint8List(0)), isNull);
  });

  test('put returns null instead of throwing when the directory is unusable', () async {
    // A regular file where the art directory should be.
    final blocker = File('${tmp.path}/blocked')..writeAsStringSync('x');
    final bad = ArtCache(Directory('${blocker.path}/art'));
    // AppLog falls back to debugPrint; keep the expected warning out of output.
    final oldPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = oldPrint);
    expect(await bad.put(_png(32, 32)), isNull);
  });

  test('fileFor resolves inside the cache directory', () {
    expect(cache.fileFor('abc.jpg').path, endsWith('abc.jpg'));
    expect(cache.fileFor('abc.jpg').parent.path, '${tmp.path}/art');
  });
}
