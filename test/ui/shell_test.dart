import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/library/library_page.dart';
import 'package:songies/ui/motion/equalizer_bars.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/account/auth_screens.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/shell/bottom_nav.dart';
import 'package:songies/ui/shell/desktop_shell.dart';
import 'package:songies/ui/shell/title_bar.dart';
import 'package:songies/ui/shell/mini_player.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/shell/sidebar.dart';
import 'package:songies/ui/shell/window_controls.dart';
import 'package:songies/ui/island/island_host.dart';

import 'package:songies/account/account_service.dart';
import 'package:songies/ui/account/avatar.dart';

import '../account/fake_account_backend.dart';
import '../helpers/fake_audio_backend.dart';

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist $id',
  durationMs: 200000,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

class _MissingResolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Err(Failure(FailureKind.notFound, 'gone'));
}

class _FakeWindowControls implements WindowControls {
  final List<String> calls = [];
  bool maximizedQueried = false;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> maximizeOrRestore() async => calls.add('maximizeOrRestore');
  @override
  Future<void> close() async => calls.add('close');
  @override
  Future<bool> isMaximized() async {
    maximizedQueried = true;
    return false;
  }

  @override
  Stream<bool> get maximizedChanges => _changes.stream;
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
  PlaylistSummary(
    id: 'p2',
    name: 'Road trip',
    source: 'yt',
    trackCount: 3,
    durationMs: 0,
    coverRef: null,
  ),
];

/// The asset an `SvgPicture.asset` was built from.
String? assetOf(WidgetTester tester, String key) {
  final loader = tester.widget<SvgPicture>(find.byKey(Key(key))).bytesLoader;
  return loader is SvgAssetLoader ? loader.assetName : null;
}

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  late _FakeWindowControls window;
  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    bool customTitleBar = true,
    TrackResolver? resolver,
    ThemeSpec theme = ThemeSpec.builtInDefault,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Created here, not in setUp: the player's command queue must live in the
    // test's fake-async zone to be driven by pump(). It holds only fakes, so
    // there is nothing to dispose.
    backend = FakeAudioBackend();
    player = PlayerService(backend, resolver ?? _Resolver());
    window = _FakeWindowControls();
    router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerServiceProvider.overrideWithValue(player),
          playlistsProvider.overrideWith((ref) => Stream.value(_playlists)),
          recentPlaylistIdsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          recentTracksProvider.overrideWith((ref) => Stream.value(const [])),
          // Settings reads these.
          libraryFoldersProvider.overrideWith((ref) => Stream.value(const [])),
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          deviceIdProvider.overrideWithValue('0123456789abcdef'),
          accountServiceProvider.overrideWithValue(
            AccountService(FakeAccountBackend()),
          ),
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
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          searchTracksProvider.overrideWith(
            (ref, query) => Stream.value(const []),
          ),
          searchPlaylistsProvider.overrideWith(
            (ref, query) => Stream.value(_playlists),
          ),
          windowControlsProvider.overrideWithValue(window),
          hasCustomTitleBarProvider.overrideWithValue(customTitleBar),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(theme),
          routerConfig: router,
          builder: (_, c) => IslandHost(child: c!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> startPlaying(WidgetTester tester) async {
    unawaited(player.playQueue([track('a'), track('b')]));
    await tester.pumpAndSettle();
  }

  Finder navLabel(String label) =>
      find.descendant(of: find.byType(BottomNav), matching: find.text(label));

  SongiesColors colorsOf(WidgetTester tester, Type type) =>
      Theme.of(tester.element(find.byType(type))).extension<SongiesColors>()!;

  group('phone shell (400x800)', () {
    const phone = Size(400, 800);

    testWidgets('shows the bottom nav with Home active', (tester) async {
      await pumpApp(tester, phone);
      final colors = colorsOf(tester, BottomNav);

      expect(find.byType(BottomNav), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
      expect(assetOf(tester, 'nav.icon.0'), 'assets/icons/home_filled.svg');
      final home = tester.widget<Text>(navLabel('Home'));
      expect(home.style?.color, colors.text);
      expect(home.style?.fontWeight, FontWeight.w700);
      final search = tester.widget<Text>(navLabel('Search'));
      expect(search.style?.color, colors.mutedText);
      expect(assetOf(tester, 'nav.icon.1'), 'assets/icons/search.svg');
      expect(assetOf(tester, 'nav.icon.2'), 'assets/icons/library.svg');
    });

    testWidgets('nav is 64 high, labels 10.5, icons 24', (tester) async {
      await pumpApp(tester, phone);
      expect(tester.getSize(find.byType(BottomNav)).height, 64);
      expect(tester.widget<Text>(navLabel('Home')).style?.fontSize, 10.5);
      expect(
        tester.getSize(find.byKey(const Key('nav.icon.0'))),
        const Size(24, 24),
      );
    });

    testWidgets('Search active: Home turns outline, Search bold + white', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      final colors = colorsOf(tester, BottomNav);

      await tester.tap(navLabel('Search'));
      await tester.pumpAndSettle();

      expect(assetOf(tester, 'nav.icon.0'), 'assets/icons/home_outline.svg');
      expect(assetOf(tester, 'nav.icon.1'), 'assets/icons/search_bold.svg');
      final search = tester.widget<Text>(navLabel('Search'));
      expect(search.style?.color, colors.text);
      expect(search.style?.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Text>(navLabel('Home')).style?.color,
        colors.mutedText,
      );
      expect(find.byType(SearchPage), findsOneWidget);
    });

    testWidgets('Library active uses the bold library icon', (tester) async {
      await pumpApp(tester, phone);
      await tester.tap(navLabel('Library'));
      await tester.pumpAndSettle();
      expect(assetOf(tester, 'nav.icon.2'), 'assets/icons/library_bold.svg');
    });

    group('playlist pages keep the page they came from underneath', () {
      /// What Android's Back button does; false means the app would close.
      Future<bool> systemBack(WidgetTester tester) async {
        final handled = await WidgetsBinding.instance.handlePopRoute();
        await tester.pumpAndSettle();
        return handled;
      }

      testWidgets('Home quick tile: Back arrow and system Back return Home', (
        tester,
      ) async {
        await pumpApp(tester, phone);
        await tester.tap(find.byKey(const Key('home.tile.p1')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistPage), findsOneWidget);
        expect(find.byTooltip('Back'), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(find.byType(PlaylistPage), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);
      });

      testWidgets('Home card: the arrow returns Home', (tester) async {
        await pumpApp(tester, phone);
        final card = find.byKey(const Key('home.card.p2'));
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistPage), findsOneWidget);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
      });

      testWidgets('Search result: system Back returns to Search', (
        tester,
      ) async {
        await pumpApp(tester, phone);
        await tester.tap(navLabel('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('search.field')), 'gym');
        await tester.pump(searchDebounce);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('search.playlist.p1')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistPage), findsOneWidget);
        expect(find.byTooltip('Back'), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(find.byType(PlaylistPage), findsNothing);
        expect(find.byType(SearchPage), findsOneWidget);
      });

      testWidgets('Library list: system Back returns to Library', (
        tester,
      ) async {
        await pumpApp(tester, phone);
        await tester.tap(navLabel('Library'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('library.playlist.p1')));
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistPage), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(find.byType(LibraryPage), findsOneWidget);
      });

      testWidgets('the old /playlist/:id link still opens the playlist', (
        tester,
      ) async {
        await pumpApp(tester, phone);
        router.go('/playlist/p1');
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistPage), findsOneWidget);
        expect(router.state.uri.path, '/library/playlist/p1');
      });
    });

    testWidgets('no mini-player while the queue is empty', (tester) async {
      await pumpApp(tester, phone);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('mini-player appears 8 px above the nav, 48 high', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);

      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Title a'), findsOneWidget);
      final mini = tester.getRect(find.byType(MiniPlayer));
      final nav = tester.getRect(find.byType(BottomNav));
      expect(nav.top - mini.bottom, 8);
      expect(mini.height, 48);
      final pill = tester.getRect(find.byKey(const Key('miniPlayer.pill')));
      expect(pill.height, 48);
      expect(pill.left, 8);
      expect(400 - pill.right, 8);
    });

    testWidgets('mini-player play button toggles playback', (tester) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      expect(player.state.playing, isTrue);

      await tester.tap(find.byKey(const Key('miniPlayer.playPause')));
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'pause');
      expect(player.state.playing, isFalse);

      await tester.tap(find.byKey(const Key('miniPlayer.playPause')));
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'play');
    });

    testWidgets('tapping the mini-player opens Now Playing', (tester) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);

      await tester.tap(find.text('Title a'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, nowPlayingLocation);
    });

    testWidgets('swiping the mini-player left skips next, right previous', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      final pill = find.byKey(const Key('miniPlayer.pill'));

      await tester.drag(pill, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'b');
      expect(find.text('Title b'), findsOneWidget);
      expect(router.state.uri.path, isNot(nowPlayingLocation));

      await tester.drag(pill, const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'a');
      expect(router.state.uri.path, isNot(nowPlayingLocation));
    });

    testWidgets('with reduced motion a swipe skips instantly', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpApp(tester, phone);
      await startPlaying(tester);
      final before = tester.getTopLeft(find.text('Title a'));

      await tester.drag(
        find.byKey(const Key('miniPlayer.pill')),
        const Offset(-160, 0),
      );
      await tester.pump();
      await tester.pump();
      expect(player.state.current?.id, 'b');
      expect(find.text('Title a'), findsNothing);
      expect(tester.getTopLeft(find.text('Title b')), before);
    });

    testWidgets('a swipe that restarts the song leaves no direction behind', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      backend.setDuration(const Duration(seconds: 200));
      backend.setPosition(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      // Mid-song, a swipe right restarts the song instead of going back.
      await tester.drag(
        find.byKey(const Key('miniPlayer.pill')),
        const Offset(160, 0),
      );
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'a');

      // The song plays out: an auto-advance is a plain crossfade, with no
      // slide left over from the swipe.
      final rest = tester.getTopLeft(find.text('Title a'));
      backend.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(Motion.emphasized ~/ 4);
      expect(player.state.current?.id, 'b');
      expect(tester.getTopLeft(find.text('Title b')).dx, closeTo(rest.dx, 0.5));
      await tester.pumpAndSettle();
    });

    testWidgets('the mini-player content slides with the finger', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      final before = tester.getTopLeft(find.text('Title a'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('miniPlayer.pill'))),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('Title a')).dx, lessThan(before.dx));

      // A short drag springs back without skipping.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'a');
      expect(tester.getTopLeft(find.text('Title a')), before);
    });

    testWidgets('a vertical drag on the mini-player does not skip', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      await tester.drag(
        find.byKey(const Key('miniPlayer.pill')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'a');
    });

    testWidgets('mini-player fill is the theme tint', (tester) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      final colors = colorsOf(tester, MiniPlayer);
      final pill = tester.widget<Container>(
        find.byKey(const Key('miniPlayer.pill')),
      );
      expect((pill.decoration! as BoxDecoration).color, colors.miniPlayer);
    });

    testWidgets('a tab tap bounces its icon once (1.0 -> 1.12 -> 1.0)', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      double scale(int i) => tester
          .widget<ScaleTransition>(find.byKey(Key('nav.bounce.$i')))
          .scale
          .value;
      expect(scale(1), 1.0);

      await tester.tap(navLabel('Search'));
      await tester.pump();
      await tester.pump(Motion.standard ~/ 2);
      expect(scale(1), greaterThan(1.05));
      expect(scale(1), lessThanOrEqualTo(1.12));
      expect(scale(0), 1.0);

      await tester.pumpAndSettle();
      expect(scale(1), 1.0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('mini-player progress line follows the position', (
      tester,
    ) async {
      await pumpApp(tester, phone);
      await startPlaying(tester);
      backend.setDuration(const Duration(seconds: 200));
      backend.setPosition(const Duration(seconds: 50));
      await tester.pumpAndSettle();

      final line = tester.getSize(find.byKey(const Key('miniPlayer.progress')));
      final track = tester.getSize(find.byKey(const Key('miniPlayer.track')));
      expect(track.height, 2);
      expect(line.width / track.width, closeTo(0.25, 0.01));
    });
  });

  group('desktop shell (1280x800)', () {
    const desktop = Size(1280, 800);

    testWidgets(
      'shows a 46 px title bar with a 520 px search field, 260 px sidebar and 72 px player bar',
      (tester) async {
        await pumpApp(tester, desktop);
        expect(find.byType(DesktopShell), findsOneWidget);
        expect(find.byType(BottomNav), findsNothing);
        expect(find.byType(MiniPlayer), findsNothing);
        expect(tester.getSize(find.byKey(const Key('titleBar'))).height, 46);
        final search = tester.getSize(find.byKey(const Key('shell.search')));
        expect(search.height, 36);
        expect(search.width, 520);
        expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 260);
        expect(tester.getSize(find.byKey(const Key('playerBar'))).height, 72);
        // The sidebar lists them (Home shows the playlists too).
        final sidebar = find.byKey(const Key('sidebar'));
        expect(
          find.descendant(of: sidebar, matching: find.text('Gym Mix')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebar, matching: find.text('Road trip')),
          findsOneWidget,
        );
      },
    );

    testWidgets('chevron collapses the sidebar to a 72 px rail', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      await tester.tap(find.byKey(const Key('sidebar.toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 72);
      expect(
        find.descendant(
          of: find.byKey(const Key('sidebar')),
          matching: find.text('Gym Mix'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sidebar.toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 260);
    });

    testWidgets('sidebar navigates', (tester) async {
      await pumpApp(tester, desktop);

      await tester.tap(find.byKey(const Key('sidebar.search')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/search');

      await tester.tap(find.text('Gym Mix'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/library/playlist/p1');
      expect(find.byType(PlaylistPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('sidebar.home')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/home');

      await tester.tap(find.byKey(const Key('sidebar.settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      // Settings renders inside the shell: chrome stays.
      expect(find.byType(TitleBar), findsOneWidget);
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.byKey(const Key('playerBar')), findsOneWidget);
    });

    testWidgets('on your profile the sidebar does not mark Home', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      bool homeMarked() =>
          (tester.widget(
                find.byKey(const Key('sidebar.home')),
              ) as dynamic).selected
              as bool;
      expect(homeMarked(), isTrue);
      router.go('/profile');
      await tester.pumpAndSettle();
      expect(homeMarked(), isFalse);
    });

    testWidgets(
      'typing in the title-bar search sets the query and opens Search',
      (tester) async {
        await pumpApp(tester, desktop);
        await tester.enterText(
          find.byKey(const Key('shell.search')),
          'beyonce',
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(DesktopShell)),
        );
        expect(container.read(searchQueryProvider), 'beyonce');
        expect(router.state.uri.path, '/search');
      },
    );

    testWidgets('the search field keeps focus when the first letter opens '
        'Search', (tester) async {
      await pumpApp(tester, desktop);
      final field = find.byKey(const Key('shell.search'));
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'b');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/search');
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);

      // The next letters land in the field.
      tester.testTextInput.enterText('be');
      await tester.pumpAndSettle();
      expect(editable.widget.controller.text, 'be');
      expect(editable.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets(
      'taking focus back after the first letter leaves the caret after it',
      (tester) async {
        await pumpApp(tester, desktop);
        final field = find.byKey(const Key('shell.search'));
        await tester.tap(field);
        await tester.pump();
        await tester.enterText(field, 'b');
        await tester.pumpAndSettle();
        final editable = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        // Desktop fields select all on focus; the next letter would replace
        // the first.
        expect(
          editable.widget.controller.selection,
          const TextSelection.collapsed(offset: 1),
        );
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets('without a custom title bar (wide Android) there is no title '
        'bar, no window plugin use, and search moves to the main pane', (
      tester,
    ) async {
      await pumpApp(tester, desktop, customTitleBar: false);
      expect(find.byType(TitleBar), findsNothing);
      expect(find.byKey(const Key('window.close')), findsNothing);
      expect(window.maximizedQueried, isFalse);
      // The search field is still there, below the top edge, and works.
      final field = find.byKey(const Key('shell.search'));
      expect(field, findsOneWidget);
      expect(
        tester.getRect(field).left,
        greaterThan(tester.getSize(find.byKey(const Key('sidebar'))).width),
      );
      await tester.enterText(field, 'abc');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/search');
    });

    testWidgets('desktop top bar shows the avatar between search and the '
        'window buttons; signed out, tapping opens Log in', (tester) async {
      await pumpApp(tester, desktop);
      final avatar = find.byKey(const Key('shell.account'));
      expect(
        find.descendant(of: find.byType(TitleBar), matching: avatar),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('sidebar')), matching: avatar),
        findsNothing,
      );
      final rect = tester.getRect(avatar);
      final search = tester.getRect(find.byKey(const Key('shell.search')));
      final minimize = tester.getRect(find.byKey(const Key('window.minimize')));
      expect(rect.left, greaterThan(search.right));
      expect(rect.right, lessThanOrEqualTo(minimize.left));
      expect(rect.center.dy, closeTo(minimize.center.dy, 1));
      // Signed out: a person icon saying what it does.
      expect(find.byTooltip('Log in'), findsOneWidget);
      expect(
        find.descendant(
          of: avatar,
          matching: find.byIcon(Icons.person_outline_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(router.state.uri.path, isNot('/settings'));
    });

    testWidgets('without a custom title bar the avatar sits at the end of the '
        'search row', (tester) async {
      await pumpApp(tester, desktop, customTitleBar: false);
      final avatar = find.byKey(const Key('shell.account'));
      expect(avatar, findsOneWidget);
      expect(find.byType(AccountAvatar), findsOneWidget);
      final rect = tester.getRect(avatar);
      final search = tester.getRect(find.byKey(const Key('shell.search')));
      expect(rect.left, greaterThan(search.right));
      expect(rect.center.dy, closeTo(search.center.dy, 1));
      // At the right end of the main pane (8 px gap, 16 px padding).
      expect(rect.right, closeTo(desktop.width - 8 - 16, 1));
    });

    testWidgets('title bar is present when the flag is on', (tester) async {
      await pumpApp(tester, desktop);
      expect(find.byType(TitleBar), findsOneWidget);
      expect(window.maximizedQueried, isTrue);
    });

    testWidgets('window buttons call the window controls', (tester) async {
      await pumpApp(tester, desktop);
      for (final key in ['minimize', 'maximize', 'close']) {
        await tester.tap(find.byKey(Key('window.$key')));
      }
      expect(window.calls, ['minimize', 'maximizeOrRestore', 'close']);
    });

    testWidgets('player bar shows the track and drives the player', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      await startPlaying(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('playerBar')),
          matching: find.text('Title a'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('playerBar.playPause')));
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'pause');

      await tester.tap(find.byKey(const Key('playerBar.next')));
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'b');

      await tester.tap(find.byKey(const Key('playerBar.shuffle')));
      expect(player.state.shuffle, isTrue);
      await tester.tap(find.byKey(const Key('playerBar.repeat')));
      expect(player.state.repeat, RepeatMode.all);

      await tester.tap(find.byKey(const Key('playerBar.queue')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, nowPlayingLocation);
    });

    testWidgets('player bar is the surface blended with the tint at 40 %', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      final colors = colorsOf(tester, PlayerBar);
      final box = tester.widget<ColoredBox>(
        find.byKey(const Key('playerBar.background')),
      );
      expect(box.color, Color.lerp(colors.surface, colors.miniPlayer, 0.4));
      expect(
        tester.getSize(find.byKey(const Key('playerBar.background'))).width,
        1280,
      );
    });

    for (final key in ['playerBar.scrubber', 'playerBar.volume']) {
      testWidgets('hovering $key thickens it from 4 to 6 px and shows the '
          'thumb', (tester) async {
        await pumpApp(tester, desktop);
        await startPlaying(tester);
        backend.setDuration(const Duration(seconds: 200));
        await tester.pumpAndSettle();
        SliderThemeData theme() =>
            SliderTheme.of(tester.element(find.byKey(Key(key))));
        expect(theme().trackHeight, 4);
        expect(theme().thumbShape!.getPreferredSize(true, false).width, 0);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byKey(Key(key))));
        await tester.pumpAndSettle();
        expect(theme().trackHeight, 6);
        expect(
          theme().thumbShape!.getPreferredSize(true, false).width,
          greaterThan(0),
        );

        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(theme().trackHeight, 4);
      });
    }

    testWidgets('the times sit 12 px off the ends of the bar', (tester) async {
      await pumpApp(tester, desktop);
      await startPlaying(tester);
      backend.setDuration(const Duration(seconds: 200));
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const Key('playerBar.scrubber')));
      final elapsed = tester.getRect(find.text('0:00'));
      final total = tester.getRect(find.text('3:20'));
      expect(bar.left - elapsed.right, greaterThanOrEqualTo(12));
      expect(total.left - bar.right, greaterThanOrEqualTo(12));
    });

    testWidgets('the playing playlist row shows EqualizerBars', (tester) async {
      await pumpApp(tester, desktop);
      Finder bars(String id) => find.descendant(
        of: find.byKey(Key('sidebar.playlist.$id')),
        matching: find.byType(EqualizerBars),
      );
      expect(bars('p1'), findsNothing);

      unawaited(player.playQueue([track('a')], sourcePlaylistId: 'p1'));
      await tester.pump();
      await tester.pump();
      expect(bars('p1'), findsOneWidget);
      expect(bars('p2'), findsNothing);
      expect(tester.widget<EqualizerBars>(bars('p1')).playing, isTrue);

      unawaited(player.pause());
      await tester.pumpAndSettle();
      expect(tester.widget<EqualizerBars>(bars('p1')).playing, isFalse);
    });

    testWidgets('sidebar rows highlight on hover', (tester) async {
      await pumpApp(tester, desktop);
      Color? fill() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const Key('sidebar.hover.playlist.p1')),
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(fill()?.a ?? 0, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('sidebar.playlist.p1'))),
      );
      await tester.pumpAndSettle();
      expect(fill()!.a, greaterThan(0));
    });

    testWidgets('the hover fill comes from the theme text (light themes)', (
      tester,
    ) async {
      final light = ThemeSpec.builtInDefault.copyWith(
        base: 'light',
        background: const Color(0xFFFFFFFF),
        surface: const Color(0xFFF2F2F2),
        text: const Color(0xFF111111),
      );
      await pumpApp(tester, desktop, theme: light);
      final colors = colorsOf(tester, Sidebar);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('sidebar.playlist.p1'))),
      );
      await tester.pumpAndSettle();
      final fill =
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const Key('sidebar.hover.playlist.p1')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(fill, colors.text.withAlpha(13));
    });

    testWidgets('the selected playlist row fill comes from the theme text '
        '(light themes)', (tester) async {
      final light = ThemeSpec.builtInDefault.copyWith(
        base: 'light',
        background: const Color(0xFFFFFFFF),
        surface: const Color(0xFFF2F2F2),
        text: const Color(0xFF111111),
      );
      await pumpApp(tester, desktop, theme: light);
      final colors = colorsOf(tester, Sidebar);
      await tester.tap(find.byKey(const Key('sidebar.playlist.p1')));
      await tester.pumpAndSettle();
      final fill =
          (tester
                      .widget<Container>(
                        find.byKey(const Key('sidebar.fill.playlist.p1')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(fill, colors.text.withAlpha(20));
    });

    testWidgets('on a playlist page only the playlist row has the bar', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      await tester.tap(find.byKey(const Key('sidebar.library')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sidebar.selectionBar.library')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sidebar.playlist.p1')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/library/playlist/p1');
      expect(
        find.byKey(const Key('sidebar.selectionBar.playlists')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sidebar.selectionBar.library')),
        findsNothing,
      );
      expect(find.byKey(const Key('sidebar.selectionBar.nav')), findsNothing);
    });

    testWidgets('the selection bar slides between sidebar rows', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      final bar = find.byKey(const Key('sidebar.selectionBar.nav'));
      final homeTop = tester.getRect(bar).top;
      expect(
        tester.getRect(bar).center.dy,
        closeTo(tester.getCenter(find.byKey(const Key('sidebar.home'))).dy, 1),
      );

      await tester.tap(find.byKey(const Key('sidebar.search')));
      await tester.pump();
      await tester.pump(Motion.standard ~/ 2);
      final searchCentre = tester
          .getCenter(find.byKey(const Key('sidebar.search')))
          .dy;
      final mid = tester.getRect(bar).center.dy;
      expect(tester.getRect(bar).top, greaterThan(homeTop));
      expect(mid, lessThan(searchCentre - 1));

      await tester.pumpAndSettle();
      expect(tester.getRect(bar).center.dy, closeTo(searchCentre, 1));

      final rowElement = tester.element(
        find.byKey(const Key('sidebar.playlist.p1')),
      );
      // A playlist takes the selection: the nav bar goes, its own appears.
      await tester.tap(find.byKey(const Key('sidebar.playlist.p1')));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      final listBar = find.byKey(const Key('sidebar.selectionBar.playlists'));
      expect(
        tester.getRect(listBar).center.dy,
        closeTo(
          tester.getCenter(find.byKey(const Key('sidebar.playlist.p1'))).dy,
          1,
        ),
      );
      // The list was not rebuilt from scratch when the bar appeared.
      expect(
        tester.element(find.byKey(const Key('sidebar.playlist.p1'))),
        same(rowElement),
      );
    });

    testWidgets('volume slider sets the player volume', (tester) async {
      await pumpApp(tester, desktop);
      final rect = tester.getRect(find.byKey(const Key('playerBar.volume')));
      await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
      await tester.pumpAndSettle();
      expect(player.state.volume, closeTo(0.5, 0.15));
    });

    testWidgets('Space toggles playback when no text field has focus', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      await startPlaying(tester);
      backend.clearCalls();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(backend.calls, ['pause']);
    });

    testWidgets('Space in the search field does not toggle playback', (
      tester,
    ) async {
      await pumpApp(tester, desktop);
      await startPlaying(tester);
      backend.clearCalls();

      await tester.tap(find.byKey(const Key('shell.search')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(backend.calls, isEmpty);

      // The text field keeps working: a typed space ends up in its text.
      await tester.enterText(find.byKey(const Key('shell.search')), 'a b');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('shell.search')))
            .controller
            ?.text,
        'a b',
      );
    });

    testWidgets('Ctrl+Right / Ctrl+Left skip tracks', (tester) async {
      await pumpApp(tester, desktop);
      await startPlaying(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(player.state.current?.id, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(player.state.current?.id, 'a');
    });

    testWidgets('Ctrl+K focuses the search field', (tester) async {
      await pumpApp(tester, desktop);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const Key('shell.search')),
      );
      expect(field.focusNode?.hasFocus, isTrue);
    });
  });

  group('playback errors', () {
    const message = "Couldn't play — the song files are missing";

    for (final (name, size) in [
      ('phone', Size(400, 800)),
      ('desktop', Size(1280, 800)),
    ]) {
      testWidgets('$name: all files missing shows one island', (tester) async {
        await pumpApp(tester, size, resolver: _MissingResolver());
        unawaited(player.playQueue([track('a'), track('b')]));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);

        // Later state ticks with the same error do not repeat it.
        backend.setPosition(const Duration(seconds: 1));
        player.setShuffle(true);
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text(message), findsNothing);
        expect(player.state.error, PlayerService.noPlayableFilesError);
      });
    }

    testWidgets('an engine failing on every track says so', (tester) async {
      await pumpApp(tester, const Size(400, 800));
      unawaited(player.playQueue([track('a')]));
      await tester.pumpAndSettle();
      backend.emitError();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => pumpEventQueue());
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(player.state.error, PlayerService.engineFailedError);
      expect(find.text("Couldn't play these songs"), findsOneWidget);
      expect(find.text(message), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a second failed attempt shows it again', (tester) async {
      await pumpApp(tester, const Size(400, 800), resolver: _MissingResolver());
      unawaited(player.playQueue([track('a')]));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing); // timed out

      unawaited(player.playQueue([track('a')]));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('breakpoint: 719 is phone, 720 is desktop', (tester) async {
    await pumpApp(tester, const Size(719, 800));
    expect(find.byType(BottomNav), findsOneWidget);
    await pumpApp(tester, const Size(720, 800));
    expect(find.byType(BottomNav), findsNothing);
    expect(find.byType(DesktopShell), findsOneWidget);
  });
}
