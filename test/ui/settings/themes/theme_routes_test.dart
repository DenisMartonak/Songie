import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/settings/themes/theme_editor_page.dart';
import 'package:songies/ui/settings/themes/themes_page.dart';

import '../../../helpers/ui_harness.dart';
import 'theme_test_harness.dart';

/// The Themes pages through the app's real router, inside the shell.
void main() {
  late ThemeHarness t;

  setUp(() async => t = await ThemeHarness.create());
  tearDown(() => t.dispose());

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...t.h.overrides,
          fontServiceProvider.overrideWithValue(t.fonts),
          themeRepositoryProvider.overrideWithValue(t.themes),
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          deviceIdProvider.overrideWithValue('0123456789abcdef'),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: router,
          builder: (context, child) => MotionScope(child: child!),
        ),
      ),
    );
    await settle(tester);
    return router;
  }

  uiTest('an encoded built-in id opens the editor for that theme', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/settings/themes/edit/builtin%3Aterminal');
    await settle(tester);

    final editor = tester.widget<ThemeEditorPage>(find.byType(ThemeEditorPage));
    expect(editor.id, 'builtin:terminal');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('themeEditor.name')))
          .controller!
          .text,
      'Terminal copy',
    );
  });

  uiTest('system Back with unsaved changes asks to discard them', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/settings/themes');
    await settle(tester);
    router.push(themeEditorLocation('builtin:default'));
    await settle(tester);

    // Without changes, Back leaves.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsNothing);
    expect(find.byType(ThemesPage), findsOneWidget);

    router.push(themeEditorLocation('builtin:default'));
    await settle(tester);
    final slider = find.byKey(const Key('themeEditor.radius'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(2000, 0));
    await settle(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.byType(ThemeEditorPage), findsNothing);
    expect(find.byType(ThemesPage), findsOneWidget);
  });
}
