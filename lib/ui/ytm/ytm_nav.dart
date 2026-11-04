import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The tabs whose branches hold YouTube Music pages (see `router.dart`).
const _tabs = {'home', 'search', 'library'};

/// The root of the tab [path] lies in ('/home', '/search' or '/library'), or
/// null outside them (Settings, Now Playing, a test's own routes).
String? tabRootOf(String path) {
  final first = Uri.parse(path).pathSegments.firstOrNull;
  return first != null && _tabs.contains(first) ? '/$first' : null;
}

/// Opens YouTube Music artist, album and playlist pages inside the tab they
/// are opened from, so Back returns to the
/// page underneath. Outside a tab they open at `/ytm/...`, which the router
/// sends to Search.
extension YtmNav on BuildContext {
  void goYtmArtist(String browseId) => _pushInTab('ytm/artist', browseId);

  void goYtmAlbum(String browseId) => _pushInTab('ytm/album', browseId);

  void goYtmPlaylist(String browseId) => _pushInTab('ytm/playlist', browseId);

  void _pushInTab(String kind, String id) {
    final root = tabRootOf(GoRouter.of(this).state.uri.path) ?? '';
    push('$root/$kind/${Uri.encodeComponent(id)}');
  }
}

/// Opens one of the user's playlists in the tab [router] shows now (outside a
/// tab, in Library). For callbacks that outlive their page, such as an
/// island's action.
void openLibraryPlaylistIn(GoRouter router, String id) {
  final root = tabRootOf(router.state.uri.path);
  final path = 'playlist/${Uri.encodeComponent(id)}';
  if (root == null) {
    router.go('/library/$path');
  } else {
    router.push('$root/$path');
  }
}
