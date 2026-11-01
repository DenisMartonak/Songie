import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/ui/motion/pressable.dart';
import 'package:songies/ui/ytm/ytm_song_row.dart';

import '../../helpers/ui_harness.dart';

const _lucky = YtmSong(
  videoId: 'v1',
  title: 'Get Lucky',
  artists: [
    YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk'),
    YtmArtistRef(name: 'Pharrell Williams'),
  ],
  album: 'Random Access Memories',
  albumBrowseId: 'MPREb_ram',
  durationMs: 369000,
);

/// A song YouTube gave no artist or album ids for.
const _bare = YtmSong(
  videoId: 'v2',
  title: 'Untitled',
  artists: [YtmArtistRef(name: 'Someone')],
  album: 'Somewhere',
);

const _menuItems = [
  'Add to queue',
  'Add to playlist',
  'Go to artist',
  'Go to album',
  'Start radio',
];

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpRow(
    WidgetTester tester,
    YtmSong song, {
    VoidCallback? onTap,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/page',
        routes: [
          GoRoute(
            path: '/page',
            builder: (_, _) => Scaffold(
              body: ListView(
                children: [YtmSongRow(song: song, onTap: onTap)],
              ),
            ),
          ),
          for (final kind in ['artist', 'album'])
            GoRoute(
              path: '/ytm/$kind/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('$kind ${s.pathParameters['id']}')),
            ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester, YtmSong song) async {
    await tester.tap(find.byKey(Key('ytm.song.menu.${song.videoId}')));
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await settle(tester);
  }

  List<String> queueTitles() => [for (final t in h.player.state.queue) t.title];

  uiTest('shows the title, artists, album and duration', (tester) async {
    await pumpRow(tester, _lucky);
    expect(find.text('Get Lucky'), findsOneWidget);
    expect(
      find.text('Daft Punk, Pharrell Williams · Random Access Memories'),
      findsOneWidget,
    );
    expect(find.text('6:09'), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('ytm.song.v1'))),
      isA<Pressable>(),
    );
  });

  uiTest('a tap plays the song with radio', (tester) async {
    await pumpRow(tester, _lucky);
    await tester.tap(find.text('Get Lucky'));
    await settle(tester);
    expect([for (final s in h.radio.played) s.videoId], ['v1']);
  });

  uiTest('a given onTap replaces the radio', (tester) async {
    var taps = 0;
    await pumpRow(tester, _lucky, onTap: () => taps++);
    await tester.tap(find.text('Get Lucky'));
    await settle(tester);
    expect(taps, 1);
    expect(h.radio.played, isEmpty);
  });

  uiTest('the menu offers every action', (tester) async {
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    for (final item in _menuItems) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  });

  uiTest('Go to artist and Go to album hide without their ids', (tester) async {
    await pumpRow(tester, _bare);
    await openMenu(tester, _bare);
    expect(find.text('Go to artist'), findsNothing);
    expect(find.text('Go to album'), findsNothing);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Start radio'), findsOneWidget);
  });

  uiTest('Add to queue stores the song and queues it', (tester) async {
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    await choose(tester, 'Add to queue');
    expect(h.ytStore.upserted, ['v1']);
    expect(queueTitles(), ['Get Lucky']);
    expect(h.radio.played, isEmpty);
  });

  uiTest('Add to playlist stores the song and opens the playlist picker', (
    tester,
  ) async {
    late String gym;
    await real(tester, () async {
      await h.addTrack('t1');
      gym = await h.addPlaylist('Gym', ['t1']);
      await h.addPlaylist('Chill', ['t1']);
    });
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    await choose(tester, 'Add to playlist');

    expect(h.ytStore.upserted, ['v1']);
    expect(find.byKey(const Key('addToPlaylist.sheet')), findsOneWidget);
    expect(find.text('Chill'), findsOneWidget);
    await tester.tap(find.text('Gym'));
    await settle(tester);

    expect(find.byKey(const Key('addToPlaylist.sheet')), findsNothing);
    expect(find.text('Added to Gym'), findsOneWidget);
    final order = await real(tester, () => h.orderOf(gym));
    expect(order, hasLength(2));
    expect(order.first, 't1');
  });

  uiTest('Go to album opens the album page', (tester) async {
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    await choose(tester, 'Go to album');
    expect(find.text('album MPREb_ram'), findsOneWidget);
  });

  uiTest('Go to artist opens the first artist with an id', (tester) async {
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    await choose(tester, 'Go to artist');
    expect(find.text('artist UCdaft'), findsOneWidget);
  });

  uiTest('Start radio plays the song with radio', (tester) async {
    await pumpRow(tester, _lucky);
    await openMenu(tester, _lucky);
    await choose(tester, 'Start radio');
    expect([for (final s in h.radio.played) s.videoId], ['v1']);
  });
}
