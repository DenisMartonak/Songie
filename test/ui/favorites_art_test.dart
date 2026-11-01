import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/shell/sidebar.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  uiTest("Favorites shows its star in the sidebar and on Home's tiles", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1');
      final f = FavoritesRepository(h.db, h.stamp);
      await f.ensureFavorites();
      await f.star('t1');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          lyricsServiceProvider.overrideWithValue(FakeLyricsService()),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home.tile.$kFavoritesPlaylistId')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
    );
  });
}
