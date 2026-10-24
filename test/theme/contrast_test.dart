import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/contrast.dart';

void main() {
  const bg = Color(0xFF121212);
  test('white on #121212 passes AA', () {
    expect(contrastRatio(const Color(0xFFFFFFFF), bg), greaterThan(4.5));
  });
  test('contrast ratio of black on white is 21', () {
    expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01));
  });
  test('readableOn keeps a passing preferred colour', () {
    const pref = Color(0xFFEEEEEE);
    expect(readableOn(bg, preferred: pref), pref);
  });
  test('#1db954 on white falls back to black', () {
    expect(
        readableOn(const Color(0xFFFFFFFF), preferred: const Color(0xFF1DB954)),
        const Color(0xFF000000));
  });
  test('ensureAccentContrast lifts a dark accent to 3:1', () {
    final c = ensureAccentContrast(const Color(0xFF202020), bg);
    expect(contrastRatio(c, bg), greaterThanOrEqualTo(3));
  });
  test('ensureAccentContrast leaves a passing accent alone', () {
    const a = Color(0xFF1DB954);
    expect(ensureAccentContrast(a, bg), a);
  });
  test('ensureAccentContrast darkens on a light background', () {
    final c = ensureAccentContrast(
        const Color(0xFFE0E0E0), const Color(0xFFFFFFFF));
    expect(contrastRatio(c, const Color(0xFFFFFFFF)), greaterThanOrEqualTo(3));
  });
}
