import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Records the app's window from inside the app: the root layer is turned
/// into an image [fps] times a second and written as raw RGBA frames to
/// `<out>/<scene>/frames.rgba`, with `meta.json` beside it. tool/showcase.sh
/// encodes them with ffmpeg. Frames that take too long to grab are filled
/// with copies of the last one, so the clip keeps real time.
class FrameRecorder {
  FrameRecorder(this.out, {this.fps = 24});

  final Directory out;
  final int fps;

  bool _running = false;
  Future<void>? _loop;
  String? _scene;

  /// Starts recording [scene].
  void start(String scene) {
    assert(!_running, 'already recording $_scene');
    _scene = scene;
    _running = true;
    _loop = _record(Directory('${out.path}/$scene'));
  }

  /// Stops recording and finishes the files.
  Future<void> stop() async {
    _running = false;
    await _loop;
    _loop = null;
  }

  /// Saves one screenshot as `<out>/<scene>/<name>.png`.
  Future<void> shot(String scene, String name) async {
    final image = await _grab();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await Directory('${out.path}/$scene').create(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
  }

  Future<void> _record(Directory dir) async {
    await dir.create(recursive: true);
    final file = await File('${dir.path}/frames.rgba').open(mode: FileMode.write);
    final frameTime = Duration(microseconds: 1000000 ~/ fps);
    final clock = Stopwatch()..start();
    var written = 0;
    var width = 0, height = 0;
    Uint8List? last;
    try {
      while (_running) {
        final image = await _grab();
        width = image.width;
        height = image.height;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        last = data!.buffer.asUint8List();
        // Every frame due by now: this one, plus copies for any we missed.
        final due = clock.elapsed.inMicroseconds ~/ frameTime.inMicroseconds + 1;
        while (written < due) {
          await file.writeFrom(last);
          written++;
        }
        final next = frameTime * written - clock.elapsed;
        if (next > Duration.zero) await Future<void>.delayed(next);
      }
    } finally {
      await file.close();
      await File('${dir.path}/meta.json').writeAsString(
        jsonEncode({'width': width, 'height': height, 'fps': fps, 'frames': written}),
      );
    }
  }

  /// The window as last drawn, at logical size. The root layer scales by
  /// the device pixel ratio, so the bounds are physical and the image ratio
  /// undoes it.
  Future<ui.Image> _grab() {
    final view = RendererBinding.instance.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final dpr = view.flutterView.devicePixelRatio;
    final physical = view.size * dpr;
    return layer.toImage(Offset.zero & physical, pixelRatio: 1 / dpr);
  }
}
