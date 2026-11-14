import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/settings/settings_categories.dart';

void main() {
  test('categories come in order, addressed by their slug', () {
    expect(
      [for (final c in SettingsCategory.values) c.slug],
      [
        'library',
        'playback',
        'youtube',
        'appearance',
        'privacy',
        'discord',
        'about',
      ],
    );
  });

  test('a slug finds its category; none or an unknown one is Library', () {
    expect(settingsCategoryFromSlug('youtube'), SettingsCategory.youtube);
    expect(settingsCategoryFromSlug(null), SettingsCategory.library);
    expect(settingsCategoryFromSlug('nope'), SettingsCategory.library);
  });

  test('Discord is listed only where Discord status works', () {
    expect(
      visibleSettingsCategories(discordSupported: true),
      SettingsCategory.values,
    );
    expect(
      visibleSettingsCategories(discordSupported: false),
      isNot(contains(SettingsCategory.discord)),
    );
    expect(visibleSettingsCategories(discordSupported: false), hasLength(6));
  });

  test('every category has a title, a line and sections', () {
    for (final c in SettingsCategory.values) {
      expect(c.title, isNotEmpty);
      expect(c.line, isNotEmpty);
      expect(c.sections, isNotEmpty);
    }
  });
}
