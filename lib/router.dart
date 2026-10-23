import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'ui/home/home_page.dart';
import 'ui/library/library_page.dart';
import 'ui/playlist/playlist_page.dart';
import 'ui/now_playing/now_playing_page.dart';
import 'ui/search/search_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell/adaptive_shell.dart';
import 'ui/widgets/page_surface.dart';

const String nowPlayingLocation = '/now-playing';

/// Builds the app's router: Home / Search / Library branches inside the shell,
/// and full-screen Now Playing and Settings above it. [navigatorKey] gives
/// `main()` a context for dialogs opened from outside the widget tree (links
/// shared into the app).
GoRouter buildRouter({GlobalKey<NavigatorState>? navigatorKey}) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const PageSurface(child: HomePage()),
              routes: [_playlistRoute()],
            ),
            // Inside the shell so desktop keeps its title bar, sidebar and
            // player bar; Settings is not a tab, so it shares Home's branch.
            GoRoute(
              path: '/settings',
              builder: (_, _) => const PageSurface(child: SettingsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (_, _) => const PageSurface(child: SearchPage()),
              routes: [_playlistRoute()],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const PageSurface(child: LibraryPage()),
              routes: [_playlistRoute()],
            ),
          ],
        ),
      ],
    ),
    // Older links; playlists now live under the branch they are opened from.
    GoRoute(
      path: '/playlist/:id',
      redirect: (_, state) => '/library/playlist/${state.pathParameters['id']}',
    ),
    GoRoute(path: nowPlayingLocation, pageBuilder: nowPlayingPage),
  ],
);

/// A playlist page nested under a branch's root page, so that opening one
/// (with `push`) keeps the page it was opened from underneath for Back.
GoRoute _playlistRoute() => GoRoute(
  path: 'playlist/:id',
  builder: (_, state) =>
      PageSurface(child: PlaylistPage(id: state.pathParameters['id']!)),
);

/// Shows Now Playing unless it is already the current page.
void openNowPlaying(GoRouter router) {
  // `state` is the top route including pushed ones; the delegate's
  // `currentConfiguration.uri` ignores pushes.
  if (router.state.uri.path == nowPlayingLocation) return;
  router.push(nowPlayingLocation);
}
