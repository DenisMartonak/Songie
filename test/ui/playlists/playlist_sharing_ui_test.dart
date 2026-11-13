import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/core/result.dart';
import 'package:songies/providers.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/playlists/playlist_invites.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late String me;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> signedIn() async {
    await h.accounts.signUp('me@x.com', 'password1', 'me');
    await h.accounts.verifySignup('me@x.com', h.accountBackend.goodCode);
    me = (h.accounts.state as SignedIn).profile.id;
    h.sharingBackend
      ..me = me
      ..names[me] = 'me'
      ..names['den'] = 'den';
  }

  /// YouTube songs y1, y2 and a local file l1, before the app starts.
  Future<void> seed(WidgetTester tester) => real(tester, () async {
    await h.db.insertTrack(
      trackRow(id: 'y1', source: 'yt', ytVideoId: 'v1', title: 'Halo'),
    );
    await h.db.insertTrack(
      trackRow(id: 'y2', source: 'yt', ytVideoId: 'v2', title: 'Run'),
    );
    await h.addTrack('l1', title: 'My file');
  });

  /// A share by `den` (another account) with code returned.
  Future<String> densShare(WidgetTester tester) => real(tester, () async {
    h.sharingBackend.me = 'den';
    final code = await h.sharingBackend.share('Den mix', const [
      RoomSong(videoId: 'v1', title: 'Halo', artist: 'B'),
      RoomSong(videoId: 'v2', title: 'Run', artist: 'B'),
    ]);
    h.sharingBackend.me = me;
    return code;
  });

  late GoRouter router;

  Future<void> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: PlaylistInvites(child: Text('Home'))),
          ),
          GoRoute(
            path: '/library/playlist/:id',
            builder: (_, s) => Scaffold(
              body: PlaylistInvites(
                child: PlaylistPage(id: s.pathParameters['id']!),
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: Text('Profile page')),
          ),
        ],
      ),
    );
    await settle(tester);
    router = GoRouter.of(tester.element(find.byType(Scaffold).first));
  }

  Finder key(String k) => find.byKey(Key(k));

  /// After an action: real-clock work (database, sharing) first, while a
  /// spinner may still turn, then frames and animations.
  Future<void> go(WidgetTester tester) async {
    await tester.pump();
    await flush(tester);
    await flush(tester);
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await go(tester);
  }

  ProviderContainer app(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  void openLink(WidgetTester tester, String code) {
    app(tester).read(playlistInviteProvider.notifier).set(code);
  }

  /// Follows [code] in the running app and opens the playlist.
  Future<String> followAndOpen(WidgetTester tester, String code) async {
    final id = (await real(
      tester,
      () => app(tester).read(playlistSharingProvider).follow(code),
    ))!;
    router.go('/library/playlist/$id');
    await go(tester);
    return id;
  }

  uiTest('Share shows the link and the left-out count; Stop sharing ends it', (
    tester,
  ) async {
    await signedIn();
    await seed(tester);
    final id = await real(tester, () => h.addPlaylist('Gym', ['y1', 'l1']));
    await pump(tester, '/library/playlist/$id');
    await openMenu(tester);
    await tester.tap(key('playlist.share'));
    await go(tester);
    final code = h.sharingBackend.codes.single;
    expect(find.textContaining('/p/$code'), findsOneWidget);
    expect(find.text("1 song from your files isn't shared"), findsOneWidget);
    await tester.tap(key('share.copyLink'));
    await go(tester);
    expect(find.text('Link copied'), findsOneWidget);
    // The same window stops it.
    await tester.tap(key('share.stop'));
    await go(tester);
    expect(h.sharingBackend.codes, isEmpty);
  });

  uiTest('a link opens the sheet; Follow adds the playlist and opens it', (
    tester,
  ) async {
    await signedIn();
    await seed(tester);
    final code = await densShare(tester);
    await pump(tester, '/');
    openLink(tester, code);
    await go(tester);
    expect(find.text('Den mix'), findsWidgets);
    expect(find.textContaining('den'), findsWidgets);
    await tester.tap(key('invite.follow'));
    await go(tester);
    expect(router.state.uri.path, startsWith('/library/playlist/'));
    expect(key('playlist.following'), findsOneWidget);
    expect(find.text('Following · by den'), findsOneWidget);
  });

  uiTest('a followed playlist shows who it follows and hides editing', (
    tester,
  ) async {
    await signedIn();
    await seed(tester);
    final code = await densShare(tester);
    await pump(tester, '/');
    await followAndOpen(tester, code);
    expect(find.text('Halo'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    await openMenu(tester);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Change cover'), findsNothing);
    expect(find.text('Add songs'), findsNothing);
    expect(key('playlist.makeCopy'), findsOneWidget);
    expect(key('playlist.stopFollowing'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await go(tester);
    // The song menu offers no Remove from playlist.
    await tester.tap(find.byTooltip('Song options').first);
    await go(tester);
    expect(find.text('Remove from playlist'), findsNothing);
  });

  uiTest('opening a followed playlist checks for updates', (tester) async {
    await signedIn();
    await seed(tester);
    final code = await densShare(tester);
    await pump(tester, '/');
    final id = (await real(
      tester,
      () => app(tester).read(playlistSharingProvider).follow(code),
    ))!;
    // The owner changes it; the follower opens it before any timer.
    await real(tester, () async {
      h.sharingBackend.me = 'den';
      await h.sharingBackend.update(code, 'Den mix', const [
        RoomSong(videoId: 'v2', title: 'Run', artist: 'B'),
      ]);
      h.sharingBackend.me = me;
    });
    router.go('/library/playlist/$id');
    await go(tester);
    expect(find.text('Halo'), findsNothing);
    expect(find.text('Run'), findsOneWidget);
  });

  uiTest('a share that stops while its window is open says so and closes', (
    tester,
  ) async {
    await signedIn();
    await seed(tester);
    final code = await densShare(tester);
    await pump(tester, '/');
    openLink(tester, code);
    await go(tester);
    await real(tester, () async {
      h.sharingBackend.me = 'den';
      await h.sharingBackend.stop(code);
      h.sharingBackend.me = me;
    });
    await tester.tap(key('invite.copy'));
    await go(tester);
    expect(key('invite.copy'), findsNothing);
    expect(find.text("This playlist isn't shared any more"), findsOneWidget);
  });

  uiTest('Add to playlist leaves out followed playlists', (tester) async {
    await signedIn();
    await seed(tester);
    final mine = await real(tester, () async {
      // A followed playlist, as following a link leaves it.
      final followed = (await h.repo.createFollowedPlaylist(
        code: 'ABCDEFGH2345',
        name: 'Den mix',
        owner: 'den',
      ) as Ok<String>).value;
      await h.repo.applySnapshot(
        followed,
        name: 'Den mix',
        trackIds: const ['y1'],
        updatedAt: DateTime.utc(2026, 11, 13),
      );
      return h.addPlaylist('Mine', ['y1']);
    });
    await pump(tester, '/library/playlist/$mine');
    await tester.tap(find.byTooltip('Song options').first);
    await go(tester);
    await tester.tap(find.text('Add to playlist'));
    await go(tester);
    expect(key('addToPlaylist.sheet'), findsOneWidget);
    expect(
      find.descendant(
        of: key('addToPlaylist.sheet'),
        matching: find.text('Mine'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('addToPlaylist.sheet'),
        matching: find.text('Den mix'),
      ),
      findsNothing,
    );
  });

  uiTest("opening your own playlist's link opens it, without Follow", (
    tester,
  ) async {
    await signedIn();
    await seed(tester);
    final id = await real(tester, () => h.addPlaylist('Gym', ['y1']));
    await pump(tester, '/');
    final code = await real(
      tester,
      () => app(tester).read(playlistSharingProvider).share(id),
    );
    openLink(tester, code);
    await go(tester);
    expect(key('invite.follow'), findsNothing);
    expect(router.state.uri.path, '/library/playlist/$id');
  });

  uiTest("a stopped share's link says so", (tester) async {
    await signedIn();
    await pump(tester, '/');
    openLink(tester, 'ABCDEFGH2345');
    await go(tester);
    expect(find.text("This playlist isn't shared any more"), findsOneWidget);
  });

  uiTest('signed out, a link asks to log in', (tester) async {
    await pump(tester, '/');
    openLink(tester, 'ABCDEFGH2345');
    await go(tester);
    expect(find.text('Log in to open shared playlists'), findsOneWidget);
  });

  uiTest('a followed playlist whose owner stopped shows the note and is '
      'editable', (tester) async {
    await signedIn();
    await seed(tester);
    final code = await densShare(tester);
    await pump(tester, '/');
    await followAndOpen(tester, code);
    await real(tester, () async {
      h.sharingBackend.me = 'den';
      await h.sharingBackend.stop(code);
      h.sharingBackend.me = me;
      await app(tester).read(playlistSharingProvider).refresh();
    });
    await go(tester);
    expect(find.text('den stopped sharing this'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsWidgets);
  });
}
