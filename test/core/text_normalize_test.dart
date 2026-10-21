import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/text_normalize.dart';

void main() {
  test('lowercases and folds diacritics', () {
    expect(
      normalizeForSearch('Beyoncé – Ünïcødé  Song'),
      'beyonce – unicode song',
    );
  });
  test('collapses whitespace and trims', () {
    expect(normalizeForSearch('  A\t\nB  '), 'a b');
  });
  test('expands ligatures and sharp s', () {
    expect(normalizeForSearch('Straße Æon'), 'strasse aeon');
  });
}
