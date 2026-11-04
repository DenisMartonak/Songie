import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/playlist/playlist_page.dart' show playlistHeroTop;
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

/// A 16x16 PNG of one colour.
Uint8List _solidPng(int r, int g, int b) {
  final image = img.Image(width: 16, height: 16);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

/// An in-memory cover that counts how often it is loaded (decoded), which
/// for a network image is how often it would be requested.
class _CountingImage extends MemoryImage {
  _CountingImage(super.bytes);

  // A list, so the (immutable) provider can still count.
  final List<void> _loads = [];

  int get loads => _loads.length;

  @override
  ImageStreamCompleter loadImage(MemoryImage key, ImageDecoderCallback decode) {
    _loads.add(null);
    return super.loadImage(key, decode);
  }
}

/// Lets the image decode and the palette isolate finish on the real clock.
Future<void> _waitForPalette(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
  }
}

Color _heroTop(WidgetTester tester) {
  final hero = tester.widget<DecoratedBox>(
    find.byKey(const Key('ytm.heroBackground')),
  );
  return ((hero.decoration as BoxDecoration).gradient! as LinearGradient)
      .colors
      .first;
}

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(400, 1600),
    bool settleAfter = true,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        extraOverrides: extraOverrides,
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
      expect(find.byKey(const Key('island')), findsOneWidget);
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
      final cover = _CountingImage(_solidPng(0xF6, 0xF4, 0xEE));
      h.ytmImages = (url, _) => url == 'https://art.test/white.jpg'
          ? cover
          : throw StateError('unexpected image $url');
      h.ytm.albumAnswers['MPREb_x'] = Ok(
        _album(thumb: 'https://art.test/white.jpg'),
      );
      await pumpPage(tester, const AlbumPage(browseId: 'MPREb_x'));
      await _waitForPalette(tester);

      final top = _heroTop(tester);
      final colors = Theme.of(tester.element(find.byType(AlbumPage)))
          .extension<SongiesColors>()!;
      // Derived from the cover the hero shows.
      expect(top, playlistHeroTop(const Color(0xFFF6F4EE), colors));
      expect(contrastRatio(colors.text, top), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(colors.mutedText, top), greaterThanOrEqualTo(4.5));
    });

    uiTest('the palette comes from the shown image: opening the page again '
        'loads nothing more, and nothing is written to the art cache', (
      tester,
    ) async {
      final artDir = Directory.systemTemp.createTempSync('songies-art');
      addTearDown(() => artDir.deleteSync(recursive: true));
      final cover = _CountingImage(_solidPng(0x33, 0x55, 0x77));
      h.ytmImages = (url, _) => cover;
      h.ytm.albumAnswers['MPREb_x'] = Ok(
        _album(thumb: 'https://art.test/cover.jpg'),
      );
      await pumpPage(
        tester,
        const AlbumPage(browseId: 'MPREb_x'),
        extraOverrides: [artCacheProvider.overrideWithValue(ArtCache(artDir))],
      );
      await _waitForPalette(tester);
      final colors = Theme.of(tester.element(find.byType(AlbumPage)))
          .extension<SongiesColors>()!;
      expect(
        _heroTop(tester),
        playlistHeroTop(const Color(0xFF335577), colors),
      );
      expect(cover.loads, 1);

      // Away and back: the page and its palette are built again.
      final router = GoRouter.of(tester.element(find.byType(AlbumPage)));
      router.go('/library/playlist/p1');
      await settle(tester);
      expect(find.byType(AlbumPage), findsNothing);
      router.go('/page');
      await settle(tester);
      await _waitForPalette(tester);

      expect(
        _heroTop(tester),
        playlistHeroTop(const Color(0xFF335577), colors),
      );
      expect(cover.loads, 1, reason: 'no second load (request) of the cover');
      expect(artDir.listSync(recursive: true), isEmpty);
      // No thumbnail was fetched through the track store either.
      expect(h.ytStore.upserted, isEmpty);
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

    YtmPlaylistPage more(List<String> ids, String? next) => YtmPlaylistPage(
      const YtmPlaylist(browseId: 'VLPLabc', title: ''),
      [for (final id in ids) _track(id)],
      next,
    );

    Future<void> scrollToTheEnd(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await settle(tester);
      }
    }

    uiTest('paging stops at an empty page, even with a new token', (
      tester,
    ) async {
      h.ytm.playlistAnswers['VLPLabc'] = Ok(firstPage());
      h.ytm.playlistAnswers['VLPLabc@C1'] = Ok(more(const [], 'C2'));
      h.ytm.playlistAnswers['VLPLabc@C2'] = Ok(more(['p31'], null));
      await pumpPage(
        tester,
        const YtmPlaylistScreen(browseId: 'VLPLabc'),
        size: const Size(400, 800),
      );
      await scrollToTheEnd(tester);
      expect(h.ytm.browseCalls, ['playlist:VLPLabc', 'playlist:VLPLabc@C1']);
    });

    uiTest('paging stops at a token seen before', (tester) async {
      h.ytm.playlistAnswers['VLPLabc'] = Ok(firstPage());
      h.ytm.playlistAnswers['VLPLabc@C1'] = Ok(more(['p31'], 'C2'));
      h.ytm.playlistAnswers['VLPLabc@C2'] = Ok(more(['p32'], 'C1'));
      await pumpPage(
        tester,
        const YtmPlaylistScreen(browseId: 'VLPLabc'),
        size: const Size(400, 800),
      );
      await scrollToTheEnd(tester);
      expect(h.ytm.browseCalls, [
        'playlist:VLPLabc',
        'playlist:VLPLabc@C1',
        'playlist:VLPLabc@C2',
      ]);
      expect(find.byKey(const Key('ytm.song.p32')), findsOneWidget);
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
