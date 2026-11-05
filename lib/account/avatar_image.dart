import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Side of the stored profile picture, in pixels.
const kAvatarSize = 256;

/// The most pixels a source picture may have; bigger ones would take too
/// much memory to decode.
const kMaxAvatarPixels = 40000000;

/// The picture has more than [kMaxAvatarPixels] pixels.
class ImageTooBigException implements Exception {
  const ImageTooBigException();
  @override
  String toString() => 'ImageTooBigException';
}

/// A profile picture from any image file: turned upright, centre-cropped to
/// a square, scaled to 256×256, laid on white and encoded as JPEG (quality
/// 85). Throws [FormatException] when [imageBytes] isn't an image it can
/// read, and [ImageTooBigException] (from the header, before decoding) when
/// it has more than [kMaxAvatarPixels] pixels.
Uint8List avatarJpeg(Uint8List imageBytes) {
  img.Image? decoded;
  try {
    final decoder = img.findDecoderForData(imageBytes);
    final info = decoder?.startDecode(imageBytes);
    if (info != null && info.width * info.height > kMaxAvatarPixels) {
      throw const ImageTooBigException();
    }
    decoded = decoder?.decode(imageBytes);
  } on ImageTooBigException {
    rethrow;
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) throw const FormatException('Not an image');
  final upright = img.bakeOrientation(decoded);
  final side = math.min(upright.width, upright.height);
  final square = img.copyCrop(
    upright,
    x: (upright.width - side) ~/ 2,
    y: (upright.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final small = img.copyResize(
    square,
    width: kAvatarSize,
    height: kAvatarSize,
    interpolation: img.Interpolation.average,
  );
  // JPEG has no transparency: transparent areas become white.
  final opaque = img.Image(width: kAvatarSize, height: kAvatarSize)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(opaque, small);
  return img.encodeJpg(opaque, quality: 85);
}
