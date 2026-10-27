import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens YouTube Music artist, album and playlist pages.
///
/// Placeholder paths until Plan 5 Task 10 adds the routes (inside each tab
/// branch) and replaces these bodies; callers keep using these helpers.
extension YtmNav on BuildContext {
  void goYtmArtist(String browseId) => push('/ytm/artist/$browseId');

  void goYtmAlbum(String browseId) => push('/ytm/album/$browseId');

  void goYtmPlaylist(String browseId) => push('/ytm/playlist/$browseId');
}
