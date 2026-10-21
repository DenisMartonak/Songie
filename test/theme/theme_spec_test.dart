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
      expect(ThemeSpec.fromJson(json), x);
    });

    test('uses the spec keys plus mutedText', () {
      expect(ThemeSpec.builtInDefault.toJson().keys.toSet(), {
        'base',
        'background',
        'surface',
        'text',
        'mutedText',
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

    test('a missing fontFileHash is allowed', () {
      final json = ThemeSpec.builtInDefault.toJson()..remove('fontFileHash');
      expect(ThemeSpec.fromJson(json).fontFileHash, isNull);
    });
  });
}
