import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/theme_spec.dart';

void main() {
  group('ThemeSpec.builtInDefault', () {
    test('has the documented default values', () {
      const d = ThemeSpec.builtInDefault;
      expect(d.base, 'charcoal');
      expect(d.background, const Color(0xFF121212));
      expect(d.surface, const Color(0xFF2A2A2A));
      expect(d.text, const Color(0xFFFFFFFF));
      expect(d.mutedText, const Color(0xFFA7A7A7));
      expect(d.accent, const Color(0xFF1DB954));
      expect(d.followCover, false);
      expect(d.glowStrength, 0.4);
      expect(d.cornerRadius, 6);
      expect(d.fontFamily, 'Inter');
      expect(d.fontFileHash, isNull);
      expect(d.fontScale, 1.0);
      expect(d.blurNowPlaying, true);
    });
  });

  group('JSON', () {
    test('round-trips with value equality', () {
      const x = ThemeSpec.builtInDefault;
      final back = ThemeSpec.fromJson(x.toJson());
      expect(back, x);
      expect(back.hashCode, x.hashCode);
    });

    test('round-trips through a real JSON string', () {
      final x = ThemeSpec.builtInDefault.copyWith(
        fontFileHash: 'abc',
        accent: const Color(0x80112233),
      );
      final json = x.toJson();
      expect(json['accent'], '#80112233');
      expect(json['background'], '#121212');
      // Loading makes the colour opaque (see 'every colour loads opaque').
      expect(
        ThemeSpec.fromJson(json),
        x.copyWith(accent: const Color(0xFF112233)),
      );
    });

    test('uses exactly the spec keys (mutedText is derived, not stored)', () {
      expect(ThemeSpec.builtInDefault.toJson().keys.toSet(), {
        'base',
        'background',
        'surface',
        'text',
        'accent',
        'followCover',
        'glowStrength',
        'cornerRadius',
        'fontFamily',
        'fontFileHash',
        'fontScale',
        'blurNowPlaying',
      });
    });

    test(
      'an old row with mutedText still loads; the stored value is ignored',
      () {
        final json = ThemeSpec.builtInDefault.toJson()
          ..['mutedText'] = '#123456';
        final back = ThemeSpec.fromJson(json);
        expect(back, ThemeSpec.builtInDefault);
        expect(back.mutedText, const Color(0xFFA7A7A7));
      },
    );

    test('mutedText is derived from text and background', () {
      final light = ThemeSpec.builtInDefault.copyWith(
        base: 'light',
        background: const Color(0xFFF5F5F5),
        text: const Color(0xFF121212),
      );
      expect(light.mutedText, isNot(ThemeSpec.builtInDefault.mutedText));
      // Between the text and the background, nearer the text.
      final lum = light.mutedText.computeLuminance();
      expect(lum, greaterThan(light.text.computeLuminance()));
      expect(lum, lessThan(light.background.computeLuminance()));
    });

    test('a missing accent throws FormatException', () {
      final json = ThemeSpec.builtInDefault.toJson()..remove('accent');
      expect(() => ThemeSpec.fromJson(json), throwsFormatException);
    });

    test('a malformed colour throws FormatException', () {
      final json = ThemeSpec.builtInDefault.toJson()..['accent'] = 'green';
      expect(() => ThemeSpec.fromJson(json), throwsFormatException);
    });

    test('a wrongly typed value throws FormatException', () {
      final json = ThemeSpec.builtInDefault.toJson()..['cornerRadius'] = 'x';
      expect(() => ThemeSpec.fromJson(json), throwsFormatException);
    });

    test('out-of-range numbers are clamped on load', () {
      final high = ThemeSpec.fromJson(
        ThemeSpec.builtInDefault.toJson()
          ..['glowStrength'] = 3
          ..['cornerRadius'] = 99
          ..['fontScale'] = 4,
      );
      expect(high.glowStrength, 1);
      expect(high.cornerRadius, 24);
      expect(high.fontScale, 1.3);
      final low = ThemeSpec.fromJson(
        ThemeSpec.builtInDefault.toJson()
          ..['glowStrength'] = -1
          ..['cornerRadius'] = -5
          ..['fontScale'] = 0.1,
      );
      expect(low.glowStrength, 0);
      expect(low.cornerRadius, 0);
      expect(low.fontScale, 0.85);
    });

    test('every colour loads fully opaque', () {
      final spec = ThemeSpec.fromJson(
        ThemeSpec.builtInDefault.toJson()
          ..['background'] = '#00121212'
          ..['surface'] = '#802a2a2a'
          ..['text'] = '#00ffffff'
          ..['accent'] = '#101db954',
      );
      expect(spec.background, const Color(0xFF121212));
      expect(spec.surface, const Color(0xFF2A2A2A));
      expect(spec.text, const Color(0xFFFFFFFF));
      expect(spec.accent, const Color(0xFF1DB954));
    });

    test('a missing fontFileHash is allowed', () {
      final json = ThemeSpec.builtInDefault.toJson()..remove('fontFileHash');
      expect(ThemeSpec.fromJson(json).fontFileHash, isNull);
    });
  });
}
