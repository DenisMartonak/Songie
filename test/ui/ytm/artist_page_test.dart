import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/ui/ytm/artist_page.dart';

import '../../helpers/ui_harness.dart';

const _daft = YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk');

YtmSong _song(int i) => YtmSong(
  videoId: 's$i',
  title: 'Top $i',
  artists: const [_daft],
  durationMs: 200000,
);

final _page = YtmArtistPage(
  artist: const YtmArtist(browseId: 'UCdaft', name: 'Daft Punk'),
  topSongs: [for (var i = 1; i <= 7; i++) _song(i)],
  albums: const [
    YtmAlbum(browseId: 'MPREb_ram', title: 'Random Access Memories'),
  ],
  singles: const [YtmAlbum(browseId: 'MPREb_one', title: 'One More Time')],
  similar: const [YtmArtist(browseId: 'UCjustice', name: 'Justice')],
  radioPlaylistId: 'RDEMdaft',
);

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/artist',
        routes: [
          GoRoute(
            path: '/artist',
            builder: (_, _) =>
                const Scaffold(body: ArtistPage(browseId: 'UCdaft')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  List<String?> queuedVideos() => [
    for (final t in h.player.state.queue) t.ytVideoId,
  ];

  uiTest('shows the artist, five top songs, albums, singles and similar', (
    tester,
  ) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(_page);
    await pumpPage(tester);

    expect(find.text('Daft Punk'), findsWidgets);
    expect(find.text('Top songs'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.byKey(Key('ytm.song.s$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('ytm.song.s6')), findsNothing);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.byKey(const Key('ytm.card.album.MPREb_ram')), findsOneWidget);
    expect(find.text('Singles'), findsOneWidget);
    expect(find.byKey(const Key('ytm.card.album.MPREb_one')), findsOneWidget);
    expect(find.text('Fans also like'), findsOneWidget);
    expect(find.byKey(const Key('ytm.card.artist.UCjustice')), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await settle(tester);
    expect(find.byKey(const Key('ytm.song.s6')), findsOneWidget);
    expect(find.byKey(const Key('ytm.song.s7')), findsOneWidget);
  });

  uiTest('five top songs or fewer: no Show all', (tester) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(
      YtmArtistPage(
        artist: _page.artist,
        topSongs: [for (var i = 1; i <= 5; i++) _song(i)],
      ),
    );
    await pumpPage(tester);
    expect(find.text('Show all'), findsNothing);
    // Missing shelves are left out.
    expect(find.text('Albums'), findsNothing);
    expect(find.text('Fans also like'), findsNothing);
  });

  uiTest('Play plays the top songs in order', (tester) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(_page);
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ytm.play')));
    await settle(tester);

    expect(queuedVideos(), [for (var i = 1; i <= 7; i++) 's$i']);
    expect(h.player.state.index, 0);
    expect(h.player.state.shuffle, isFalse);
    expect(h.radio.played, isEmpty);
    expect(h.radio.started, isEmpty);
  });

  uiTest('a top song plays the top songs from that song, without radio', (
    tester,
  ) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(_page);
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ytm.song.s2')));
    await settle(tester);

    expect(queuedVideos(), [for (var i = 1; i <= 7; i++) 's$i']);
    expect(h.player.state.index, 1);
    expect(h.radio.played, isEmpty);
  });

  uiTest('Radio starts the artist\'s radio playlist', (tester) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(_page);
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ytm.radio')));
    await settle(tester);

    expect([for (final t in h.radio.started) t.ytVideoId], ['s1']);
    expect(h.radio.startedPlaylists, ['RDEMdaft']);
  });

  uiTest('an artist without a radio has no Radio button', (tester) async {
    h.ytm.artistAnswers['UCdaft'] = Ok(
      YtmArtistPage(artist: _page.artist, topSongs: _page.topSongs),
    );
    await pumpPage(tester);
    expect(find.byKey(const Key('ytm.radio')), findsNothing);
    expect(find.byKey(const Key('ytm.play')), findsOneWidget);
  });

  uiTest('a load error shows Couldn\'t load with Retry', (tester) async {
    await pumpPage(tester);
    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    h.ytm.artistAnswers['UCdaft'] = Ok(_page);
    await tester.tap(find.byKey(const Key('ytm.retry')));
    await settle(tester);
    expect(find.text('Top songs'), findsOneWidget);
    expect(h.ytm.browseCalls, ['artist:UCdaft', 'artist:UCdaft']);
  });
}
