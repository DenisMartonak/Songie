import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/theme_spec.dart';

void main() {
  test('default theme exposes SongiesColors and a charcoal scaffold', () {
    final theme = buildThemeData(ThemeSpec.builtInDefault);
    final c = theme.extension<SongiesColors>()!;
    expect(c.radius, 6);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF121212));
    expect(theme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(c.background, const Color(0xFF121212));
    expect(c.surface, const Color(0xFF2A2A2A));
    expect(c.text, const Color(0xFFFFFFFF));
    expect(c.mutedText, const Color(0xFFA7A7A7));
    expect(c.accent, const Color(0xFF1DB954));
    expect(c.blurNowPlaying, true);
  });

  test('glow is the accent at glowStrength opacity', () {
    final c = buildThemeData(ThemeSpec.builtInDefault)
        .extension<SongiesColors>()!;
    expect(c.glow, c.accent.withValues(alpha: 0.4));
  });

  test('miniPlayer is the accent at 25% blended over the surface', () {
    final c = buildThemeData(ThemeSpec.builtInDefault)
        .extension<SongiesColors>()!;
    expect(
      c.miniPlayer,
      Color.alphaBlend(c.accent.withValues(alpha: 0.25), c.surface),
    );
  });

  test('fontScale is left to the text scaler, not baked into sizes', () {
    final base = buildThemeData(ThemeSpec.builtInDefault);
    final big = buildThemeData(
      ThemeSpec.builtInDefault.copyWith(fontScale: 1.5),
    );
    expect(
      big.textTheme.bodyMedium!.fontSize,
      base.textTheme.bodyMedium!.fontSize,
    );
  });

  test('text that fails 4.5:1 on the background falls back to white', () {
    final c = SongiesColors.fromSpec(
      ThemeSpec.builtInDefault.copyWith(text: const Color(0xFF333333)),
    );
    expect(c.text, const Color(0xFFFFFFFF));
    final theme = buildThemeData(
      ThemeSpec.builtInDefault.copyWith(text: const Color(0xFF333333)),
    );
    expect(theme.textTheme.bodyMedium!.color, const Color(0xFFFFFFFF));
  });

  test('onPrimary is readable on the accent', () {
    final theme = buildThemeData(
      ThemeSpec.builtInDefault.copyWith(accent: const Color(0xFFFFEB3B)),
    );
    expect(
      contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('the resolved font family drives the text theme', () {
    final colors = SongiesColors.fromSpec(
      ThemeSpec.builtInDefault.copyWith(fontFamily: 'Missing Font'),
      fontFamily: 'Inter',
    );
    final theme = buildThemeData(ThemeSpec.builtInDefault, colors: colors);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(theme.extension<SongiesColors>()!.fontFamily, 'Inter');
  });

  group('lerp', () {
    final a = SongiesColors.fromSpec(ThemeSpec.builtInDefault);
    final b = SongiesColors.fromSpec(ThemeSpec.terminal)
        .copyWith(blurNowPlaying: false);

    test('at 0 is the start and at 1 the end', () {
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
    });

    test('at 0.5 every colour and the radius lie halfway', () {
      final m = a.lerp(b, 0.5);
      expect(m.background, Color.lerp(a.background, b.background, 0.5));
      expect(m.surface, Color.lerp(a.surface, b.surface, 0.5));
      expect(m.text, Color.lerp(a.text, b.text, 0.5));
      expect(m.mutedText, Color.lerp(a.mutedText, b.mutedText, 0.5));
      expect(m.accent, Color.lerp(a.accent, b.accent, 0.5));
      expect(m.glow, Color.lerp(a.glow, b.glow, 0.5));
      expect(m.miniPlayer, Color.lerp(a.miniPlayer, b.miniPlayer, 0.5));
      expect(
        m.nowPlayingTop,
        Color.lerp(a.nowPlayingTop, b.nowPlayingTop, 0.5),
      );
      expect(
        m.nowPlayingBottom,
        Color.lerp(a.nowPlayingBottom, b.nowPlayingBottom, 0.5),
      );
      expect(m.radius, 3);
    });

    test('fontFamily and blurNowPlaying switch at 0.5', () {
      expect(a.lerp(b, 0.49).fontFamily, 'Inter');
      expect(a.lerp(b, 0.49).blurNowPlaying, isTrue);
      expect(a.lerp(b, 0.5).fontFamily, 'JetBrains Mono');
      expect(a.lerp(b, 0.5).blurNowPlaying, isFalse);
    });
  });

  test('spec colours and font drive the theme', () {
    final spec = ThemeSpec.builtInDefault.copyWith(
      background: const Color(0xFF000000),
      fontFamily: 'Outfit',
      cornerRadius: 12,
    );
    final theme = buildThemeData(spec);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Outfit');
    expect(theme.extension<SongiesColors>()!.radius, 12);
  });
}
