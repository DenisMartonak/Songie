import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Takes screenshots of the app's window from inside the app (the root
/// layer turned into an image), so it works on Wayland with nothing to
/// install. tool/showcase.sh turns them into WebP for the website.
///
/// Video was tried first and dropped: grabbing frames from a debug build
/// can't keep up, and the clips came out choppy.
class FrameRecorder {
  FrameRecorder(this.out);

  final Directory out;

  /// Saves one screenshot as `<out>/<scene>/<name>.png`, at twice the
  /// window's logical size so it stays sharp on high-density screens.
  Future<void> shot(String scene, String name) async {
    final image = await _grab(scale: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await Directory('${out.path}/$scene').create(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
  }

  /// The window as last drawn, at [scale] times its logical size. The root
  /// layer scales by the device pixel ratio, so the bounds are physical and
  /// the image ratio undoes it.
  Future<ui.Image> _grab({double scale = 1}) {
    final view = RendererBinding.instance.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final dpr = view.flutterView.devicePixelRatio;
    final physical = view.size * dpr;
    return layer.toImage(Offset.zero & physical, pixelRatio: scale / dpr);
  }
}
