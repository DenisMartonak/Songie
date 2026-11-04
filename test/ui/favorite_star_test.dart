import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/widgets/favorite_star.dart';
import 'package:songies/ui/widgets/song_menu.dart';
import 'package:songies/ui/island/island_host.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async {
    h = await UiHarness.create();
  });
  tearDown(() => h.dispose());

  Future<Track> seed(WidgetTester tester) => real(tester, () async {
    await FavoritesRepository(h.db, h.stamp).ensureFavorites();
    await h.addTrack('t1', title: 'Song one');
    await h.addTrack('t2', title: 'Song two');
    return (h.db.select(
      h.db.tracks,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get().then((l) => l.first);
  });

  Future<bool> starred(WidgetTester tester, String id) => real(
    tester,
    () async => (await FavoritesRepository(
      h.db,
      h.stamp,
    ).watchIds().first).contains(id),
  );

  uiTest('a star toggles the song in and out of Favorites', (tester) async {
    final track = await seed(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: MaterialApp(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          builder: (_, c) => IslandHost(child: c!),
          home: Scaffold(body: FavoriteStar(song: MenuSong.track(track))),
        ),
      ),
    );
    await settle(tester);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(find.byTooltip('Add to Favorites'), findsOneWidget);

    await tester.tap(find.byType(FavoriteStar));
    await settle(tester);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
    expect(await starred(tester, 't1'), isTrue);

    await tester.tap(find.byType(FavoriteStar));
    await settle(tester);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(await starred(tester, 't1'), isFalse);
  });

  uiTest('the player bar has a star for the playing song', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final track = await seed(tester);
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
          builder: (_, c) => IslandHost(child: c!),
        ),
      ),
    );
    await settle(tester);
    await real(tester, () => h.player.playQueue([track]));
    await settle(tester);
    final star = find.descendant(
      of: find.byType(PlayerBar),
      matching: find.byType(FavoriteStar),
    );
    expect(star, findsOneWidget);

    // The star sits right after the title, not at the far edge.
    final title = find.descendant(
      of: find.byType(PlayerBar),
      matching: find.text('Song one'),
    );
    final titleRect = tester.getRect(title);
    final starRect = tester.getRect(star);
    expect(starRect.left - titleRect.right, inInclusiveRange(0, 12));
    expect(starRect.center.dy, closeTo(titleRect.center.dy, 4));

    await tester.tap(star);
    await settle(tester);
    expect(await starred(tester, 't1'), isTrue);
  });
}
