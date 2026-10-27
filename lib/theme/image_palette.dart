import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/log.dart';
import 'cover_palette.dart';

/// The [CoverPalette] of the image [provider] shows, resolved through
/// Flutter's image cache: an image already on screen is neither fetched nor
/// decoded again, and nothing is written to the art cache. Null when the
/// image cannot be loaded or read. Never throws.
Future<CoverPalette?> paletteOfImage(
  ImageProvider provider, {
  Future<CoverPalette?> Function(Uint8List rgba, int width, int height)?
  extract,
}) async {
  final loaded = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) {
      if (!loaded.isCompleted) loaded.complete(info.image.clone());
      info.dispose();
    },
    onError: (e, s) {
      if (!loaded.isCompleted) loaded.complete(null);
    },
  );
  stream.addListener(listener);
  final image = await loaded.future;
  stream.removeListener(listener);
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final w = image.width;
    final h = image.height;
    return await (extract ??
        (rgba, w, h) => Isolate.run(
          () => extractCoverPaletteFromRgba(rgba, w, h),
        ))(rgba, w, h);
  } catch (e, s) {
    AppLog.w('Palette of a shown image failed', e, s);
    return null;
  } finally {
    image.dispose();
  }
}
