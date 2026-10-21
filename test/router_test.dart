import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/library/playlist_page.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/settings/settings_page.dart';

void main() {
  testWidgets('starts on /home and reaches every route', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
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
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('openNowPlaying pushes once, then does nothing', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

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
