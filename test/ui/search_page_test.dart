import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/motion/fade_slide_in.dart';
import 'package:songies/ui/motion/pressable.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/ui/ytm/ytm_song_row.dart';

import '../helpers/ui_harness.dart';

const _lucky = YtmSong(
  videoId: 'v1',
  title: 'Get Lucky',
  artists: [YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk')],
  album: 'Random Access Memories',
  albumBrowseId: 'MPREb_ram',
  durationMs: 369000,
);

const _around = YtmSong(
  videoId: 'v2',
  title: 'Around the World',
  artists: [YtmArtistRef(name: 'Daft Punk')],
);

const _video = YtmSong(
  videoId: 'v9',
  title: 'Get Lucky (Official Video)',
  artists: [YtmArtistRef(name: 'Daft Punk')],
  isVideo: true,
);

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpSearch(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (_, _) => const Scaffold(body: SearchPage()),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  /// A local song matching "daft", in a playlist.
  Future<void> seedLibrary(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1', title: 'One More Time', artist: 'Daft Punk');
    await h.addPlaylist('Dance', ['t1']);
  });

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('search.field')), text);
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
  }

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  /// Opens a tab, scrolling the tab row to it first (it scrolls on a phone).
  Future<void> openTab(WidgetTester tester, YtmSearchKind kind) async {
    final tab = find.byKey(Key('search.tab.${kind.name}'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await settle(tester);
  }

  uiTest('the empty query keeps "Search your library"', (tester) async {
    await pumpSearch(tester);
    expect(find.text('Search your library'), findsOneWidget);
    expect(find.byKey(const Key('search.tabs')), findsNothing);
    expect(h.ytm.calls, isEmpty);
  });

  uiTest('"daft" shows "In your library" first, then the tabs on Songs', (
    tester,
  ) async {
    await seedLibrary(tester);
    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky, _around]);
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    final library = find.text('In your library');
    expect(library, findsOneWidget);
    expect(find.text('One More Time'), findsOneWidget);
    final tabs = find.byKey(const Key('search.tabs'));
    expect(tabs, findsOneWidget);
    for (final label in ['Songs', 'Videos', 'Albums', 'Artists', 'Playlists']) {
      expect(
        find.descendant(of: tabs, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(top(tester, library), lessThan(top(tester, tabs)));
    expect(top(tester, tabs), lessThan(top(tester, find.text('Get Lucky'))));
    expect(
      tester.getSemantics(find.byKey(const Key('search.tab.songs'))),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('search.tab.videos'))),
      isSemantics(isSelected: false),
    );
    expect(h.ytm.calls, [('daft', YtmSearchKind.songs)]);
  });

  uiTest('without local matches there is no library section', (tester) async {
    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky]);
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);
    expect(find.text('In your library'), findsNothing);
    expect(find.text('Get Lucky'), findsOneWidget);
  });

  uiTest('tapping a song row plays it with radio', (tester) async {
    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky, _around]);
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    await tester.tap(find.text('Around the World'));
    await settle(tester);
    expect([for (final s in h.radio.played) s.videoId], ['v2']);
  });

  uiTest('a tab loads once and keeps its results for the query', (
    tester,
  ) async {
    h.ytm
      ..answer('daft', YtmSearchKind.songs, [_lucky])
      ..answer('daft', YtmSearchKind.videos, [_video]);
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    await openTab(tester, YtmSearchKind.videos);
    expect(find.text('Get Lucky (Official Video)'), findsOneWidget);
    expect(find.text('Get Lucky'), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const Key('search.tab.videos'))),
      isSemantics(isSelected: true),
    );

    await openTab(tester, YtmSearchKind.songs);
    expect(find.text('Get Lucky'), findsOneWidget);
    await openTab(tester, YtmSearchKind.videos);
    expect(find.text('Get Lucky (Official Video)'), findsOneWidget);
    expect(h.ytm.calls, [
      ('daft', YtmSearchKind.songs),
      ('daft', YtmSearchKind.videos),
    ]);
  });

  uiTest('albums, artists and playlists tabs list their results', (
    tester,
  ) async {
    h.ytm
      ..answer('daft', YtmSearchKind.albums, [
        const YtmAlbum(browseId: 'MPREb_d', title: 'Discovery', year: '2001'),
      ])
      ..answer('daft', YtmSearchKind.artists, [
        const YtmArtist(browseId: 'UCdaft', name: 'Daft Punk'),
      ])
      ..answer('daft', YtmSearchKind.playlists, [
        const YtmPlaylist(browseId: 'VLPLx', title: 'Daft mix', author: 'Me'),
      ]);
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    await openTab(tester, YtmSearchKind.albums);
    expect(find.byKey(const Key('ytm.album.MPREb_d')), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);

    await openTab(tester, YtmSearchKind.artists);
    expect(find.byKey(const Key('ytm.artist.UCdaft')), findsOneWidget);

    await openTab(tester, YtmSearchKind.playlists);
    expect(find.byKey(const Key('ytm.playlist.VLPLx')), findsOneWidget);
    expect(find.text('Daft mix'), findsOneWidget);
  });

  uiTest('typing fast shows only the last query, even if it answers first', (
    tester,
  ) async {
    final da = Completer<void>();
    final daft = Completer<void>();
    h.ytm
      ..answer('da', YtmSearchKind.songs, [_around])
      ..answer('daft', YtmSearchKind.songs, [_lucky])
      ..gates[('da', YtmSearchKind.songs)] = da
      ..gates[('daft', YtmSearchKind.songs)] = daft;
    await pumpSearch(tester);

    await type(tester, 'da');
    await type(tester, 'daft');
    expect(h.ytm.calls, [
      ('da', YtmSearchKind.songs),
      ('daft', YtmSearchKind.songs),
    ]);

    daft.complete();
    await settle(tester);
    expect(find.text('Get Lucky'), findsOneWidget);

    // "da" answers last; its late results are dropped.
    da.complete();
    await settle(tester);
    expect(find.text('Get Lucky'), findsOneWidget);
    expect(find.text('Around the World'), findsNothing);
  });

  uiTest('a query typed during the debounce never goes out', (tester) async {
    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky]);
    await pumpSearch(tester);
    await tester.enterText(find.byKey(const Key('search.field')), 'da');
    await tester.pump(const Duration(milliseconds: 50));
    await type(tester, 'daft');
    await settle(tester);
    expect(h.ytm.calls, [('daft', YtmSearchKind.songs)]);
  });

  uiTest('offline says so and keeps the library results', (tester) async {
    await seedLibrary(tester);
    h.network.kind = NetworkKind.offline;
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('In your library'), findsOneWidget);
    expect(find.text('One More Time'), findsOneWidget);
    expect(h.ytm.calls, isEmpty);
  });

  uiTest('a network failure while offline says offline', (tester) async {
    h.ytm.answers[('daft', YtmSearchKind.songs)] = const Err(
      Failure(FailureKind.network, 'no route'),
    );
    final gate = Completer<void>();
    h.ytm.gates[('daft', YtmSearchKind.songs)] = gate;
    await pumpSearch(tester);
    await type(tester, 'daft');
    h.network.kind = NetworkKind.offline;
    gate.complete();
    await settle(tester);
    expect(find.text("You're offline"), findsOneWidget);
  });

  uiTest('an error offers Retry, which refetches', (tester) async {
    await seedLibrary(tester);
    h.ytm.answers[('daft', YtmSearchKind.songs)] = const Err(
      Failure(FailureKind.unknown, 'bad JSON'),
    );
    await pumpSearch(tester);
    await type(tester, 'daft');
    await settle(tester);

    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('One More Time'), findsOneWidget);
    // Nothing retries on its own.
    await tester.pump(const Duration(seconds: 30));
    await settle(tester);
    expect(h.ytm.calls, hasLength(1));

    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky]);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await settle(tester);
    expect(find.text("Couldn't load"), findsNothing);
    expect(find.text('Get Lucky'), findsOneWidget);
    expect(h.ytm.calls, hasLength(2));
  });

  uiTest('an empty answer says nothing matches', (tester) async {
    await pumpSearch(tester);
    await type(tester, 'zzz');
    await settle(tester);
    expect(find.text("Nothing matches 'zzz'"), findsOneWidget);
  });

  uiTest('rows press and fade in with distinct ids; then nothing animates', (
    tester,
  ) async {
    await seedLibrary(tester);
    h.ytm.answer('daft', YtmSearchKind.songs, [_lucky, _around]);
    await pumpSearch(tester);
    // Through the provider, so no focused field blinks a cursor.
    ProviderScope.containerOf(tester.element(find.byType(SearchPage)))
        .read(searchQueryProvider.notifier)
        .set('daft');
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await settle(tester);

    for (final key in [
      const Key('search.song.t1'),
      const Key('ytm.song.v1'),
      const Key('ytm.song.v2'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
      expect(tester.widget(find.byKey(key)), isA<Pressable>());
      expect(
        find.ancestor(of: find.byKey(key), matching: find.byType(FadeSlideIn)),
        findsOneWidget,
      );
    }
    expect(find.byType(YtmSongRow), findsNWidgets(2));
    final ids = [
      for (final w in tester.widgetList<FadeSlideIn>(find.byType(FadeSlideIn)))
        w.id,
    ];
    expect(ids, everyElement(isNotNull));
    expect(ids.toSet(), hasLength(ids.length));

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('library section', () {
    /// 10 songs and 3 playlists matching "daft".
    Future<void> seedMany(WidgetTester tester) => real(tester, () async {
      final ids = [for (var i = 1; i <= 10; i++) 't$i'];
      for (final (i, id) in ids.indexed) {
        await h.addTrack(id, title: 'Daft song ${i + 1}', artist: 'Daft Punk');
      }
      for (final name in ['Daft A', 'Daft B', 'Daft C']) {
        await h.addPlaylist(name, ids);
      }
    });

    Future<void> search(WidgetTester tester) async {
      h.ytm.answer('daft', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, size: const Size(400, 700));
      await type(tester, 'daft');
      await settle(tester);
    }

    Iterable<String> shownLibraryRows(WidgetTester tester) => [
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    ((w.key! as ValueKey<String>).value.startsWith(
                          'search.song.',
                        ) ||
                        (w.key! as ValueKey<String>).value.startsWith(
                          'search.playlist.',
                        )),
                skipOffstage: false,
              )
              .evaluate())
        (e.widget.key! as ValueKey<String>).value,
    ];

    uiTest('shows only a few matches, with the tabs on the first screen', (
      tester,
    ) async {
      await seedMany(tester);
      await search(tester);

      final rows = shownLibraryRows(tester).toList();
      expect(rows.where((k) => k.startsWith('search.song.')), hasLength(3));
      expect(rows.where((k) => k.startsWith('search.playlist.')), hasLength(2));
      expect(find.text('Show all (8 more)'), findsOneWidget);
      final tabs = find.byKey(const Key('search.tabs'));
      expect(tabs, findsOneWidget);
      expect(tester.getBottomLeft(tabs).dy, lessThanOrEqualTo(700));
      expect(
        tester.getBottomLeft(find.byKey(const Key('search.tab.songs'))).dy,
        lessThanOrEqualTo(700),
      );
    });

    uiTest('"Show all" reveals the rest in place', (tester) async {
      await seedMany(tester);
      await search(tester);

      await tester.tap(find.byKey(const Key('search.library.showAll')));
      await settle(tester);

      final rows = shownLibraryRows(tester).toList();
      expect(rows.where((k) => k.startsWith('search.song.')), hasLength(10));
      expect(rows.where((k) => k.startsWith('search.playlist.')), hasLength(3));
      expect(find.byKey(const Key('search.library.showAll')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });

    uiTest('a few matches need no "Show all"', (tester) async {
      await seedLibrary(tester);
      await search(tester);
      expect(find.byKey(const Key('search.library.showAll')), findsNothing);
      expect(find.text('One More Time'), findsOneWidget);
    });
  });
}
