import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/search/search_page.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  late GoRouter router;

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(400, 800),
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
          for (final branch in ['home', 'search'])
            GoRoute(
              path: '/$branch/playlist/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Playlist ${s.pathParameters['id']}')),
            ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Settings stub')),
          ),
        ],
      ),
    );
    router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    await settle(tester);
  }

  Future<Track> trackById(WidgetTester tester, String id) => real(
    tester,
    () => (h.db.select(h.db.tracks)..where((t) => t.id.equals(id))).getSingle(),
  );

  Future<void> play(WidgetTester tester, String trackId, {String? from}) async {
    final track = await trackById(tester, trackId);
    await real(
      tester,
      () => h.player.playQueue([track], sourcePlaylistId: from),
    );
    await settle(tester);
  }

  group('greeting', () {
    test('changes at 05, 12 and 18 o-clock', () {
      String at(int hour, [int minute = 0]) =>
          greetingFor(DateTime(2026, 10, 21, hour, minute));
      expect(at(4, 59), 'Good evening');
      expect(at(5), 'Good morning');
      expect(at(11, 59), 'Good morning');
      expect(at(12), 'Good afternoon');
      expect(at(17, 59), 'Good afternoon');
      expect(at(18), 'Good evening');
      expect(at(0), 'Good evening');
    });
  });

  group('HomePage', () {
    uiTest('greets "Good morning" at 09:00 on the injected clock', (
      tester,
    ) async {
      h.now = () => DateTime(2026, 10, 21, 9);
      await pumpPage(tester, const HomePage());
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Good evening'), findsNothing);
    });

    uiTest('lists the last played tracks, newest first', (tester) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'First song');
        await h.addTrack('t2', title: 'Second song');
        await h.addTrack('t3', title: 'Never played');
      });
      await pumpPage(tester, const HomePage());
      expect(find.text('Recently played'), findsNothing);

      await play(tester, 't1');
      await play(tester, 't2');

      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Never played'), findsNothing);
      final first = tester.getTopLeft(find.text('First song')).dy;
      final second = tester.getTopLeft(find.text('Second song')).dy;
      expect(second, lessThan(first));
    });

    uiTest('replaying a track moves it to the top without duplicating', (
      tester,
    ) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'First song');
        await h.addTrack('t2', title: 'Second song');
      });
      await pumpPage(tester, const HomePage());
      await play(tester, 't1');
      await play(tester, 't2');
      await play(tester, 't1');

      expect(find.text('First song'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('First song')).dy,
        lessThan(tester.getTopLeft(find.text('Second song')).dy),
      );
    });

    Finder tiles() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('home.tile.'),
    );

    List<String> tileIds(WidgetTester tester) => [
      for (final w in tester.widgetList(tiles()))
        (w.key! as ValueKey<String>).value.substring('home.tile.'.length),
    ];

    uiTest('shows at most 6 quick tiles, recently played playlists first', (
      tester,
    ) async {
      final ids = <String>[];
      await real(tester, () async {
        await h.addTrack('t1');
        // Alphabetical order is P1 .. P8.
        for (var i = 1; i <= 8; i++) {
          ids.add(await h.addPlaylist('P$i', ['t1']));
        }
      });
      await pumpPage(tester, const HomePage());
      expect(tileIds(tester), ids.take(6).toList());

      await play(tester, 't1', from: ids[7]);
      await play(tester, 't1', from: ids[6]);

      final shown = tileIds(tester);
      expect(shown, hasLength(6));
      expect(shown.take(2), [ids[6], ids[7]]);
      expect(shown.skip(2), ids.take(4));
    });

    uiTest('tapping a tile opens the playlist', (tester) async {
      late String id;
      await real(tester, () async {
        await h.addTrack('t1');
        id = await h.addPlaylist('Road trip', ['t1']);
      });
      await pumpPage(tester, const HomePage());
      await tester.tap(find.byKey(Key('home.tile.$id')));
      await settle(tester);
      expect(find.text('Playlist $id'), findsOneWidget);
    });

    uiTest('lists the playlists as cards', (tester) async {
      late String id;
      await real(tester, () async {
        await h.addTrack('t1');
        id = await h.addPlaylist('Road trip', ['t1']);
      });
      await pumpPage(tester, const HomePage());
      expect(find.text('Your playlists'), findsOneWidget);
      await tester.tap(find.byKey(Key('home.card.$id')));
      await settle(tester);
      expect(find.text('Playlist $id'), findsOneWidget);
    });

    uiTest('the gear opens settings on a phone', (tester) async {
      await pumpPage(tester, const HomePage());
      await tester.tap(find.byKey(const Key('home.settings')));
      await settle(tester);
      expect(find.text('Settings stub'), findsOneWidget);
      expect(router.state.uri.path, '/settings');
    });

    uiTest('has no gear on a wide window', (tester) async {
      await pumpPage(tester, const HomePage(), size: const Size(1000, 800));
      expect(find.byKey(const Key('home.settings')), findsNothing);
    });
  });

  group('SearchPage', () {
    Future<void> seed(WidgetTester tester) => real(tester, () async {
      await h.addTrack('t1', title: 'Halo', artist: 'Beyoncé');
      await h.addTrack('t2', title: 'Yellow', artist: 'Coldplay');
      await h.addPlaylist('Beyoncé hits', ['t1']);
    });

    Future<void> type(WidgetTester tester, String text) =>
        tester.enterText(find.byKey(const Key('search.field')), text);

    uiTest('an empty query shows the hint', (tester) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage());
      expect(find.text('Search your songs and playlists'), findsOneWidget);
      expect(find.text('Songs'), findsNothing);
    });

    uiTest('"bey" lists Halo under Songs and the playlist under Playlists', (
      tester,
    ) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage());
      await type(tester, 'bey');
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);

      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Halo'), findsOneWidget);
      expect(find.text('Yellow'), findsNothing);
      expect(find.text('Beyoncé hits'), findsOneWidget);
      expect(find.text('Search your songs and playlists'), findsNothing);
    });

    uiTest('querying waits 150 ms after the last keystroke', (tester) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage());
      await type(tester, 'bey');
      // `flush` itself advances the fake clock a few milliseconds.
      await tester.pump(const Duration(milliseconds: 100));
      await flush(tester);
      expect(find.text('Halo'), findsNothing);

      // A further keystroke restarts the wait.
      await type(tester, 'beyo');
      await tester.pump(const Duration(milliseconds: 100));
      await flush(tester);
      expect(find.text('Halo'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      await settle(tester);
      expect(find.text('Halo'), findsOneWidget);
    });

    uiTest('writes the query to searchQueryProvider', (tester) async {
      await pumpPage(tester, const SearchPage());
      await type(tester, 'bey');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
      );
      expect(container.read(searchQueryProvider), 'bey');
      await tester.pump(const Duration(milliseconds: 200));
    });

    uiTest('follows the provider when another field writes it', (tester) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage(), size: const Size(1000, 800));
      // A wide window has no field of its own: the title bar owns it.
      expect(find.byKey(const Key('search.field')), findsNothing);

      ProviderScope.containerOf(tester.element(find.byType(SearchPage)))
          .read(searchQueryProvider.notifier)
          .set('yell');
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);
      expect(find.text('Yellow'), findsOneWidget);
    });

    uiTest('tapping a song plays it alone', (tester) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage());
      await type(tester, 'bey');
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);

      await tester.tap(find.text('Halo'));
      await settle(tester);
      expect([for (final t in h.player.state.queue) t.id], ['t1']);
      expect(h.backend.sources, ['/music/t1.mp3']);
    });

    uiTest('tapping a playlist opens it', (tester) async {
      late String id;
      await real(tester, () async {
        await h.addTrack('t1', title: 'Halo', artist: 'Beyoncé');
        id = await h.addPlaylist('Beyoncé hits', ['t1']);
      });
      await pumpPage(tester, const SearchPage());
      await type(tester, 'hits');
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);

      await tester.tap(find.text('Beyoncé hits'));
      await settle(tester);
      expect(find.text('Playlist $id'), findsOneWidget);
    });

    uiTest('says so when nothing matches', (tester) async {
      await seed(tester);
      await pumpPage(tester, const SearchPage());
      await type(tester, 'zzz');
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);
      expect(find.text('No results for "zzz"'), findsOneWidget);
    });
  });
}
