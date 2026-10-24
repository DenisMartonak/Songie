import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/settings/themes/theme_editor_page.dart';
import 'package:songies/ui/settings/themes/themes_page.dart';

import '../../../helpers/ui_harness.dart';
import 'theme_test_harness.dart';

void main() {
  late ThemeHarness t;

  setUp(() async => t = await ThemeHarness.create());
  tearDown(() => t.dispose());

  String editLocation(String id) =>
      '/settings/themes/edit/${Uri.encodeComponent(id)}';

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ThemeEditorPage)));

  BorderRadiusGeometry? previewRadius(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(const Key('themePreview.tile')).first,
    );
    return (box.decoration as BoxDecoration).borderRadius;
  }

  Future<void> dragRadiusToMax(WidgetTester tester) async {
    final slider = find.byKey(const Key('themeEditor.radius'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(2000, 0));
    await settle(tester);
  }

  Future<void> setHex(WidgetTester tester, String field, String hex) async {
    final header = find.byKey(Key('themeEditor.colour.$field'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await settle(tester);
    final hexField = find.descendant(
      of: find.byKey(Key('themeEditor.colourField.$field')),
      matching: find.byKey(const Key('colourField.hex')),
    );
    await tester.ensureVisible(hexField);
    await tester.enterText(hexField, hex);
    await settle(tester);
  }

  Future<ThemeEntry> active(WidgetTester tester) =>
      real(tester, () => t.themes.watchActive().first);

  Future<List<ThemeEntry>> saved(WidgetTester tester) async => [
    for (final e in await real(tester, () => t.themes.watchAll().first))
      if (!e.builtIn) e,
  ];

  uiTest('the radius slider changes the preview but not the app', (
    tester,
  ) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    final before = container(tester).read(songiesColorsProvider);
    expect(previewRadius(tester), BorderRadius.circular(6));

    await dragRadiusToMax(tester);

    expect(previewRadius(tester), BorderRadius.circular(24));
    expect(container(tester).read(songiesColorsProvider), before);
    expect(container(tester).read(songiesColorsProvider).radius, 6);
    expect(await saved(tester), isEmpty);
  });

  uiTest('editing Default and saving makes an active "Default copy"', (
    tester,
  ) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    await dragRadiusToMax(tester);

    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);

    final copies = await saved(tester);
    expect(copies.map((e) => e.name), ['Default copy']);
    expect(copies.single.spec.cornerRadius, 24);
    expect((await active(tester)).id, copies.single.id);
    // Back on the Themes page.
    expect(find.byType(ThemesPage), findsOneWidget);
    expect(find.byType(ThemeEditorPage), findsNothing);
  });

  uiTest('saving a saved theme updates it in place', (tester) async {
    final id = await real(
      tester,
      () async => (await t.themes.save(
        null,
        'Mine',
        ThemeSpec.builtInDefault,
      ) as Ok<String>).value,
    );
    await t.pump(tester, location: editLocation(id));
    await dragRadiusToMax(tester);
    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);

    final all = await saved(tester);
    expect(all.map((e) => (e.id, e.name)), [(id, 'Mine')]);
    expect(all.single.spec.cornerRadius, 24);
    expect((await active(tester)).id, id);
  });

  uiTest('Cancel with changes asks to discard them', (tester) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    await dragRadiusToMax(tester);

    await tester.tap(find.byKey(const Key('themeEditor.cancel')));
    await settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsOneWidget);
    expect(previewRadius(tester), BorderRadius.circular(24));

    await tester.tap(find.byKey(const Key('themeEditor.cancel')));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsNothing);
    expect(await saved(tester), isEmpty);
  });

  uiTest('Back with changes asks too; without changes it just leaves', (
    tester,
  ) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    await tester.tap(find.byKey(const Key('themeEditor.back')));
    await settle(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(ThemeEditorPage), findsNothing);

    await tester.tap(find.byKey(const Key('themes.new')));
    await settle(tester);
    await dragRadiusToMax(tester);
    await tester.tap(find.byKey(const Key('themeEditor.back')));
    await settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
  });

  uiTest('warns when text on the background is below 4.5:1', (tester) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    expect(find.text('Text may be hard to read'), findsNothing);

    await setHex(tester, 'text', '777777');
    await setHex(tester, 'background', '888888');

    expect(find.text('Text may be hard to read'), findsOneWidget);
  });

  uiTest('choosing a base resets the colours to its defaults', (tester) async {
    await t.pump(tester, location: editLocation(kDefaultThemeId));
    await setHex(tester, 'background', '888888');
    await tester.tap(find.text('Light'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);

    final spec = (await saved(tester)).single.spec;
    expect(spec.base, 'light');
    expect(spec.background, editorBaseColours['light']!.background);
    expect(spec.text, editorBaseColours['light']!.text);
  });

  uiTest('Import font… imports through FontService and selects it', (
    tester,
  ) async {
    final path = await real(tester, () async {
      final src = 'assets/fonts/Outfit-Regular.ttf';
      final dest = '${t.tmp.path}/Fancy Sans.ttf';
      await File(src).copy(dest);
      // Two rows synced from other devices that share the family name: one
      // for another file, one for this very file.
      final hash = sha256.convert(await File(dest).readAsBytes()).toString();
      for (final fileHash in ['synced-elsewhere', hash]) {
        final s = await t.h.stamp.next();
        await t.h.db
            .into(t.h.db.fonts)
            .insert(
              FontsCompanion.insert(
                id: s.id,
                clock: s.clock,
                originDevice: s.originDevice,
                localSeq: s.localSeq,
                family: 'Fancy Sans',
                fileHash: fileHash,
                ext: 'ttf',
              ),
            );
      }
      return dest;
    });
    await t.pump(
      tester,
      location: editLocation(kDefaultThemeId),
      extraOverrides: [
        fontFilePickerProvider.overrideWithValue(() async => path),
      ],
    );
    final font = find.byKey(const Key('themeEditor.font'));
    await tester.ensureVisible(font);
    await tester.tap(font);
    await settle(tester);
    await tester.tap(find.text('Import font…').last);
    // Importing reads, hashes and copies the file: many real-clock turns.
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }

    expect(find.text('Fancy Sans'), findsWidgets);
    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);
    final spec = (await saved(tester)).single.spec;
    expect(spec.fontFamily, 'Fancy Sans');
    // The imported file's own hash, not the other row's with that family.
    final bytes = await real(tester, () => File(path).readAsBytes());
    expect(spec.fontFileHash, sha256.convert(bytes).toString());
  });

  uiTest('a failure to apply the saved theme says so and keeps Save usable', (
    tester,
  ) async {
    await t.pump(
      tester,
      location: editLocation(kDefaultThemeId),
      themesInApp: _FailingSetActive(t),
    );
    await dragRadiusToMax(tester);
    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);

    expect(find.text("Couldn't apply the theme"), findsOneWidget);
    expect(find.byType(ThemeEditorPage), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('themeEditor.save')),
    );
    expect(save.onPressed, isNotNull);

    // Saving again updates the copy already written, not a second one.
    await tester.tap(find.byKey(const Key('themeEditor.save')));
    await settle(tester);
    expect((await saved(tester)).map((e) => e.name), ['Default copy']);
  });
}

/// The harness's repository, except that making a theme active fails.
class _FailingSetActive extends ThemeRepository {
  _FailingSetActive(ThemeHarness t)
    : super(t.h.db, t.h.stamp, SettingsRepository(t.h.db));

  @override
  Future<void> setActive(String id) async =>
      throw StateError('settings unwritable');
}
