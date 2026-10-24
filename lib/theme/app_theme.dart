import 'package:flutter/material.dart';

import 'contrast.dart';
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
    required this.nowPlayingTop,
    required this.nowPlayingBottom,
    required this.radius,
    required this.fontFamily,
    required this.blurNowPlaying,
  });

  /// The colours of [spec] with its own accent. [fontFamily] is the family
  /// the theme renders with (see `FontService.resolveFamily`), by default the
  /// spec's. Text that misses 4.5:1 on the background falls back to white or
  /// black.
  factory SongiesColors.fromSpec(ThemeSpec spec, {String? fontFamily}) {
    final accent = spec.accent;
    final glow = accent.withValues(alpha: spec.glowStrength);
    return SongiesColors(
      background: spec.background,
      surface: spec.surface,
      text: readableOn(spec.background, preferred: spec.text),
      mutedText: spec.mutedText,
      accent: accent,
      glow: glow,
      miniPlayer: Color.alphaBlend(
        accent.withValues(alpha: 0.25),
        spec.surface,
      ),
      // A cover-following theme tops it with the darkened accent (the cover's
      // dominant colour once known); the others keep the soft glow fading
      // into the background.
      nowPlayingTop: spec.followCover
          ? darken(accent)
          : Color.alphaBlend(glow, spec.background),
      nowPlayingBottom: spec.background,
      radius: spec.cornerRadius,
      fontFamily: fontFamily ?? spec.fontFamily,
      blurNowPlaying: spec.blurNowPlaying,
    );
  }

  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color accent;

  /// The header glow: the accent at `glowStrength` opacity.
  final Color glow;

  /// The mini-player tint: the accent blended over the surface.
  final Color miniPlayer;

  /// The Now Playing gradient, top to bottom.
  final Color nowPlayingTop;
  final Color nowPlayingBottom;
  final double radius;
  final String fontFamily;
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
    Color? nowPlayingTop,
    Color? nowPlayingBottom,
    double? radius,
    String? fontFamily,
    bool? blurNowPlaying,
  }) => SongiesColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    mutedText: mutedText ?? this.mutedText,
    accent: accent ?? this.accent,
    glow: glow ?? this.glow,
    miniPlayer: miniPlayer ?? this.miniPlayer,
    nowPlayingTop: nowPlayingTop ?? this.nowPlayingTop,
    nowPlayingBottom: nowPlayingBottom ?? this.nowPlayingBottom,
    radius: radius ?? this.radius,
    fontFamily: fontFamily ?? this.fontFamily,
    blurNowPlaying: blurNowPlaying ?? this.blurNowPlaying,
  );

  /// Interpolates every colour and [radius]; [fontFamily] and
  /// [blurNowPlaying] switch at t = 0.5.
  @override
  SongiesColors lerp(ThemeExtension<SongiesColors>? other, double t) {
    if (other is! SongiesColors) return this;
    final second = t >= 0.5;
    return SongiesColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      miniPlayer: Color.lerp(miniPlayer, other.miniPlayer, t)!,
      nowPlayingTop: Color.lerp(nowPlayingTop, other.nowPlayingTop, t)!,
      nowPlayingBottom: Color.lerp(
        nowPlayingBottom,
        other.nowPlayingBottom,
        t,
      )!,
      radius: radius + (other.radius - radius) * t,
      fontFamily: second ? other.fontFamily : fontFamily,
      blurNowPlaying: second ? other.blurNowPlaying : blurNowPlaying,
    );
  }

  // Value equality, so an unchanged theme never restarts the theme animation.
  @override
  bool operator ==(Object other) =>
      other is SongiesColors &&
      other.background == background &&
      other.surface == surface &&
      other.text == text &&
      other.mutedText == mutedText &&
      other.accent == accent &&
      other.glow == glow &&
      other.miniPlayer == miniPlayer &&
      other.nowPlayingTop == nowPlayingTop &&
      other.nowPlayingBottom == nowPlayingBottom &&
      other.radius == radius &&
      other.fontFamily == fontFamily &&
      other.blurNowPlaying == blurNowPlaying;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    text,
    mutedText,
    accent,
    glow,
    miniPlayer,
    nowPlayingTop,
    nowPlayingBottom,
    radius,
    fontFamily,
    blurNowPlaying,
  );
}

/// [c] darkened by [amount] (0..1) towards black; used for the top of the
/// Now Playing gradient.
Color darken(Color c, [double amount = 0.55]) =>
    Color.lerp(c, const Color(0xFF000000), amount)!;

/// Builds the [ThemeData] for [spec] (light for the light base, else dark),
/// from [colors] when given (e.g. cover-derived ones), else from the spec
/// alone. Font sizes are not scaled here: `fontScale` goes through
/// `MediaQuery.textScaler`.
ThemeData buildThemeData(ThemeSpec spec, {SongiesColors? colors}) {
  final c = colors ?? SongiesColors.fromSpec(spec);
  final brightness = spec.base == 'light' ? Brightness.light : Brightness.dark;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: readableOn(c.accent, preferred: c.background),
        surface: c.surface,
        onSurface: readableOn(c.surface, preferred: c.text),
        onSurfaceVariant: c.mutedText,
      );

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: c.fontFamily,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    extensions: [c],
  );

  // A raw ThemeData has no font sizes until MaterialApp localizes it, so merge
  // the English-like geometry in first.
  final geometry = Typography.material2021().geometryThemeFor(
    ScriptCategory.englishLike,
  );
  return base.copyWith(
    textTheme: base.textTheme
        .merge(geometry)
        .apply(
          bodyColor: c.text,
          displayColor: c.text,
          fontFamily: c.fontFamily,
        ),
  );
}
