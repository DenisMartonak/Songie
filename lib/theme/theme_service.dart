import 'package:flutter/widgets.dart';

import 'app_theme.dart';
import 'contrast.dart';
import 'cover_palette.dart';
import 'theme_spec.dart';

/// The app's colours for [spec]. When the theme follows the cover and
/// [palette] is a real (non-fallback) one, the accent, glow, tint and Now
/// Playing gradient come from the cover; otherwise from the theme's own
/// accent. [fontFamily] is the resolved family (defaults to the spec's).
SongiesColors songiesColorsFor(
  ThemeSpec spec, {
  CoverPalette? palette,
  String? fontFamily,
}) {
  final own = SongiesColors.fromSpec(spec, fontFamily: fontFamily);
  if (!spec.followCover || palette == null || palette.isFallback) return own;
  final vibrant = palette.vibrant;
  return own.copyWith(
    accent: ensureAccentContrast(vibrant, spec.background),
    glow: vibrant.withValues(alpha: spec.glowStrength),
    miniPlayer: Color.alphaBlend(vibrant.withValues(alpha: 0.3), spec.surface),
    nowPlayingTop: darken(palette.dominant),
  );
}

/// [base] with every size multiplied by [factor] (the theme's `fontScale`),
/// so the user's system text scaling is kept.
TextScaler scaleText(TextScaler base, double factor) =>
    factor == 1 ? base : _ScaledTextScaler(base, factor);

class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
