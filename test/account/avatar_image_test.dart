import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:songies/account/avatar_image.dart';

import 'image_fixtures.dart';

void main() {
  test('avatarJpeg makes a 256x256 jpeg from a wide image, centre-cropped', () {
    // 600x200: red left third, green middle third, blue right third.
    final src = img.Image(width: 600, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 600; x++) {
        final c = x < 200
            ? img.ColorRgb8(255, 0, 0)
            : x < 400
            ? img.ColorRgb8(0, 255, 0)
            : img.ColorRgb8(0, 0, 255);
        src.setPixel(x, y, c);
      }
    }
    final out = avatarJpeg(Uint8List.fromList(img.encodePng(src)));
    // JPEG magic number.
    expect(out.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);
    // Only the green middle survives the crop.
    for (final (x, y) in [(5, 5), (128, 128), (250, 250)]) {
      final p = decoded.getPixel(x, y);
      expect(p.g, greaterThan(200), reason: '($x,$y)');
      expect(p.r, lessThan(60), reason: '($x,$y)');
      expect(p.b, lessThan(60), reason: '($x,$y)');
    }
  });

  test('avatarJpeg throws FormatException on bytes that are not an image', () {
    expect(
      () => avatarJpeg(Uint8List.fromList([1, 2, 3, 4])),
      throwsFormatException,
    );
  });

  test('avatarJpeg fills transparent areas with white', () {
    final src = img.Image(width: 50, height: 50, numChannels: 4);
    final out = img.decodeJpg(
      avatarJpeg(Uint8List.fromList(img.encodePng(src))),
    )!;
    final p = out.getPixel(128, 128);
    expect([p.r, p.g, p.b], everyElement(greaterThan(240)));
  });

  test('avatarJpeg refuses images over 40 megapixels from the header', () {
    expect(kMaxAvatarPixels, 40000000);
    expect(
      () => avatarJpeg(hugePngHeader(8000, 6000)),
      throwsA(isA<ImageTooBigException>()),
    );
    // A small header gets past the size check (and then fails to decode
    // the made-up pixel data).
    expect(
      () => avatarJpeg(hugePngHeader(100, 100)),
      throwsA(isNot(isA<ImageTooBigException>())),
    );
  });
}
