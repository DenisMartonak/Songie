import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/font_service.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/ui/settings/themes/theme_editor_page.dart';
import 'package:songies/ui/settings/themes/themes_page.dart';

import '../../../helpers/ui_harness.dart';

/// The UI harness plus a real theme repository and font service on its
/// database, and the Themes routes as the app nests them.
class ThemeHarness {
  ThemeHarness._(this.h, this.tmp)
    : themes = ThemeRepository(h.db, h.stamp, SettingsRepository(h.db)),
      fonts = FontService(
        h.db,
        h.stamp,
        Directory(p.join(tmp.path, 'fonts')),
        register: (_, _) async {},
      );

  final UiHarness h;
  final Directory tmp;
  final ThemeRepository themes;
  final FontService fonts;

  static Future<ThemeHarness> create() async {
    final h = await UiHarness.create();
    final tmp = Directory.systemTemp.createTempSync('songies_themes_ui_');
    final t = ThemeHarness._(h, tmp);
    // A fresh install would pick Album glow (it follows the cover); start
    // from Default so the app's colours need no player.
    await t.themes.setActive(kDefaultThemeId);
    return t;
  }

  Future<void> dispose() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  }

  Future<void> pump(
    WidgetTester tester, {
    required String location,
    List<Override> extraOverrides = const [],
    ThemeRepository? themesInApp,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        extraOverrides: [
          fontServiceProvider.overrideWithValue(fonts),
          themeRepositoryProvider.overrideWithValue(themesInApp ?? themes),
          ...extraOverrides,
        ],
        routes: [
          GoRoute(
            path: '/settings/themes',
            builder: (_, _) => const Scaffold(body: ThemesPage()),
            routes: [
              GoRoute(
                path: 'edit/:id',
                builder: (_, state) => Scaffold(
                  body: ThemeEditorPage(id: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }
}
