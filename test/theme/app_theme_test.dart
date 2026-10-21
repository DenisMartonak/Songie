import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/app_theme.dart';
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

  test('fontScale scales text sizes', () {
    final base = buildThemeData(ThemeSpec.builtInDefault);
    final big = buildThemeData(
      ThemeSpec.builtInDefault.copyWith(fontScale: 1.5),
    );
    expect(
      big.textTheme.bodyMedium!.fontSize,
      closeTo(base.textTheme.bodyMedium!.fontSize! * 1.5, 0.001),
    );
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
