import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/paths.dart';
import 'data/database.dart';
import 'data/settings_repository.dart';
import 'data/sync_stamp.dart';
import 'downloads/android_download_notifier.dart';
import 'downloads/download_notifier.dart';
import 'downloads/download_repository.dart';
import 'downloads/download_service.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/play_history_repository.dart';
import 'library/scan_queue.dart';
import 'library/search_repository.dart';
import 'player/player_service.dart';
import 'theme/font_service.dart';
import 'theme/theme_spec.dart';
import 'ui/shell/window_controls.dart';
import 'youtube/yt_import_service.dart';
import 'youtube/ytdlp_runner.dart';

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

// --- YouTube ---------------------------------------------------------------

/// Device-local settings (Wi-Fi only, system yt-dlp).
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final ytDlpRunnerProvider = Provider<YtDlpRunner>(
  (ref) => _unwired('ytDlpRunnerProvider'),
);

final ytImportServiceProvider = Provider<YtImportService>(
  (ref) => _unwired('ytImportServiceProvider'),
);

/// Platform flags for the YouTube settings; tests override them.
final isAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);
final isLinuxProvider = Provider<bool>((ref) => Platform.isLinux);

/// The installed yt-dlp version, or null when it is missing. Read when
/// Settings opens (a user action) and again after an update.
final ytDlpVersionProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(ytDlpRunnerProvider).version(),
);

/// The Wi-Fi only setting: its stored value, else the platform default.
final wifiOnlySettingProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(
        kWifiOnly,
        fallback: wifiOnlyDefault(isAndroid: ref.watch(isAndroidProvider)),
      ),
);

/// Whether Linux runs the system yt-dlp (read by `main()` at startup).
final useSystemYtDlpProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kYtdlpUseSystem, fallback: false),
);

/// One playlist row (for its YouTube link and last sync time).
final playlistRowProvider = StreamProvider.autoDispose
    .family<Playlist?, String>(
      (ref, id) => ref.watch(libraryRepositoryProvider).watchPlaylist(id),
    );

/// Bundled and imported fonts.
final fontServiceProvider = Provider<FontService>(
  (ref) => _unwired('fontServiceProvider'),
);

// --- Downloads -------------------------------------------------------------

/// This device's YouTube download rows. `main()` overrides it with the
/// instance the queue uses.
final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(ref.watch(databaseProvider)),
);

/// Shows the queue outside the app: the Android notification, nothing on
/// desktop. `main()` overrides it with the instance the queue uses.
final downloadNotifierProvider = Provider<DownloadNotifier>(
  (ref) => ref.watch(isAndroidProvider)
      ? AndroidDownloadNotifier()
      : const NoopDownloadNotifier(),
);

/// The YouTube download queue.
final downloadServiceProvider = Provider<DownloadService>(
  (ref) => _unwired('downloadServiceProvider'),
);

/// Asks for the notification permission (Android 13+) when the user starts a
/// download; never blocks. Tests replace it to keep off platform channels.
final notificationPermissionProvider = Provider<Future<void> Function()>(
  (ref) => ensureNotificationPermission,
);

/// The download queue's state, starting with its current value.
final downloadSnapshotProvider = StreamProvider<DownloadSnapshot>(
  (ref) => ref.watch(downloadServiceProvider).snapshots,
);

/// Whether songs are downloading or waiting to (the app-wide indicator).
final downloadsActiveProvider = Provider<bool>(
  (ref) => ref.watch(
    downloadSnapshotProvider.select((a) {
      final s = a.value;
      return s != null && s.active + s.queued > 0;
    }),
  ),
);

/// How far one playlist's downloads have come on this device.
final playlistDownloadProvider = StreamProvider.autoDispose
    .family<PlaylistDownloadStatus, String>(
      (ref, playlistId) =>
          ref.watch(downloadRepositoryProvider).watchPlaylist(playlistId),
    );

/// Download state by track id for one playlist's YouTube tracks (only those
/// with a download row): one stream per playlist, which its rows select from.
final trackDownloadStatesProvider = StreamProvider.autoDispose
    .family<Map<String, String>, String>((ref, playlistId) {
      // The ids only, so a change elsewhere in the rows doesn't resubscribe.
      final ids = ref.watch(
        playlistTracksProvider(playlistId)
            .select((a) => a.value?.map((e) => e.track.id).join('\n')),
      );
      if (ids == null) return const Stream.empty();
      return ref
          .watch(downloadRepositoryProvider)
          .watchTrackStates(ids.isEmpty ? const [] : ids.split('\n'));
    });

/// One YouTube track's download state (null without a download row).
final trackDownloadStateProvider = StreamProvider.autoDispose
    .family<String?, String>(
      (ref, trackId) => ref
          .watch(downloadRepositoryProvider)
          .watchTrackStates([trackId])
          .map((states) => states[trackId]),
    );

/// The playlists downloaded on this device.
final downloadEnabledPlaylistsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(downloadRepositoryProvider).watchEnabledPlaylists(),
);

/// A downloading track, for its title in the downloads sheet.
final downloadTrackProvider = FutureProvider.autoDispose.family<Track?, String>(
  (ref, trackId) => ref.watch(downloadRepositoryProvider).ytTrack(trackId),
);

/// Bytes of all finished YouTube downloads, for Settings.
final downloadTotalBytesProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(downloadRepositoryProvider).watchTotalBytes(),
);

/// Finished-download bytes per playlist, for Settings.
final downloadBytesPerPlaylistProvider =
    StreamProvider.autoDispose<List<(String playlistId, int bytes)>>(
      (ref) => ref.watch(downloadRepositoryProvider).watchBytesPerPlaylist(),
    );
