// Home's YouTube Music feed: rows below the library part of Home, loaded when
// Home opens, cached for the session and reloaded only by pull to refresh.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/motion/shimmer.dart';
import 'package:songies/ui/ytm/consent_sheet.dart';
import 'package:songies/ui/ytm/ytm_shelf_row.dart';

import '../helpers/ui_harness.dart';

const _song = YtmSong(
  videoId: 'vid1',
  title: 'Feed song',
  artists: [YtmArtistRef(name: 'Feed artist')],
);
const _album = YtmAlbum(browseId: 'MPREb_1', title: 'Feed album');
const _artist = YtmArtist(browseId: 'UC_1', name: 'Feed artist page');
const _playlist = YtmPlaylist(browseId: 'VLPL_1', title: 'Feed mix');

const _feed = YtmHome([
  YtmShelf('Quick picks', [_song]),
  YtmShelf('New releases', [_album, _artist, _playlist]),
], null);

void main() {
  late UiHarness h;
  late GoRouter router;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpHome(WidgetTester tester, {bool settleAfter = true}) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: HomePage()),
          ),
          GoRoute(
            path: '/elsewhere',
            builder: (_, _) => const Scaffold(body: Text('Elsewhere')),
          ),
          GoRoute(
            path: '/home/playlist/:id',
            builder: (_, s) =>
                Scaffold(body: Text('Playlist ${s.pathParameters['id']}')),
          ),
          for (final kind in ['artist', 'album', 'playlist'])
            GoRoute(
              path: '/home/ytm/$kind/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('YTM $kind ${s.pathParameters['id']}')),
            ),
        ],
      ),
    );
    router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    if (settleAfter) {
      await settle(tester);
    } else {
      await flush(tester);
    }
  }

  Future<void> seedLibrary(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1');
    await h.addPlaylist('Gym Mix', ['t1']);
  });

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  uiTest('the library part comes first, then one row per shelf', (
    tester,
  ) async {
    await seedLibrary(tester);
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester);

    expect(find.byType(YtmShelfRow), findsNWidgets(2));
    expect(find.text('Quick picks'), findsOneWidget);
    expect(find.text('New releases'), findsOneWidget);
    expect(
      top(tester, find.text('Your playlists')),
      lessThan(top(tester, find.text('Quick picks'))),
    );
    expect(
      top(tester, find.text('Quick picks')),
      lessThan(top(tester, find.text('New releases'))),
    );
    expect(find.text('Feed song'), findsOneWidget);
    expect(find.text('Feed album'), findsOneWidget);
    expect(h.ytm.homeCalls, [null]);
  });

  uiTest('a song card plays with radio; the others open their pages', (
    tester,
  ) async {
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('ytm.card.song.vid1')));
    await settle(tester);
    expect(h.radio.played.map((s) => s.videoId), ['vid1']);

    for (final (key, page) in [
      ('ytm.card.album.MPREb_1', 'YTM album MPREb_1'),
      ('ytm.card.artist.UC_1', 'YTM artist UC_1'),
      ('ytm.card.playlist.VLPL_1', 'YTM playlist VLPL_1'),
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
      expect(find.text(page), findsOneWidget);
      router.pop();
      await settle(tester);
    }
  });

  uiTest('skeleton rows while loading; the shimmer stops once loaded', (
    tester,
  ) async {
    h.ytm.homeGate = Completer<void>();
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester, settleAfter: false);

    final skeleton = find.byKey(const Key('home.feed.skeleton'));
    expect(skeleton, findsOneWidget);
    expect(
      find.descendant(of: skeleton, matching: find.byType(SkeletonBox)),
      findsWidgets,
    );
    expect(find.byType(Shimmer), findsOneWidget);

    h.ytm.homeGate!.complete();
    await settle(tester);
    expect(skeleton, findsNothing);
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byType(YtmShelfRow), findsNWidgets(2));
  });

  uiTest('an error stops the shimmer and offers Retry', (tester) async {
    h.ytm.homeGate = Completer<void>();
    h.ytm.homeAnswer = const Err(Failure(FailureKind.network, 'boom'));
    await pumpHome(tester, settleAfter: false);
    expect(find.byType(Shimmer), findsOneWidget);

    h.ytm.homeGate!.complete();
    await settle(tester);
    expect(find.byType(Shimmer), findsNothing);
    expect(find.text("Couldn't load"), findsOneWidget);

    h.ytm
      ..homeGate = null
      ..homeAnswer = const Ok(_feed);
    await tester.tap(find.byKey(const Key('ytm.retry')));
    await settle(tester);
    expect(find.byType(YtmShelfRow), findsNWidgets(2));
    expect(h.ytm.homeCalls, hasLength(2));
  });

  uiTest('pull to refresh refetches once; reopening Home does not', (
    tester,
  ) async {
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester);
    expect(h.ytm.homeCalls, hasLength(1));

    // From the greeting, down: the pull-to-refresh gesture.
    await tester.fling(
      find.text(greetingFor(h.now())),
      const Offset(0, 400),
      1000,
    );
    await settle(tester);
    expect(h.ytm.homeCalls, hasLength(2));

    router.go('/elsewhere');
    await settle(tester);
    expect(find.byType(HomePage), findsNothing);
    router.go('/home');
    await settle(tester);
    expect(find.byType(YtmShelfRow), findsNWidgets(2));
    expect(h.ytm.homeCalls, hasLength(2));
  });

  uiTest('offline hides the feed and keeps the rest of Home', (tester) async {
    await seedLibrary(tester);
    h.network.kind = NetworkKind.offline;
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester);

    expect(find.text('Connect to see recommendations'), findsOneWidget);
    expect(find.byType(YtmShelfRow), findsNothing);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(find.text('Gym Mix'), findsWidgets);
    expect(h.ytm.homeCalls, isEmpty);
  });

  uiTest('Home asks for consent when YouTube does', (tester) async {
    await pumpHome(tester);
    expect(find.byType(ConsentListener), findsOneWidget);
    h.innertube.askForConsent();
    await settle(tester);
    expect(find.text('YouTube needs you to accept its terms'), findsOneWidget);
  });

  uiTest('paused with the feed loaded, nothing is drawn', (tester) async {
    await seedLibrary(tester);
    h.ytm.homeAnswer = const Ok(_feed);
    await pumpHome(tester);
    final track = await real(
      tester,
      () => (h.db.select(
        h.db.tracks,
      )..where((t) => t.id.equals('t1'))).getSingle(),
    );
    await real(tester, () async {
      await h.player.playQueue([track]);
      await h.player.pause();
    });
    await settle(tester);

    expect(find.byType(YtmShelfRow), findsNWidgets(2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('signed in to YouTube', () {
    final session = YtSession({'SAPISID': 'SAPISECRET'});
    const notice = 'YouTube sign-in expired — showing the regular feed';

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomePage)));

    Future<void> signIn(WidgetTester tester) async {
      await real(
        tester,
        () =>
            container(tester)
                .read(ytAuthProvider.notifier)
                .signIn(session, name: 'N'),
      );
      await settle(tester);
    }

    final signedInFeed = Ok(YtmHome(_feed.shelves, null, signedIn: true));

    uiTest('signing in reloads Home with the session', (tester) async {
      h.ytm
        ..homeAnswer = const Ok(_feed)
        ..signedInHomeAnswer = signedInFeed;
      await pumpHome(tester);
      expect(h.ytm.homeSessions, [null]);
      await signIn(tester);
      expect(h.ytm.homeSessions, [null, session]);
      expect(find.text(notice), findsNothing);
    });

    uiTest('an expired session: the regular feed, the notice once', (
      tester,
    ) async {
      h.ytm
        ..homeAnswer = const Ok(_feed)
        ..signedInHomeAnswer = const Ok(YtmHome([], null));
      await pumpHome(tester);
      await signIn(tester);
      // Signed in, refused, then one anonymous retry.
      expect(h.ytm.homeSessions, [null, session, null]);
      expect(find.text(notice), findsOneWidget);
      expect(find.text('Quick picks'), findsOneWidget);
      expect(container(tester).read(ytAuthProvider), isA<YtExpired>());

      // Opening Home again: signed out, no second notice.
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.text(notice), findsNothing);
      container(tester).invalidate(ytmHomeProvider);
      await settle(tester);
      expect(h.ytm.homeSessions, [null, session, null, null]);
      expect(find.text(notice), findsNothing);
    });

    uiTest('YouTube asking for consent opens no sheet while signed in', (
      tester,
    ) async {
      h.ytm
        ..homeAnswer = const Ok(_feed)
        ..signedInHomeAnswer = signedInFeed;
      await pumpHome(tester);
      await signIn(tester);
      expect(container(tester).read(ytAuthProvider), isA<YtSignedIn>());
      h.innertube.askForConsent();
      await settle(tester);
      expect(find.text('YouTube needs you to accept its terms'), findsNothing);
    });
  });
}
