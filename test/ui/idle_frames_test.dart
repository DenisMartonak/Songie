// The battery rule: once playback is paused and on-screen animations have
// settled, the whole app schedules no frames; and a backgrounded app schedules
// none even while it plays.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/app.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/motion/equalizer_bars.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/shell/window_controls.dart';

import '../helpers/fake_audio_backend.dart';

/// Long enough to make the Now Playing title scroll while playing.
const _longTitle =
    'A very long song title that cannot possibly fit on one line of the '
    'Now Playing page, so it scrolls';

Track _track(String id, String title) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: title,
  artist: 'Artist $id',
  durationMs: 200000,
  unavailable: false,
  searchText: '$title artist',
);

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

class _Window implements WindowControls {
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
    trackCount: 2,
    durationMs: 0,
    coverRef: null,
  ),
  PlaylistSummary(
    id: 'p2',
    name: 'Road trip',
    source: 'yt',
    trackCount: 3,
    durationMs: 0,
    coverRef: null,
  ),
];

void main() {
  late PlayerService player;
  late GoRouter router;

  /// The real app (SongiesApp: router, shell, MotionScope, AnimatedTheme) on
  /// Album glow, the liveliest built-in, with no downloads running.
  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Created here so the player's command queue lives in the test's
    // fake-async zone and is driven by pump(); it holds only fakes.
    player = PlayerService(FakeAudioBackend(), _Resolver());
    router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerServiceProvider.overrideWithValue(player),
          initialThemeSpecProvider.overrideWithValue(ThemeSpec.albumGlow),
          activeThemeProvider.overrideWith(
            (ref) => Stream.value(
              const ThemeEntry(
                id: kAlbumGlowThemeId,
                name: 'Album glow',
                spec: ThemeSpec.albumGlow,
                builtIn: true,
              ),
            ),
          ),
          resolvedFontFamilyProvider.overrideWithValue('Outfit'),
          coverPaletteProvider.overrideWith((ref) => Stream.value(null)),
          playlistsProvider.overrideWith((ref) => Stream.value(_playlists)),
          recentPlaylistIdsProvider.overrideWith(
            (ref) => Stream.value(const ['p1', 'p2']),
          ),
          recentTracksProvider.overrideWith((ref) => Stream.value(const [])),
          libraryFoldersProvider.overrideWith((ref) => Stream.value(const [])),
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          deviceIdProvider.overrideWithValue('0123456789abcdef'),
          ytDlpVersionProvider.overrideWith((ref) async => null),
          wifiOnlySettingProvider.overrideWith((ref) => Stream.value(false)),
          useSystemYtDlpProvider.overrideWith((ref) => Stream.value(false)),
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
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          searchTracksProvider.overrideWith(
            (ref, query) => Stream.value(const []),
          ),
          searchPlaylistsProvider.overrideWith(
            (ref, query) => Stream.value(_playlists),
          ),
          windowControlsProvider.overrideWithValue(_Window()),
          hasCustomTitleBarProvider.overrideWithValue(size.width >= 720),
        ],
        child: SongiesApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Plays a two-song queue from playlist p1, so the playlist's equalizer
  /// bars (Home tile, sidebar row) and the Now Playing title are live.
  Future<void> play(WidgetTester tester, {String title = 'Short'}) async {
    unawaited(
      player.playQueue([
        _track('a', title),
        _track('b', 'Second'),
      ], sourcePlaylistId: 'p1'),
    );
    // Not pumpAndSettle: while playing, the equalizer never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(player.state.playing, isTrue);
  }

  Future<void> pause(WidgetTester tester) async {
    unawaited(player.pause());
    await tester.pumpAndSettle();
    expect(player.state.playing, isFalse);
  }

  void expectIdle(WidgetTester tester, String where) {
    expect(tester.binding.hasScheduledFrame, isFalse, reason: where);
    expect(tester.binding.transientCallbackCount, 0, reason: where);
  }

  for (final (name, size) in [
    ('phone', const Size(400, 800)),
    ('desktop', const Size(1280, 800)),
  ]) {
    group('$name (${size.width.toInt()} wide)', () {
      testWidgets('paused on Home, then on Now Playing, nothing is drawn', (
        tester,
      ) async {
        await pumpApp(tester, size);
        expect(find.byType(HomePage), findsOneWidget);
        await play(tester, title: _longTitle);
        // Playing does animate (or this test would prove nothing).
        expect(find.byType(EqualizerBars), findsWidgets);
        expect(tester.binding.hasScheduledFrame, isTrue);

        await pause(tester);
        expectIdle(tester, 'paused on Home');

        openNowPlaying(router);
        await tester.pumpAndSettle();
        expect(find.byType(NowPlayingPage), findsOneWidget);
        // On desktop Now Playing is a see-through panel: the shell behind it
        // stays painted and must be still too.
        if (size.width >= 720) expect(find.byType(HomePage), findsOneWidget);
        expectIdle(tester, 'paused on Now Playing');

        // And it stays idle: no timer wakes anything up later.
        await tester.pump(const Duration(seconds: 10));
        expectIdle(tester, 'paused on Now Playing, 10 s later');
      });

      testWidgets('backgrounded while playing, nothing is drawn', (
        tester,
      ) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await pumpApp(tester, size);
        await play(tester, title: _longTitle);
        openNowPlaying(router);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(NowPlayingPage), findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isTrue);

        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(player.state.playing, isTrue);
        expectIdle(tester, 'backgrounded');

        await tester.pump(const Duration(seconds: 10));
        expectIdle(tester, 'backgrounded, 10 s later');

        // Back in front, the playing animations resume.
        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.binding.hasScheduledFrame, isTrue);

        await pause(tester);
        expectIdle(tester, 'paused after resuming');
      });
    });
  }
}
