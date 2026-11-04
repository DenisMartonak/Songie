// The one song menu: opened by long-press, right-click or ⋯ on every song
// row and on Now Playing, with each item only where it applies.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/search/search_page.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/ui/widgets/artwork.dart';
import 'package:songies/ui/widgets/favorite_star.dart';

import '../helpers/test_db.dart';
import '../helpers/ui_harness.dart';

const _lucky = YtmSong(
  videoId: 'v1',
  title: 'Get Lucky',
  artists: [YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk')],
  album: 'Random Access Memories',
  albumBrowseId: 'MPREb_ram',
  durationMs: 369000,
);

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  void phone(WidgetTester tester, [Size size = const Size(400, 900)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder item(String action) => find.byKey(Key('songMenu.$action'));
  final sheet = find.byKey(const Key('songMenu.sheet'));
  final popup = find.byWidgetPredicate((w) => w is PopupMenuItem);

  Future<void> longPress(WidgetTester tester, Finder row) async {
    await tester.longPress(row);
    await settle(tester);
  }

  Future<Offset> rightClick(WidgetTester tester, Finder row) async {
    // Near the left edge, so the menu fits to the right of the pointer.
    final at = Offset(tester.getTopLeft(row).dx + 24, tester.getCenter(row).dy);
    await tester.tapAt(
      at,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    return at;
  }

  Future<void> choose(WidgetTester tester, String action) async {
    await tester.tap(item(action));
    await settle(tester);
  }

  /// Closes an open sheet or popup menu.
  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
  }

  /// The sheet opened by long-press and the popup at the pointer opened by
  /// right-click, both holding the same menu.
  Future<void> expectBothWays(WidgetTester tester, Finder row) async {
    await longPress(tester, row);
    expect(sheet, findsOneWidget);
    expect(item('addToQueue'), findsOneWidget);
    expect(item('addToPlaylist'), findsOneWidget);
    await dismiss(tester);
    expect(sheet, findsNothing);

    final at = await rightClick(tester, row);
    expect(sheet, findsNothing);
    expect(popup, findsWidgets);
    expect(item('addToQueue'), findsOneWidget);
    expect(item('addToPlaylist'), findsOneWidget);
    // It opens at the pointer.
    final top = tester.getTopLeft(item('addToQueue'));
    expect((top.dy - at.dy).abs(), lessThan(60));
    expect((top.dx - at.dx).abs(), lessThan(60));
    await dismiss(tester);
    expect(popup, findsNothing);
  }

  List<String> queueIds() => [for (final t in h.player.state.queue) t.id];

  Future<void> addYtTrack(String id, {bool unavailable = false}) => h.db
      .into(h.db.tracks)
      .insert(
        trackRow(
          id: id,
          source: 'yt',
          ytVideoId: 'v$id',
          title: 'Song $id',
        ).copyWith(unavailable: Value(unavailable)),
      );

  // --- pages ----------------------------------------------------------------

  Future<void> pumpPlaylist(WidgetTester tester, String id) async {
    phone(tester, const Size(800, 900));
    await tester.pumpWidget(
      h.app(
        initialLocation: '/playlist/$id',
        routes: [
          GoRoute(
            path: '/playlist/:id',
            builder: (_, s) =>
                Scaffold(body: PlaylistPage(id: s.pathParameters['id']!)),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> pumpHome(WidgetTester tester) async {
    phone(tester, const Size(400, 1600));
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: HomePage()),
          ),
          GoRoute(
            path: '/home/playlist/:id',
            builder: (_, s) =>
                Scaffold(body: Text('Playlist ${s.pathParameters['id']}')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> pumpSearch(WidgetTester tester, String query) async {
    phone(tester);
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
    await tester.enterText(find.byKey(const Key('search.field')), query);
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await settle(tester);
  }

  /// With [still], under reduced motion: the playing row's bars stand still.
  Future<void> pumpNowPlaying(WidgetTester tester, {bool still = false}) async {
    phone(tester, const Size(400, 800));
    await tester.pumpWidget(
      h.app(
        disableAnimations: still,
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Shell stub')),
          ),
          GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage),
        ],
      ),
    );
    GoRouter.of(tester.element(find.text('Shell stub'))).push('/now-playing');
    await settle(tester);
  }

  /// Song t1 played, then t2 (the newest first in Recents).
  Future<void> recents(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1', title: 'First');
    await h.addTrack('t2', title: 'Second');
    await h.history.record('t1', null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await h.history.record('t2', null);
  });

  final recentRow = find.byKey(const Key('home.recent.t1'));

  // --- opening --------------------------------------------------------------

  group('opens', () {
    uiTest('on a library row (Recents) by long-press and right-click', (
      tester,
    ) async {
      await recents(tester);
      h.ytm.homeAnswer = const Ok(YtmHome([], null));
      await pumpHome(tester);
      await expectBothWays(tester, recentRow);
    });

    uiTest('on a playlist row by long-press and right-click', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        return h.addPlaylist('Road trip', ['t1', 't2']);
      });
      await pumpPlaylist(tester, pid);
      await expectBothWays(tester, find.text('Song t2'));
    });

    uiTest('on a search library row by long-press and right-click', (
      tester,
    ) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'One More Time', artist: 'Daft Punk');
        await h.addPlaylist('Dance', ['t1']);
      });
      await pumpSearch(tester, 'daft');
      await expectBothWays(tester, find.byKey(const Key('search.song.t1')));
    });

    uiTest('on a YouTube Music search row by long-press and right-click', (
      tester,
    ) async {
      h.ytm.answer('lucky', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, 'lucky');
      await expectBothWays(tester, find.byKey(const Key('ytm.song.v1')));
    });

    uiTest('on a queue row by long-press', (tester) async {
      await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
      });
      await pumpNowPlaying(tester, still: true);
      final tracks = await real(tester, () => h.db.select(h.db.tracks).get());
      await real(tester, () => h.player.playQueue(tracks));
      await settle(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await settle(tester);

      await longPress(tester, find.byKey(const Key('queue.row.1')));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Song t2')),
        findsOneWidget,
      );
    });

    uiTest("from Now Playing's ⋯ for the current song", (tester) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'Song one');
        await h.addPlaylist('Gym', const []);
      });
      await pumpNowPlaying(tester);
      final tracks = await real(tester, () => h.db.select(h.db.tracks).get());
      await real(tester, () => h.player.playQueue(tracks));
      await settle(tester);

      await tester.tap(find.byKey(const Key('nowPlaying.more')));
      await settle(tester);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Song one')),
        findsOneWidget,
      );

      await choose(tester, 'addToPlaylist');
      await tester.tap(find.text('Gym'));
      await settle(tester);
      expect(find.text('Added to Gym'), findsOneWidget);
    });

    uiTest('on a Home feed song card by long-press and right-click', (
      tester,
    ) async {
      h.ytm.homeAnswer = const Ok(
        YtmHome([
          YtmShelf('Quick picks', [_lucky]),
        ], null),
      );
      await pumpHome(tester);
      await expectBothWays(tester, find.byKey(const Key('ytm.card.song.v1')));
    });

    uiTest('at once under reduced motion', (tester) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'First');
        await h.history.record('t1', null);
      });
      phone(tester, const Size(400, 1600));
      await tester.pumpWidget(
        h.app(
          disableAnimations: true,
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: HomePage()),
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.longPress(recentRow);
      await flush(tester);
      expect(sheet, findsOneWidget);
      // Fully up after a few 1 ms frames: the sheet's bottom sits on the screen's bottom.
      expect(tester.getBottomLeft(sheet).dy, closeTo(1600, 1));
    });

    uiTest('Now Playing has no ⋯ while nothing plays', (tester) async {
      await pumpNowPlaying(tester);
      expect(find.byKey(const Key('nowPlaying.more')), findsNothing);
    });
  });

  // --- a tap is unchanged ---------------------------------------------------

  group('a tap still plays', () {
    uiTest('a Recents row plays through the list from it', (tester) async {
      await recents(tester);
      h.ytm.homeAnswer = const Ok(YtmHome([], null));
      await pumpHome(tester);
      await tester.tap(recentRow);
      await settle(tester);
      expect(sheet, findsNothing);
      expect(queueIds(), ['t2', 't1']);
      expect(h.player.state.current?.id, 't1');
    });

    uiTest('a playlist row plays the playlist from it', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        return h.addPlaylist('Road trip', ['t1', 't2']);
      });
      await pumpPlaylist(tester, pid);
      await tester.tap(find.text('Song t2'));
      // The playing row's equalizer moves: no settling.
      await flush(tester);
      expect(sheet, findsNothing);
      expect(queueIds(), ['t1', 't2']);
      expect(h.player.state.current?.id, 't2');
      expect(h.player.state.sourcePlaylistId, pid);
    });

    uiTest('a search row plays the song', (tester) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'One More Time', artist: 'Daft Punk');
      });
      await pumpSearch(tester, 'daft');
      await tester.tap(find.byKey(const Key('search.song.t1')));
      await settle(tester);
      expect(sheet, findsNothing);
      expect(queueIds(), ['t1']);
    });
  });

  // --- actions --------------------------------------------------------------

  group('Add to playlist', () {
    uiTest('adds the song to the chosen playlist', (tester) async {
      late String gym;
      await recents(tester);
      await real(tester, () async => gym = await h.addPlaylist('Gym', []));
      await pumpHome(tester);

      await longPress(tester, recentRow);
      await choose(tester, 'addToPlaylist');
      await tester.tap(find.byKey(Key('addToPlaylist.$gym')));
      await settle(tester);

      expect(find.text('Added to Gym'), findsOneWidget);
      expect(await real(tester, () => h.orderOf(gym)), ['t1']);
    });

    uiTest('a song already in the playlist is not added twice', (tester) async {
      late String gym;
      await recents(tester);
      await real(tester, () async => gym = await h.addPlaylist('Gym', ['t1']));
      await pumpHome(tester);

      await longPress(tester, recentRow);
      await choose(tester, 'addToPlaylist');
      await tester.tap(find.byKey(Key('addToPlaylist.$gym')));
      await settle(tester);

      expect(find.text('Already in Gym'), findsOneWidget);
      expect(find.text('Added to Gym'), findsNothing);
      expect(await real(tester, () => h.orderOf(gym)), ['t1']);
    });
  });

  group('Remove from this playlist', () {
    uiTest('shows inside a playlist and removes with Undo', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        return h.addPlaylist('Road trip', ['t1', 't2']);
      });
      await pumpPlaylist(tester, pid);

      await longPress(tester, find.text('Song t1'));
      await choose(tester, 'removeFromPlaylist');
      expect(await real(tester, () => h.orderOf(pid)), ['t2']);
      expect(find.text('Removed Song t1'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(await real(tester, () => h.orderOf(pid)), ['t1', 't2']);
    });

    uiTest('removes the right song after the list changed under the menu', (
      tester,
    ) async {
      final pid = await real(tester, () async {
        for (final id in ['t1', 't2', 't3', 't4']) {
          await h.addTrack(id);
        }
        return h.addPlaylist('Road trip', ['t1', 't2', 't3']);
      });
      await pumpPlaylist(tester, pid);

      await longPress(tester, find.text('Song t2'));
      expect(item('removeFromPlaylist'), findsOneWidget);
      // While the menu is open, t1 goes away and t4 is added at the end.
      await real(tester, () async {
        // A plain read: a stream subscribed here would wait on the fake
        // clock.
        final first = await (h.db.select(
          h.db.playlistEntries,
        )..where((e) => e.trackId.equals('t1'))).getSingle();
        await h.repo.removeEntry(first.id);
      });
      // The page catches up between writes (drift's stream re-query runs on
      // the test's clock).
      await settle(tester);
      await real(tester, () => h.repo.addTracks(pid, ['t4']));
      await settle(tester);
      expect(await real(tester, () => h.orderOf(pid)), ['t2', 't3', 't4']);

      await choose(tester, 'removeFromPlaylist');
      expect(await real(tester, () => h.orderOf(pid)), ['t3', 't4']);
      expect(find.text('Removed Song t2'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(await real(tester, () => h.orderOf(pid)), ['t2', 't3', 't4']);
    });

    uiTest('does nothing when the page is gone before Remove is chosen', (
      tester,
    ) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        return h.addPlaylist('Road trip', ['t1']);
      });
      phone(tester, const Size(800, 900));
      // The page can be taken out of the tree while its menu stays open.
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        h.app(
          initialLocation: '/playlist/$pid',
          routes: [
            GoRoute(
              path: '/playlist/:id',
              builder: (_, s) => Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: shown,
                  builder: (_, on, _) => on
                      ? PlaylistPage(id: s.pathParameters['id']!)
                      : const SizedBox(),
                ),
              ),
            ),
          ],
        ),
      );
      await settle(tester);

      await longPress(tester, find.text('Song t1'));
      expect(item('removeFromPlaylist'), findsOneWidget);
      shown.value = false;
      await settle(tester);
      expect(find.byType(PlaylistPage), findsNothing);
      expect(item('removeFromPlaylist'), findsOneWidget);

      await choose(tester, 'removeFromPlaylist');
      expect(tester.takeException(), isNull);
      expect(await real(tester, () => h.orderOf(pid)), ['t1']);
    });

    uiTest('does not show outside a playlist', (tester) async {
      await recents(tester);
      await pumpHome(tester);
      await longPress(tester, recentRow);
      expect(item('addToQueue'), findsOneWidget);
      expect(item('removeFromPlaylist'), findsNothing);
    });
  });

  group('Download', () {
    uiTest('is offered for a YouTube song in a playlist', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        await addYtTrack('y1');
        return h.addPlaylist('Mix', ['t1', 'y1']);
      });
      await pumpPlaylist(tester, pid);

      await longPress(tester, find.text('Song y1'));
      expect(item('download'), findsOneWidget);
      expect(item('startRadio'), findsOneWidget);
      await choose(tester, 'download');
      expect(h.downloadRepo.calls, ['downloadTrack(y1)']);
    });

    uiTest('is not offered for a local song', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        return h.addPlaylist('Mix', ['t1']);
      });
      await pumpPlaylist(tester, pid);

      await longPress(tester, find.text('Song t1'));
      expect(item('addToQueue'), findsOneWidget);
      expect(item('download'), findsNothing);
      expect(item('removeDownload'), findsNothing);
      expect(item('startRadio'), findsNothing);
    });

    uiTest('is offered for a YouTube Music result, storing it first', (
      tester,
    ) async {
      h.ytm.answer('lucky', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, 'lucky');
      await longPress(tester, find.byKey(const Key('ytm.song.v1')));
      await choose(tester, 'download');
      expect(h.ytStore.upserted, ['v1']);
      expect(h.downloadRepo.calls, hasLength(1));
      expect(h.downloadRepo.calls.single, startsWith('downloadTrack('));
    });
  });

  group('a failed database read', () {
    uiTest('still opens the menu, as not downloaded', (tester) async {
      final pid = await real(tester, () async {
        await addYtTrack('y1');
        return h.addPlaylist('Mix', ['y1']);
      });
      h.downloadRepo = _FailingRowIds(h.db);
      await pumpPlaylist(tester, pid);
      await longPress(tester, find.text('Song y1'));
      expect(sheet, findsOneWidget);
      expect(item('download'), findsOneWidget);
      expect(item('removeDownload'), findsNothing);
    });

    uiTest('still adds to the playlist', (tester) async {
      late String gym;
      await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        gym = await h.addPlaylist('Gym', ['t2']);
      });
      h.repo = _FailingTrackIdsIn(h.db, h.stamp);
      await pumpPlaylist(tester, gym);
      await longPress(tester, find.text('Song t2'));
      await choose(tester, 'addToPlaylist');
      await tester.tap(find.byKey(Key('addToPlaylist.$gym')));
      await settle(tester);
      // Without the check it adds (a duplicate here) rather than failing.
      expect(find.text('Added to Gym'), findsOneWidget);
      expect(await real(tester, () => h.orderOf(gym)), ['t2', 't2']);
    });
  });

  group('Go to', () {
    uiTest('artist and album hide for a library song (ids unknown)', (
      tester,
    ) async {
      final pid = await real(tester, () async {
        await addYtTrack('y1');
        return h.addPlaylist('Mix', ['y1']);
      });
      await pumpPlaylist(tester, pid);
      await longPress(tester, find.text('Song y1'));
      expect(item('addToQueue'), findsOneWidget);
      expect(item('goToArtist'), findsNothing);
      expect(item('goToAlbum'), findsNothing);
    });

    uiTest('artist and album show for a YouTube Music song with ids', (
      tester,
    ) async {
      h.ytm.answer('lucky', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, 'lucky');
      await longPress(tester, find.byKey(const Key('ytm.song.v1')));
      expect(item('goToArtist'), findsOneWidget);
      expect(item('goToAlbum'), findsOneWidget);
      // Opening the menu writes nothing: the song is stored only by an action.
      expect(h.ytStore.upserted, isEmpty);
      expect(await real(tester, () => h.db.select(h.db.tracks).get()), isEmpty);
    });
  });

  group('Favorites', () {
    Finder starIn(Finder row) =>
        find.descendant(of: row, matching: find.byType(FavoriteStar));

    Future<Set<String>> favIds(WidgetTester tester) =>
        real(tester, () => FavoritesRepository(h.db, h.stamp).watchIds().first);

    setUp(() async {
      await FavoritesRepository(h.db, h.stamp).ensureFavorites();
    });

    uiTest('playlist rows have a star', (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        return h.addPlaylist('Road trip', ['t1', 't2']);
      });
      await pumpPlaylist(tester, pid);
      expect(find.byType(FavoriteStar), findsNWidgets(2));
    });

    uiTest('search rows have a star, library and YouTube Music', (
      tester,
    ) async {
      await real(tester, () async {
        await h.addTrack('t1', title: 'One More Time', artist: 'Daft Punk');
      });
      await pumpSearch(tester, 'daft');
      expect(starIn(find.byKey(const Key('search.song.t1'))), findsOneWidget);
      h.ytm.answer('lucky', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, 'lucky');
      expect(starIn(find.byKey(const Key('ytm.song.v1'))), findsOneWidget);
    });

    uiTest('Home recents and queue rows have a star', (tester) async {
      await recents(tester);
      h.ytm.homeAnswer = const Ok(YtmHome([], null));
      await pumpHome(tester);
      expect(starIn(recentRow), findsOneWidget);

      await pumpNowPlaying(tester, still: true);
      final tracks = await real(tester, () => h.db.select(h.db.tracks).get());
      await real(tester, () => h.player.playQueue(tracks));
      await settle(tester);
      await tester.tap(find.byKey(const Key('nowPlaying.tab.queue')));
      await settle(tester);
      expect(starIn(find.byKey(const Key('queue.row.1'))), findsOneWidget);
    });

    uiTest('the menu adds and removes Favorites', (tester) async {
      await recents(tester);
      h.ytm.homeAnswer = const Ok(YtmHome([], null));
      await pumpHome(tester);
      await longPress(tester, recentRow);
      expect(find.text('Add to Favorites'), findsOneWidget);
      await choose(tester, 'favorite');
      expect(await favIds(tester), {'t1'});
      await longPress(tester, recentRow);
      expect(find.text('Remove from Favorites'), findsOneWidget);
      await choose(tester, 'favorite');
      expect(await favIds(tester), isEmpty);
    });

    uiTest('starring a song that fails to store changes nothing', (
      tester,
    ) async {
      h.ytStore.failUpsert = const Failure(FailureKind.network, 'down');
      h.ytm.answer('lucky', YtmSearchKind.songs, [_lucky]);
      await pumpSearch(tester, 'lucky');
      await tester.tap(starIn(find.byKey(const Key('ytm.song.v1'))));
      await settle(tester);
      expect(find.text("Couldn't add that song"), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(await favIds(tester), isEmpty);
    });

    uiTest('un-starring on the Favorites page removes the row', (tester) async {
      await real(tester, () async {
        await h.addTrack('t1');
        await h.addTrack('t2');
        final f = FavoritesRepository(h.db, h.stamp);
        await f.star('t1');
        await f.star('t2');
      });
      await pumpPlaylist(tester, kFavoritesPlaylistId);
      expect(find.text('Song t1'), findsOneWidget);
      await tester.tap(
        starIn(
          find
              .ancestor(of: find.text('Song t1'), matching: find.byType(Row))
              .first,
        ),
      );
      await settle(tester);
      expect(find.text('Song t1'), findsNothing);
      expect(find.text('Song t2'), findsOneWidget);
    });
  });

  group('queue actions on a library song', () {
    uiTest('Add to queue uses the track as it is, in the order added', (
      tester,
    ) async {
      await recents(tester);
      await pumpHome(tester);
      await longPress(tester, recentRow);
      await choose(tester, 'addToQueue');
      expect(queueIds(), ['t1']);
      await longPress(tester, find.byKey(const Key('home.recent.t2')));
      await choose(tester, 'addToQueue');
      expect(queueIds(), ['t1', 't2']);
      expect(h.ytStore.upserted, isEmpty);
    });

    uiTest('Add to queue shows an island with the song', (tester) async {
      await recents(tester);
      await pumpHome(tester);
      await longPress(tester, recentRow);
      await choose(tester, 'addToQueue');
      expect(find.text('Added to queue'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('island')),
          matching: find.byType(Artwork),
        ),
        findsOneWidget,
      );
    });

    uiTest('there is no Play next', (tester) async {
      await recents(tester);
      await pumpHome(tester);
      await longPress(tester, recentRow);
      expect(find.text('Play next'), findsNothing);
      expect(item('addToQueue'), findsOneWidget);
    });
  });
}

/// A download repository whose download-row lookup fails.
class _FailingRowIds extends RecordingDownloadRepository {
  _FailingRowIds(super.db);

  @override
  Future<Set<String>> rowIds(Iterable<String> trackIds) =>
      Future.error(StateError('database is locked'));
}

/// A library repository whose playlist-contents lookup fails.
class _FailingTrackIdsIn extends LibraryRepository {
  _FailingTrackIdsIn(super.db, super.stamp);

  @override
  Future<Set<String>> trackIdsIn(String playlistId) =>
      Future.error(StateError('database is locked'));
}
