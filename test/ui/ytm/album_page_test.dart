import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/cover_palette.dart';
import 'package:songies/ui/motion/shimmer.dart';
import 'package:songies/ui/ytm/album_page.dart';
import 'package:songies/ui/ytm/ytm_playlist_page.dart';
import 'package:songies/youtube/yt_import_service.dart';

import '../../helpers/ui_harness.dart';

YtmSong _track(String id) => YtmSong(
  videoId: id,
  title: 'Song $id',
  artists: const [YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk')],
  album: 'Discovery',
  albumBrowseId: 'MPREb_x',
  durationMs: 200000,
);

YtmAlbumPage _album({String? playlistId = 'OLAK5uy_disc', String? thumb}) =>
    YtmAlbumPage(
      YtmAlbum(
        browseId: 'MPREb_x',
        title: 'Discovery',
        artist: 'Daft Punk',
        year: '2001',
        thumbnailUrl: thumb,
        playlistId: playlistId,
      ),
      [for (var i = 1; i <= 4; i++) _track('t$i')],
    );

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(400, 1600),
    bool settleAfter = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/page',
        routes: [
          GoRoute(
            path: '/page',
            builder: (_, _) => Scaffold(body: page),
          ),
          GoRoute(
            path: '/library/playlist/:id',
            builder: (_, s) =>
                Scaffold(body: Text('Playlist ${s.pathParameters['id']}')),
          ),
        ],
      ),
    );
    if (settleAfter) {
      await settle(tester);
    } else {
      await flush(tester);
    }
  }

  List<String?> queuedVideos() => [
    for (final t in h.player.state.queue) t.ytVideoId,
  ];

  group('album page', () {
    uiTest('shows the cover, title, artist, year and tracklist', (
      tester,
    ) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      expect(find.byKey(const Key('ytm.hero.cover')), findsOneWidget);
      expect(find.text('Discovery'), findsOneWidget);
      expect(find.text('Daft Punk · 2001'), findsOneWidget);
      for (var i = 1; i <= 4; i++) {
        expect(find.byKey(Key('ytm.song.t$i')), findsOneWidget);
      }
    });

    uiTest('tapping track 3 plays the album from it, without radio', (
      tester,
    ) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      await tester.tap(find.byKey(const Key('ytm.song.t3')));
      await settle(tester);

      expect(queuedVideos(), ['t1', 't2', 't3', 't4']);
      expect(h.player.state.index, 2);
      expect(h.player.state.current?.ytVideoId, 't3');
      expect(h.radio.played, isEmpty);
      expect(h.radio.started, isEmpty);
    });

    uiTest('Play plays the album from the top', (tester) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      await tester.tap(find.byKey(const Key('ytm.play')));
      await settle(tester);

      expect(h.player.state.shuffle, isFalse);
      expect(queuedVideos(), ['t1', 't2', 't3', 't4']);
      expect(h.player.state.index, 0);
    });

    uiTest('Shuffle plays the album shuffled', (tester) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      await tester.tap(find.byKey(const Key('ytm.shuffle')));
      await settle(tester);

      expect(h.player.state.shuffle, isTrue);
      expect(queuedVideos().toSet(), {'t1', 't2', 't3', 't4'});
      expect(h.radio.played, isEmpty);
    });

    uiTest('Import as playlist imports the album\'s playlist and offers to '
        'open it', (tester) async {
      h.importService.onImport = (_) async => const Ok(
        ImportResult(playlistId: 'p1', alreadyExisted: false, added: 4),
      );
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      await tester.tap(find.byKey(const Key('ytm.import')));
      await settle(tester);

      expect(h.importService.imported, [
        'https://music.youtube.com/playlist?list=OLAK5uy_disc',
      ]);
      expect(find.text('Imported 4 songs'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('Playlist p1'), findsOneWidget);
    });

    uiTest('an import that fails says why', (tester) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      await tester.tap(find.byKey(const Key('ytm.import')));
      await settle(tester);

      expect(h.importService.imported, hasLength(1));
      expect(find.text('Open'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    uiTest('an album playlist id that is not OLAK5uy_ hides Import', (
      tester,
    ) async {
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album(playlistId: 'PLnotanalbum'));
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));
      expect(find.byKey(const Key('ytm.import')), findsNothing);
      expect(find.byKey(const Key('ytm.play')), findsOneWidget);
    });

    uiTest('while loading it shows skeletons', (tester) async {
      final gate = Completer<void>();
      h.ytm.browseGate = gate;
      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await pumpPage(
        tester,
        const AlbumPage(browseId: 'MPREb_x'),
        settleAfter: false,
      );
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text('Discovery'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(find.text('Discovery'), findsOneWidget);
    });

    uiTest('a load error shows Couldn\'t load with Retry', (tester) async {
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));
      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      h.ytm.albumAnswers['MPREb_x'] = Ok(_album());
      await tester.tap(find.byKey(const Key('ytm.retry')));
      await settle(tester);
      expect(find.text('Discovery'), findsOneWidget);
    });

    uiTest('a near-white cover still leaves the hero text readable', (
      tester,
    ) async {
      h.ytmPalette = (url) async => url == 'https://art.test/white.jpg'
          ? const CoverPalette(
              dominant: Color(0xFFF6F4EE),
              vibrant: Color(0xFFE02060),
              muted: Color(0xFFDDDDDD),
            )
          : null;
      h.ytm.albumAnswers['MPREb_x'] = Ok(
        _album(thumb: 'https://art.test/white.jpg'),
      );
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));

      final hero = tester.widget<DecoratedBox>(
        find.byKey(const Key('ytm.heroBackground')),
      );
      final top =
          ((hero.decoration as BoxDecoration).gradient! as LinearGradient)
              .colors
              .first;
      final colors = Theme.of(tester.element(find.byType(AlbumPage)))
          .extension<SongiesColors>()!;
      // Cover-derived, not the plain background.
      expect(top, isNot(colors.background));
      expect(contrastRatio(colors.text, top), greaterThanOrEqualTo(4.5));
    });
  });

  group('YouTube Music playlist page', () {
    YtmPlaylistPage firstPage() => YtmPlaylistPage(
      const YtmPlaylist(
        browseId: 'VLPLabc',
        title: 'Chill Mix',
        author: 'Someone',
      ),
      [for (var i = 1; i <= 30; i++) _track('p$i')],
      'C1',
    );

    uiTest('shows the tracklist and loads the continuation once at the end', (
      tester,
    ) async {
      h.ytm.playlistAnswers['VLPLabc'] = Ok(firstPage());
      h.ytm.playlistAnswers['VLPLabc@C1'] = Ok(
        YtmPlaylistPage(const YtmPlaylist(browseId: 'VLPLabc', title: ''), [
          for (var i = 31; i <= 35; i++) _track('p$i'),
        ], null),
      );
      await pumpPage(
        tester,
        const YtmPlaylistScreen(browseId: 'VLPLabc'),
        size: const Size(400, 800),
      );

      expect(find.text('Chill Mix'), findsOneWidget);
      expect(find.byKey(const Key('ytm.song.p1')), findsOneWidget);
      expect(h.ytm.browseCalls, ['playlist:VLPLabc']);

      await tester.scrollUntilVisible(
        find.byKey(const Key('ytm.song.p35')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await settle(tester);

      expect(find.byKey(const Key('ytm.song.p35')), findsOneWidget);
      expect(h.ytm.browseCalls, ['playlist:VLPLabc', 'playlist:VLPLabc@C1']);
      // The continuation's empty stub title never replaces the playlist's.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await settle(tester);
      expect(find.text('Chill Mix'), findsOneWidget);
    });

    uiTest('a tapped song plays the playlist from it', (tester) async {
      h.ytm.playlistAnswers['VLPLabc'] = Ok(firstPage());
      await pumpPage(tester, const YtmPlaylistScreen(browseId: 'VLPLabc'));

      await tester.tap(find.byKey(const Key('ytm.song.p2')));
      await settle(tester);
      expect(h.player.state.index, 1);
      expect(queuedVideos().take(3), ['p1', 'p2', 'p3']);
      expect(h.radio.played, isEmpty);
    });

    uiTest('Import as playlist uses the playlist\'s URL', (tester) async {
      h.importService.onImport = (_) async => const Ok(
        ImportResult(playlistId: 'p9', alreadyExisted: true, added: 0),
      );
      h.ytm.playlistAnswers['VLPLabc'] = Ok(firstPage());
      await pumpPage(tester, const YtmPlaylistScreen(browseId: 'VLPLabc'));

      await tester.tap(find.byKey(const Key('ytm.import')));
      await settle(tester);

      expect(h.importService.imported, [
        'https://music.youtube.com/playlist?list=PLabc',
      ]);
      expect(
        find.text('Already in your library — use Sync to update it'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('Playlist p9'), findsOneWidget);
    });

    uiTest('a load error shows Couldn\'t load with Retry', (tester) async {
      await pumpPage(tester, const YtmPlaylistScreen(browseId: 'VLPLabc'));
      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
