import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/widgets/steady_track_shape.dart';

Widget slider(double radius, double value, SliderTrackShape shape) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: RepaintBoundary(
            key: const Key('rb'),
            child: SizedBox(
              width: 300,
              height: 32,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white,
                  thumbColor: Colors.red,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: radius,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: shape,
                ),
                child: Slider(value: value, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );

/// The first and last x of the white track on the middle row.
Future<String> span(WidgetTester tester) async {
  final rb = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('rb')),
  );
  late String out;
  await tester.runAsync(() async {
    final img = await rb.toImage();
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final cols = <String>[];
    final y = img.height ~/ 2;
    var first = -1, last = -1;
    for (var x = 0; x < img.width; x++) {
      final i = (y * img.width + x) * 4;
      if (data.getUint8(i) > 128 && data.getUint8(i + 1) > 128) {
        if (first < 0) first = x;
        last = x;
      }
    }
    cols.add('$first..$last');
    out = cols.join(' ');
  });
  return out;
}

void main() {
  Future<String> pressedSpan(
    WidgetTester tester,
    double radius,
    SliderTrackShape shape,
  ) async {
    await tester.pumpWidget(slider(radius, 0.5, shape));
    final g = await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await tester.pump(const Duration(milliseconds: 500));
    final s = await span(tester);
    await g.up();
    await tester.pump();
    return s;
  }

  testWidgets('the track keeps its full length when the thumb appears', (
    tester,
  ) async {
    expect(await pressedSpan(tester, 0, const SteadyTrackShape()), '0..299');
    expect(await pressedSpan(tester, 8, const SteadyTrackShape()), '0..299');
  });

  testWidgets('the stock rounded track would shorten (why this shape exists)', (
    tester,
  ) async {
    expect(
      await pressedSpan(tester, 8, const RoundedRectSliderTrackShape()),
      isNot('0..299'),
    );
  });
}
