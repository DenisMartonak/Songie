import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/log.dart';

/// Disk cache of downscaled album covers: `<dir>/<sha256 of source>.jpg`
/// (`yt2-` prefixed when square-cropped YouTube art), longest side <= [maxSide], JPEG quality [jpegQuality].
class ArtCache {
  ArtCache(this.dir);

  static const int maxSide = 720;
  static const int jpegQuality = 85;

  final Directory dir;

  File fileFor(String ref) => File(p.join(dir.path, ref));

  /// Stores [imageBytes] and returns its ref, or null if the bytes cannot be
  /// decoded or the file cannot be written. Never throws.
  Future<String?> put(Uint8List imageBytes, {bool squareCrop = false}) async {
    try {
      final ref =
          '${squareCrop ? 'yt2-' : ''}${sha256.convert(imageBytes)}.jpg';
      final target = fileFor(ref);
      if (target.existsSync()) return ref;

      final jpg = await Isolate.run(() => _toJpeg(imageBytes, squareCrop));
      if (jpg == null) return null;

      dir.createSync(recursive: true);
      final tmp = File('${target.path}.tmp');
      try {
        tmp.writeAsBytesSync(jpg, flush: true);
        tmp.renameSync(target.path);
      } on FileSystemException {
        // A concurrent put of the same cover may have won the race.
        if (tmp.existsSync()) tmp.deleteSync();
        if (target.existsSync()) return ref;
        rethrow;
      }
      return ref;
    } on FileSystemException catch (e, s) {
      AppLog.w('ArtCache.put failed', e, s);
      return null;
    } catch (e, s) {
      AppLog.w('ArtCache.put failed unexpectedly', e, s);
      return null;
    }
  }
}

Uint8List? _toJpeg(Uint8List bytes, bool squareCrop) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = decoded;
  // A 4:3 image (YouTube's sddefault) carries black letterbox bars: keep the
  // centre 16:9 band before the square crop.
  if (squareCrop && (image.width / image.height - 4 / 3).abs() < 0.02) {
    final bandHeight = (image.width * 9 / 16).round();
    image = img.copyCrop(
      image,
      x: 0,
      y: (image.height - bandHeight) ~/ 2,
      width: image.width,
      height: bandHeight,
    );
  }
  if (squareCrop && image.width != image.height) {
    final side = math.min(image.width, image.height);
    image = img.copyCrop(
      image,
      x: (image.width - side) ~/ 2,
      y: (image.height - side) ~/ 2,
      width: side,
      height: side,
    );
  }
  final longest = math.max(image.width, image.height);
  if (longest > ArtCache.maxSide) {
    final scale = ArtCache.maxSide / longest;
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(image, quality: ArtCache.jpegQuality),
  );
}
