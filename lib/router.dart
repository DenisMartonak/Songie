import 'package:go_router/go_router.dart';

import 'ui/home/home_page.dart';
import 'ui/library/library_page.dart';
import 'ui/library/playlist_page.dart';
import 'ui/now_playing/now_playing_page.dart';
import 'ui/search/search_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell/adaptive_shell.dart';

const String nowPlayingLocation = '/now-playing';

/// Builds the app's router: Home / Search / Library branches inside the shell,
/// and full-screen Now Playing and Settings above it.
GoRouter buildRouter() => GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/home', builder: (_, _) => const HomePage())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
            GoRoute(
              path: '/playlist/:id',
              builder: (_, state) =>
                  PlaylistPage(id: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: nowPlayingLocation,
      builder: (_, _) => const NowPlayingPage(),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
  ],
);

/// Shows Now Playing unless it is already the current page.
void openNowPlaying(GoRouter router) {
  // `state` is the top route including pushed ones; the delegate's
  // `currentConfiguration.uri` ignores pushes.
  if (router.state.uri.path == nowPlayingLocation) return;
  router.push(nowPlayingLocation);
}
