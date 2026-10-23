import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/library/library_page.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/shell/bottom_nav.dart';
import 'package:songies/ui/shell/window_controls.dart';

import '../../helpers/fake_audio_backend.dart';

class _NoResolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Err(Failure(FailureKind.notFound, 'none'));
}

class _NoWindow implements WindowControls {
  @override
  Future<void> minimize() async {}
  @override
  Future<void> maximizeOrRestore() async {}
  @override
  Future<void> close() async {}
  @override
  Future<bool> isMaximized() async => false;
  @override
  Stream<bool> get maximizedChanges => const Stream.empty();
}

const _playlists = [
  PlaylistSummary(
    id: 'p1',
    name: 'Gym Mix',
    source: 'local',
    trackCount: 12,
    durationMs: 0,
    coverRef: null,
  ),
];

Future<GoRouter> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerServiceProvider.overrideWithValue(
          PlayerService(FakeAudioBackend(), _NoResolver()),
        ),
        playlistsProvider.overrideWith((ref) => Stream.value(_playlists)),
        recentPlaylistIdsProvider.overrideWith((ref) => Stream.value(const [])),
        recentTracksProvider.overrideWith((ref) => Stream.value(const [])),
        libraryFoldersProvider.overrideWith((ref) => Stream.value(const [])),
        storageUsageProvider.overrideWith(
          (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
        ),
        playlistTracksProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        searchTracksProvider.overrideWith((ref, q) => Stream.value(const [])),
        searchPlaylistsProvider.overrideWith(
          (ref, q) => Stream.value(_playlists),
        ),
        windowControlsProvider.overrideWithValue(_NoWindow()),
        hasCustomTitleBarProvider.overrideWithValue(false),
      ],
      child: MaterialApp.router(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  Finder navLabel(String label) =>
      find.descendant(of: find.byType(BottomNav), matching: find.text(label));

  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(navLabel(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('phone', () {
    const phone = Size(400, 800);

    testWidgets('Home reopens its root after a playlist was open', (
      tester,
    ) async {
      final router = await _pump(tester, phone);
      router.go('/home/playlist/p1');
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tapNav(tester, 'Library');
      await tapNav(tester, 'Home');

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);
    });

    testWidgets('Library reopens its root after a playlist was open', (
      tester,
    ) async {
      final router = await _pump(tester, phone);
      router.go('/library/playlist/p1');
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tapNav(tester, 'Home');
      await tapNav(tester, 'Library');

      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);
    });

    testWidgets('back still pops a playlist inside the branch', (tester) async {
      final router = await _pump(tester, phone);
      router.go('/home/playlist/p1');
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);
    });
  });

  group('desktop', () {
    const desktop = Size(1280, 800);

    testWidgets('sidebar Library and Home open their roots', (tester) async {
      await _pump(tester, desktop);

      await tapKey(tester, 'sidebar.playlist.p1');
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tapKey(tester, 'sidebar.library');
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);

      await tapKey(tester, 'sidebar.home');
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);
    });

    testWidgets('sidebar Search opens its root', (tester) async {
      final router = await _pump(tester, desktop);
      router.go('/search/playlist/p1');
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tapKey(tester, 'sidebar.home');
      await tapKey(tester, 'sidebar.search');

      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byType(PlaylistPage), findsNothing);
    });
  });
}
