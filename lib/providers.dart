import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connectivity.dart';
import 'core/paths.dart';
import 'core/result.dart';
import 'data/database.dart';
import 'data/settings_repository.dart';
import 'data/sync_stamp.dart';
import 'downloads/android_download_notifier.dart';
import 'downloads/download_notifier.dart';
import 'downloads/download_repository.dart';
import 'downloads/download_service.dart';
import 'innertube/innertube_client.dart';
import 'innertube/ytm_models.dart';
import 'innertube/ytm_service.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/play_history_repository.dart';
import 'library/scan_queue.dart';
import 'library/search_repository.dart';
import 'library/yt_tracks.dart';
import 'player/player_service.dart';
import 'player/radio_controller.dart';
import 'theme/app_theme.dart';
import 'theme/cover_palette.dart';
import 'theme/font_service.dart';
import 'theme/theme_repository.dart';
import 'theme/theme_service.dart';
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

/// YouTube imports handed to their playlist page before its entries have
/// reached it: the import dialog adds the new playlist's id as it opens the
/// page, and the page shows skeleton rows for it until the entries arrive.
class PendingImports extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String playlistId) => state = {...state, playlistId};

  /// Does nothing once the app's providers are gone.
  void remove(String playlistId) {
    if (!ref.mounted) return;
    if (state.contains(playlistId)) {
      state = {...state}..remove(playlistId);
    }
  }
}

final pendingImportsProvider = NotifierProvider<PendingImports, Set<String>>(
  PendingImports.new,
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

// --- Theme -----------------------------------------------------------------

/// Built-in and saved themes, and the device's active-theme choice.
final themeRepositoryProvider = Provider<ThemeRepository>(
  (ref) => ThemeRepository(
    ref.watch(databaseProvider),
    ref.watch(syncStampProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

/// The active theme entry.
final activeThemeProvider = StreamProvider<ThemeEntry>(
  (ref) => ref.watch(themeRepositoryProvider).watchActive(),
);

/// The theme to show until [activeThemeProvider] first emits. `main()` loads
/// the active one before the first frame, so startup doesn't flash (or tween
/// from) Default.
final initialThemeSpecProvider = Provider<ThemeSpec>(
  (ref) => ThemeSpec.builtInDefault,
);

/// The active theme's spec.
final themeSpecProvider = Provider<ThemeSpec>(
  (ref) =>
      ref.watch(activeThemeProvider).value?.spec ??
      ref.watch(initialThemeSpecProvider),
);

/// The family the active theme renders with: an imported font that is
/// missing on this device falls back to Inter.
final resolvedFontFamilyProvider = Provider<String>(
  (ref) => ref
      .watch(fontServiceProvider)
      .resolveFamily(ref.watch(themeSpecProvider)),
);

/// Cover palettes (cached on disk next to the art).
final coverPaletteServiceProvider = Provider<CoverPaletteService>(
  (ref) => CoverPaletteService(ref.watch(artCacheProvider)),
);

/// The playing track's art ref; changes only when the track (or its art)
/// does.
final currentArtRefProvider = Provider<String?>(
  (ref) => ref.watch(
    playerStateProvider.select((s) => s.value?.current?.artworkRef),
  ),
);

/// The playing track's cover palette. Extraction runs only on a track change,
/// and only the latest track's result is ever emitted, so a song skipped past
/// never lends its colours.
final coverPaletteProvider = StreamProvider<CoverPalette?>((ref) {
  final refs = StreamController<String?>();
  ref.onDispose(refs.close);
  ref.listen<String?>(
    currentArtRefProvider,
    (_, next) => refs.add(next),
    fireImmediately: true,
  );
  return ref.watch(coverPaletteServiceProvider).paletteStream(refs.stream);
});

/// The palette of one cover for a page (a playlist hero, Home's glow), or
/// null without art. These requests are never superseded by the playing
/// track's, so a page always gets its colours.
final artPaletteProvider = FutureProvider.autoDispose
    .family<CoverPalette?, String?>((ref, artRef) {
      if (artRef == null) return null;
      return ref
          .watch(coverPaletteServiceProvider)
          .paletteFor(artRef, supersede: false);
    });

/// The app's colours: the active theme, following the playing track's cover
/// when the theme asks for it.
final songiesColorsProvider = Provider<SongiesColors>((ref) {
  final spec = ref.watch(themeSpecProvider);
  final palette = spec.followCover
      ? ref.watch(coverPaletteProvider).value
      : null;
  return songiesColorsFor(
    spec,
    palette: palette,
    fontFamily: ref.watch(resolvedFontFamilyProvider),
  );
});

/// The app's [ThemeData], rebuilt only when the colours or theme change.
final songiesThemeProvider = Provider<ThemeData>(
  (ref) => buildThemeData(
    ref.watch(themeSpecProvider),
    colors: ref.watch(songiesColorsProvider),
  ),
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

/// Device-local settings (Wi-Fi only downloads/streaming, system yt-dlp).
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final ytDlpRunnerProvider = Provider<YtDlpRunner>(
  (ref) => _unwired('ytDlpRunnerProvider'),
);

final ytImportServiceProvider = Provider<YtImportService>(
  (ref) => _unwired('ytImportServiceProvider'),
);

/// YouTube's Innertube API (YouTube Music browse/search, instant streaming).
final innertubeClientProvider = Provider<InnertubeClient>(
  (ref) => _unwired('innertubeClientProvider'),
);

/// YouTube Music search, radio and (later) browse.
final ytmServiceProvider = Provider<YtmService>(
  (ref) => YtmService(ref.watch(innertubeClientProvider)),
);

/// Track rows for played YouTube Music results.
final ytTrackStoreProvider = Provider<YtTrackStore>(
  (ref) => _unwired('ytTrackStoreProvider'),
);

/// Plays YouTube Music songs with their radio queued after them.
final radioControllerProvider = Provider<RadioController>((ref) {
  final c = RadioController(
    ref.watch(playerServiceProvider),
    ref.watch(ytmServiceProvider),
    ref.watch(ytTrackStoreProvider),
  );
  ref.onDispose(c.dispose);
  return c;
});

/// The device's network (one instance, shared with the player and the
/// download queue).
final networkStatusProvider = Provider<NetworkStatus>(
  (ref) => _unwired('networkStatusProvider'),
);

/// YouTube Music could not be searched because the device is offline.
class YtmOffline implements Exception {
  const YtmOffline();

  @override
  String toString() => 'YtmOffline';
}

/// A YouTube Music request failed for any other reason.
class YtmLoadFailed implements Exception {
  const YtmLoadFailed(this.failure);

  final Failure failure;

  @override
  String toString() => 'YtmLoadFailed($failure)';
}

/// One tab of YouTube Music search results for a (trimmed) query: fetched
/// when first watched, by a user's search, and never retried on its own
/// (Retry invalidates it). Each query is its own instance, so a late answer
/// for an older query lands in an instance nothing shows any more.
///
/// Fails with [YtmOffline] when offline (without a request) or when a network
/// failure turns out to be the device going offline, else [YtmLoadFailed].
final ytmSearchProvider = FutureProvider.autoDispose
    .family<YtmSearchPage, (String, YtmSearchKind)>(
      (ref, arg) async {
        final (query, kind) = arg;
        final network = ref.watch(networkStatusProvider);
        final ytm = ref.watch(ytmServiceProvider);
        if (await network.current() == NetworkKind.offline) {
          throw const YtmOffline();
        }
        switch (await ytm.search(query, kind)) {
          case Ok(:final value):
            return value;
          case Err(:final failure):
            if (failure.kind == FailureKind.network &&
                await network.current() == NetworkKind.offline) {
              throw const YtmOffline();
            }
            throw YtmLoadFailed(failure);
        }
      },
      // A failed search waits for the user's Retry: no idle requests.
      retry: (_, _) => null,
    );

/// The YouTube Music home feed: fetched when Home is first shown, kept for the
/// session, and fetched again only by pull to refresh, Retry, accepting
/// consent or resetting recommendations (each invalidates it). Never retried
/// on its own: no idle requests.
///
/// Fails with [YtmOffline] when offline (without a request) or when a network
/// failure turns out to be the device going offline, else [YtmLoadFailed].
final ytmHomeProvider = FutureProvider<YtmHome>((ref) async {
  final network = ref.watch(networkStatusProvider);
  final ytm = ref.watch(ytmServiceProvider);
  if (await network.current() == NetworkKind.offline) {
    throw const YtmOffline();
  }
  switch (await ytm.home()) {
    case Ok(:final value):
      return value;
    case Err(:final failure):
      if (failure.kind == FailureKind.network &&
          await network.current() == NetworkKind.offline) {
        throw const YtmOffline();
      }
      throw YtmLoadFailed(failure);
  }
}, retry: (_, _) => null);

/// YouTube asking the user to accept its terms (see [InnertubeClient]).
final ytConsentRequiredProvider = StreamProvider<bool>(
  (ref) => ref.watch(innertubeClientProvider).consentRequired,
);

/// Whether the consent sheet was already shown this session (Not now holds
/// until the app restarts; Accept holds for good, in the client).
final consentAskedProvider = NotifierProvider<ConsentAsked, bool>(
  ConsentAsked.new,
);

class ConsentAsked extends Notifier<bool> {
  @override
  bool build() => false;

  void markAsked() => state = true;
}

/// Platform flags for the YouTube settings; tests override them.
final isAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);
final isLinuxProvider = Provider<bool>((ref) => Platform.isLinux);

/// The installed yt-dlp version, or null when it is missing. Read when
/// Settings opens (a user action) and again after an update.
final ytDlpVersionProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(ytDlpRunnerProvider).version(),
);

/// The Wi-Fi only downloads setting: its stored value, else the platform
/// default.
final wifiOnlySettingProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(
        kWifiOnly,
        fallback: wifiOnlyDefault(isAndroid: ref.watch(isAndroidProvider)),
      ),
);

/// The Wi-Fi only streaming setting (off unless turned on).
final wifiOnlyStreamingSettingProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kWifiOnlyStreaming, fallback: false),
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

/// The fonts the user imported. Widgets that resolve a theme's font watch it
/// to update once a new font is imported and registered.
final importedFontsProvider = StreamProvider.autoDispose<List<FontEntry>>(
  (ref) => ref.watch(fontServiceProvider).watchAll(),
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
