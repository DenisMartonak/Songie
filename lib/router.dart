import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ui/home/home_page.dart';
import 'ui/library/library_page.dart';
import 'ui/motion/motion.dart';
import 'ui/playlist/playlist_page.dart';
import 'ui/now_playing/now_playing_page.dart';
import 'ui/search/search_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell/adaptive_shell.dart';
import 'ui/shell/fade_through_branches.dart';
import 'ui/widgets/page_surface.dart';

const String nowPlayingLocation = '/now-playing';

/// Builds the app's router: Home / Search / Library branches inside the shell,
/// and full-screen Now Playing and Settings above it. [navigatorKey] gives
/// `main()` a context for dialogs opened from outside the widget tree (links
/// shared into the app).
///
/// Transitions: switching tabs fades through, pages pushed inside a branch
/// (playlists, Settings) move along a shared horizontal axis, and Now Playing
/// slides up (see [nowPlayingPage]). With reduced motion they are instant.
GoRouter buildRouter({GlobalKey<NavigatorState>? navigatorKey}) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) => AdaptiveShell(shell),
      navigatorContainerBuilder: (context, shell, children) =>
          FadeThroughBranches(
            currentIndex: shell.currentIndex,
            children: children,
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) => sharedAxisPage(
                context,
                state,
                const PageSurface(child: HomePage()),
              ),
              routes: [_playlistRoute()],
            ),
            // Inside the shell so desktop keeps its title bar, sidebar and
            // player bar; Settings is not a tab, so it shares Home's branch.
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => sharedAxisPage(
                context,
                state,
                const PageSurface(child: SettingsPage()),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => sharedAxisPage(
                context,
                state,
                const PageSurface(child: SearchPage()),
              ),
              routes: [_playlistRoute()],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              pageBuilder: (context, state) => sharedAxisPage(
                context,
                state,
                const PageSurface(child: LibraryPage()),
              ),
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
  pageBuilder: (context, state) => sharedAxisPage(
    context,
    state,
    PageSurface(child: PlaylistPage(id: state.pathParameters['id']!)),
  ),
);

/// A page inside a branch: it enters, and the page under it leaves, along a
/// shared horizontal axis over [Motion.emphasized] (at once with reduced
/// motion). Branch roots use it too so that they slide out under a push.
Page<void> sharedAxisPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final duration = Motion.of(context).emphasized;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          // The page surface paints the background; don't cover the shell.
          fillColor: Colors.transparent,
          child: child,
        ),
  );
}

/// Shows Now Playing unless it is already the current page.
void openNowPlaying(GoRouter router) {
  // `state` is the top route including pushed ones; the delegate's
  // `currentConfiguration.uri` ignores pushes.
  if (router.state.uri.path == nowPlayingLocation) return;
  router.push(nowPlayingLocation);
}
