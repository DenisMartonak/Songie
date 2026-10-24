import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/settings/themes/theme_editor_page.dart';
import 'package:songies/ui/settings/themes/theme_file.dart';

import '../../../helpers/ui_harness.dart';
import 'theme_test_harness.dart';

void main() {
  late ThemeHarness t;

  setUp(() async => t = await ThemeHarness.create());
  tearDown(() => t.dispose());

  Future<String> addTheme(WidgetTester tester, String name) => real(
    tester,
    () async => (await t.themes.save(
      null,
      name,
      ThemeSpec.terminal,
    ) as Ok<String>).value,
  );

  Future<ThemeEntry> active(WidgetTester tester) =>
      real(tester, () => t.themes.watchActive().first);

  Future<List<ThemeEntry>> saved(WidgetTester tester) async => [
    for (final e in await real(tester, () => t.themes.watchAll().first))
      if (!e.builtIn) e,
  ];

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('themes.menu.$id')));
    await settle(tester);
  }

  uiTest('shows every theme with a check on the active one', (tester) async {
    final id = await addTheme(tester, 'Mine');
    await t.pump(tester, location: '/settings/themes');

    for (final key in [
      kDefaultThemeId,
      kAlbumGlowThemeId,
      kTerminalThemeId,
      id,
    ]) {
      expect(find.byKey(Key('themes.card.$key')), findsOneWidget);
    }
    expect(find.text('Mine'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('themes.card.$kDefaultThemeId')),
        matching: find.byKey(const Key('themes.activeCheck')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('themes.activeCheck')), findsOneWidget);
  });

  uiTest('tapping a card applies it', (tester) async {
    await t.pump(tester, location: '/settings/themes');
    await tester.tap(find.byKey(const Key('themes.card.$kTerminalThemeId')));
    await settle(tester);

    expect((await active(tester)).id, kTerminalThemeId);
    expect(
      find.descendant(
        of: find.byKey(const Key('themes.card.$kTerminalThemeId')),
        matching: find.byKey(const Key('themes.activeCheck')),
      ),
      findsOneWidget,
    );
  });

  uiTest('built-ins offer no Delete; saved themes do', (tester) async {
    final id = await addTheme(tester, 'Mine');
    await t.pump(tester, location: '/settings/themes');

    await openMenu(tester, kDefaultThemeId);
    for (final item in ['Edit', 'Duplicate', 'Export']) {
      expect(find.text(item), findsOneWidget);
    }
    expect(find.text('Delete'), findsNothing);
    await tester.tapAt(Offset.zero);
    await settle(tester);

    await openMenu(tester, id);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(await saved(tester), isEmpty);
  });

  uiTest('Duplicate saves a copy', (tester) async {
    await t.pump(tester, location: '/settings/themes');
    await openMenu(tester, kTerminalThemeId);
    await tester.tap(find.text('Duplicate'));
    await settle(tester);

    expect((await saved(tester)).map((e) => e.name), ['Terminal copy']);
  });

  uiTest('Edit and New theme open the editor', (tester) async {
    await t.pump(tester, location: '/settings/themes');
    await openMenu(tester, kTerminalThemeId);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsOneWidget);
    expect(
      tester.widget<ThemeEditorPage>(find.byType(ThemeEditorPage)).id,
      kTerminalThemeId,
    );
    await tester.tap(find.byKey(const Key('themeEditor.back')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('themes.new')));
    await settle(tester);
    expect(
      tester.widget<ThemeEditorPage>(find.byType(ThemeEditorPage)).id,
      newThemeId,
    );
  });

  uiTest('Export saves a .songies-theme.json file', (tester) async {
    final files = <(String, Uint8List)>[];
    await t.pump(
      tester,
      location: '/settings/themes',
      extraOverrides: [
        themeFileSaverProvider.overrideWithValue((name, bytes) async {
          files.add((name, bytes));
          return true;
        }),
      ],
    );
    await openMenu(tester, kTerminalThemeId);
    await tester.tap(find.text('Export'));
    await settle(tester);

    expect(files.single.$1, 'Terminal.songies-theme.json');
    final json = jsonDecode(utf8.decode(files.single.$2)) as Map;
    expect(json['songiesTheme'], 1);
    expect(json['spec'], ThemeSpec.terminal.toJson());
    expect(find.text('Theme exported'), findsOneWidget);
  });

  uiTest('Import saves a valid file and rejects a bad one', (tester) async {
    final good = File('${t.tmp.path}/good.songies-theme.json');
    final bad = File('${t.tmp.path}/bad.songies-theme.json');
    await real(tester, () async {
      await good.writeAsBytes(
        ThemeFile(name: 'Shared', spec: ThemeSpec.terminal).encode(),
      );
      await bad.writeAsString('{"songiesTheme": 1}');
    });
    var pick = bad.path;
    await t.pump(
      tester,
      location: '/settings/themes',
      extraOverrides: [
        themeFilePickerProvider.overrideWithValue(() async => pick),
      ],
    );

    await tester.tap(find.byKey(const Key('themes.import')));
    await settle(tester);
    expect(find.text("That isn't a Songies theme file"), findsOneWidget);
    expect(await saved(tester), isEmpty);

    pick = good.path;
    await tester.tap(find.byKey(const Key('themes.import')));
    await settle(tester);
    expect((await saved(tester)).map((e) => e.name), ['Shared']);
    expect(find.text('Shared'), findsOneWidget);
  });
}
