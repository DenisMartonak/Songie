import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/library/playlist_page.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/shell/bottom_nav.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';

import 'helpers/fake_audio_backend.dart';

class _NoTracks implements TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Err(Failure(FailureKind.notFound, 'none'));
}

/// Pumps the app at phone width, whose shell needs only the player.
Future<GoRouter> pumpRouter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerServiceProvider.overrideWithValue(
          PlayerService(FakeAudioBackend(), _NoTracks()),
        ),
      ],
      child: MaterialApp.router(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        routerConfig: router,
      ),
    ),
  );
  return router;
}

void main() {
  testWidgets('starts on /home and reaches every route', (tester) async {
    final router = await pumpRouter(tester);
    expect(find.byType(HomePage), findsOneWidget);

    router.go('/search');
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);

    router.go('/playlist/abc');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PlaylistPage, 'Playlist abc'), findsOneWidget);

    router.go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    // Settings lives in the shell, so the phone keeps its bottom nav.
    expect(find.byType(BottomNav), findsOneWidget);
  });

  testWidgets('openNowPlaying pushes once, then does nothing', (tester) async {
    final router = await pumpRouter(tester);

    openNowPlaying(router);
    await tester.pumpAndSettle();
    openNowPlaying(router);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPage), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });

  test('providers that main() should override fail loudly', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(playerServiceProvider),
      throwsA(predicate((e) => e.toString().contains('must be overridden'))),
    );
  });
}
