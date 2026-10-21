import 'package:flutter/material.dart';

import 'theme_spec.dart';

/// Colours and shape values the app's own widgets read from the theme.
class SongiesColors extends ThemeExtension<SongiesColors> {
  const SongiesColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.glow,
    required this.miniPlayer,
    required this.radius,
    required this.blurNowPlaying,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color accent;

  /// The accent at `glowStrength` opacity.
  final Color glow;

  /// The mini-player fill: the accent at 25% over the surface.
  final Color miniPlayer;
  final double radius;
  final bool blurNowPlaying;

  @override
  SongiesColors copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? mutedText,
    Color? accent,
    Color? glow,
    Color? miniPlayer,
    double? radius,
    bool? blurNowPlaying,
  }) => SongiesColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    mutedText: mutedText ?? this.mutedText,
    accent: accent ?? this.accent,
    glow: glow ?? this.glow,
    miniPlayer: miniPlayer ?? this.miniPlayer,
    radius: radius ?? this.radius,
    blurNowPlaying: blurNowPlaying ?? this.blurNowPlaying,
  );

  @override
  SongiesColors lerp(ThemeExtension<SongiesColors>? other, double t) {
    if (other is! SongiesColors) return this;
    return SongiesColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      miniPlayer: Color.lerp(miniPlayer, other.miniPlayer, t)!,
      radius: radius + (other.radius - radius) * t,
      blurNowPlaying: t < 0.5 ? blurNowPlaying : other.blurNowPlaying,
    );
  }
}

/// Builds the dark [ThemeData] for [spec].
ThemeData buildThemeData(ThemeSpec spec) {
  final colors = SongiesColors(
    background: spec.background,
    surface: spec.surface,
    text: spec.text,
    mutedText: spec.mutedText,
    accent: spec.accent,
    glow: spec.accent.withValues(alpha: spec.glowStrength),
    miniPlayer: Color.alphaBlend(
      spec.accent.withValues(alpha: 0.25),
      spec.surface,
    ),
    radius: spec.cornerRadius,
    blurNowPlaying: spec.blurNowPlaying,
  );

  final scheme =
      ColorScheme.fromSeed(
        seedColor: spec.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: spec.accent,
        onPrimary: spec.background,
        surface: spec.surface,
        onSurface: spec.text,
        onSurfaceVariant: spec.mutedText,
      );

  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: spec.fontFamily,
    scaffoldBackgroundColor: spec.background,
    canvasColor: spec.background,
    extensions: [colors],
  );

  // A raw ThemeData has no font sizes until MaterialApp localizes it, so merge
  // the English-like geometry in first; only then can sizes be scaled.
  final geometry = Typography.material2021().geometryThemeFor(
    ScriptCategory.englishLike,
  );
  return base.copyWith(
    textTheme: base.textTheme
        .merge(geometry)
        .apply(
          bodyColor: spec.text,
          displayColor: spec.text,
          fontFamily: spec.fontFamily,
        )
        .apply(fontSizeFactor: spec.fontScale),
  );
}
