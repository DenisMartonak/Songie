import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/paths.dart';
import 'data/database.dart';
import 'data/sync_stamp.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/play_history_repository.dart';
import 'library/scan_queue.dart';
import 'library/search_repository.dart';
import 'player/player_service.dart';
import 'theme/theme_spec.dart';
import 'ui/shell/window_controls.dart';

/// Singletons are created in `main()` and injected with
/// `ProviderScope.overrides`; reading one without an override is a wiring bug.
Never _unwired(String name) =>
    throw UnimplementedError('$name must be overridden in ProviderScope');

final appPathsProvider = Provider<AppPaths>(
  (ref) => _unwired('appPathsProvider'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => _unwired('databaseProvider'),
);

final syncStampProvider = Provider<SyncStamp>(
  (ref) => _unwired('syncStampProvider'),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => _unwired('libraryRepositoryProvider'),
);

final playHistoryRepositoryProvider = Provider<PlayHistoryRepository>(
  (ref) => _unwired('playHistoryRepositoryProvider'),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => _unwired('searchRepositoryProvider'),
);

final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => _unwired('libraryScannerProvider'),
);

/// Serialises folder scans; shared by the Library page and Settings.
final scanQueueProvider = Provider<ScanQueue>(
  (ref) => ScanQueue(ref.watch(libraryScannerProvider).scanFolder),
);

/// Progress of the running scan; null when none is running.
final scanProgressProvider = StreamProvider<ScanProgress?>(
  (ref) => ref.watch(scanQueueProvider).current,
);

final artCacheProvider = Provider<ArtCache>(
  (ref) => _unwired('artCacheProvider'),
);

final playerServiceProvider = Provider<PlayerService>(
  (ref) => _unwired('playerServiceProvider'),
);

/// The player's state, starting with its current value (the service's own
/// stream only emits changes).
///
/// Subscribes first and seeds afterwards, so an update emitted in between is
/// delivered rather than lost.
final playerStateProvider = StreamProvider<PlayerState>((ref) {
  final player = ref.watch(playerServiceProvider);
  return Stream<PlayerState>.multi((controller) {
    final sub = player.states.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.addSync(player.state);
    controller.onCancel = sub.cancel;
  });
});

/// Every live playlist, for the sidebar and the library.
final playlistsProvider = StreamProvider<List<PlaylistSummary>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchPlaylists(),
);

/// The scanned music folders, for Settings.
final libraryFoldersProvider = StreamProvider<List<LibraryFolder>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFolders(),
);

/// This device's id, for Settings' About section.
final deviceIdProvider = Provider<String>(
  (ref) => ref.watch(syncStampProvider).deviceId,
);

/// One playlist's entries in order.
final playlistTracksProvider = StreamProvider.autoDispose
    .family<List<PlaylistTrack>, String>(
      (ref, playlistId) =>
          ref.watch(libraryRepositoryProvider).watchPlaylistTracks(playlistId),
    );

/// The current time; tests override it (e.g. for Home's greeting).
final nowProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// The last 10 distinct tracks played, newest first.
final recentTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(playHistoryRepositoryProvider).recentTracks(10),
);

/// The playlists most recently played from, newest first (enough to fill
/// Home's quick tiles).
final recentPlaylistIdsProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(playHistoryRepositoryProvider).recentPlaylistIds(6),
);

/// Live tracks matching a search query.
final searchTracksProvider = StreamProvider.autoDispose
    .family<List<Track>, String>(
      (ref, query) => ref.watch(searchRepositoryProvider).searchTracks(query),
    );

/// Live playlists matching a search query.
final searchPlaylistsProvider = StreamProvider.autoDispose
    .family<List<PlaylistSummary>, String>(
      (ref, query) =>
          ref.watch(searchRepositoryProvider).searchPlaylists(query),
    );

/// The text in the search field. The desktop title-bar field and the phone
/// search page both write it; the search page reads it.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// The active theme. Always the built-in Default in this plan.
final themeSpecProvider = Provider<ThemeSpec>(
  (ref) => ThemeSpec.builtInDefault,
);

/// The native window's minimize / maximize / close actions (desktop only).
final windowControlsProvider = Provider<WindowControls>(
  (ref) => WindowManagerControls(),
);

/// Whether the window draws its own title bar (Windows and Linux, where
/// `main()` hides the native one). Wide Android windows have no such bar and no
/// window_manager plugin.
final hasCustomTitleBarProvider = Provider<bool>(
  (ref) => Platform.isWindows || Platform.isLinux,
);
