import 'package:flutter/material.dart';

/// A rounded slider track that always spans the slider's full width.
/// [RoundedRectSliderTrackShape] insets the track by half the thumb's width,
/// so a thumb that appears on hover or press would shorten the bar.
class SteadyTrackShape extends RoundedRectSliderTrackShape {
  const SteadyTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 4;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }
}
