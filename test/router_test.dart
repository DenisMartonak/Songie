import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/shell/bottom_nav.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';

import 'helpers/fake_audio_backend.dart';

class _NoTracks extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Err(Failure(FailureKind.notFound, 'none'));
}

/// Pumps the app at phone width, whose shell needs only the player.
Future<GoRouter> pumpRouter(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
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
        // The playlist page reads the library; an empty one is enough here.
        playlistsProvider.overrideWith((ref) => Stream.value(const [])),
        recentPlaylistIdsProvider.overrideWith((ref) => Stream.value(const [])),
        recentTracksProvider.overrideWith((ref) => Stream.value(const [])),
        // Settings reads these.
        libraryFoldersProvider.overrideWith((ref) => Stream.value(const [])),
        storageUsageProvider.overrideWith(
          (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
        ),
        deviceIdProvider.overrideWithValue('0123456789abcdef'),
        // The YouTube section reads these.
        ytDlpVersionProvider.overrideWith((ref) async => null),
        wifiOnlySettingProvider.overrideWith((ref) => Stream.value(false)),
        useSystemYtDlpProvider.overrideWith((ref) => Stream.value(false)),
        // The download UI reads these.
        downloadSnapshotProvider.overrideWith(
          (ref) => Stream.value(const DownloadSnapshot()),
        ),
        downloadEnabledPlaylistsProvider.overrideWith(
          (ref) => Stream.value(const <String>{}),
        ),
        downloadTotalBytesProvider.overrideWith((ref) => Stream.value(0)),
        downloadBytesPerPlaylistProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
      child: MaterialApp.router(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
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
    expect(find.byType(PlaylistPage), findsOneWidget);

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

  group('transitions', () {
    Finder inTransition<T extends Widget>(Type page) =>
        find.ancestor(of: find.byType(page), matching: find.byType(T));

    testWidgets('pushing a playlist uses a shared-axis transition', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      unawaited(router.push('/home/playlist/abc'));
      await tester.pump();
      await tester.pump(Motion.emphasized ~/ 2);
      final axis = tester.widget<SharedAxisTransition>(
        inTransition<SharedAxisTransition>(PlaylistPage).first,
      );
      expect(axis.transitionType, SharedAxisTransitionType.horizontal);
      expect(axis.animation.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);
    });

    testWidgets('switching tabs fades through', (tester) async {
      final router = await pumpRouter(tester);
      router.go('/search');
      await tester.pump();
      await tester.pump(Motion.standard ~/ 2);
      final fade = tester.widget<FadeThroughTransition>(
        inTransition<FadeThroughTransition>(SearchPage).first,
      );
      expect(fade.animation.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      // Settled: nothing keeps ticking.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('Now Playing slides up over Motion.emphasized', (tester) async {
      final router = await pumpRouter(tester);
      openNowPlaying(router);
      await tester.pump();
      await tester.pump(Motion.emphasized - const Duration(milliseconds: 50));
      final top = tester.getTopLeft(find.byType(NowPlayingPage)).dy;
      expect(top, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(find.byType(NowPlayingPage)).dy, 0);
    });

    testWidgets('with reduced motion every transition is instant', (
      tester,
    ) async {
      final router = await pumpRouter(tester, disableAnimations: true);

      router.go('/search');
      await tester.pump();
      await tester.pump();
      expect(find.byType(HomePage), findsNothing);
      expect(find.byType(SearchPage), findsOneWidget);

      unawaited(router.push('/search/playlist/abc'));
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(PlaylistPage), findsOneWidget);

      openNowPlaying(router);
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getTopLeft(find.byType(NowPlayingPage)).dy, 0);
    });
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
