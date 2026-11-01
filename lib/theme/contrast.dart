import 'dart:math' as math;
import 'dart:ui';

import 'package:material_color_utilities/material_color_utilities.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 2 contrast ratio between [a] and [b], from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [preferred] if it reaches 4.5:1 on [bg], otherwise white or black,
/// whichever contrasts more.
Color readableOn(Color bg, {Color preferred = _white}) {
  if (contrastRatio(preferred, bg) >= 4.5) return preferred;
  return contrastRatio(_white, bg) >= contrastRatio(_black, bg)
      ? _white
      : _black;
}

// Luminance where white and black contrast equally; darker backgrounds
// take lighter accents, lighter ones darker accents.
const double _neutralLuminance = 0.179;

/// Moves [accent] in HCT tone (hue and chroma kept) until it reaches 3:1
/// against [bg]. Moves away from the background's lightness; if that cannot
/// reach 3:1, tries the other direction, then returns the best attempt.
Color ensureAccentContrast(Color accent, Color bg) {
  if (contrastRatio(accent, bg) >= 3) return accent;
  final hct = Hct.fromInt(accent.toARGB32());
  final lighter = _luminance(bg) < _neutralLuminance;
  Color? best;
  for (final up in [lighter, !lighter]) {
    for (var t = hct.tone; up ? t <= 100 : t >= 0; t += up ? 1 : -1) {
      final c = Color(Hct.from(hct.hue, hct.chroma, t).toInt());
      if (contrastRatio(c, bg) >= 3) return c;
    }
    final end = Color(Hct.from(hct.hue, hct.chroma, up ? 100 : 0).toInt());
    if (best == null || contrastRatio(end, bg) > contrastRatio(best, bg)) {
      best = end;
    }
  }
  return best!;
}
