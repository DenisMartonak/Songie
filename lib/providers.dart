import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart'
    show ImageProvider, NetworkImage, ResizeImage, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connectivity.dart';
import 'core/log.dart';
import 'innertube/yt_session_store.dart';
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
import 'lyrics/lyrics_service.dart';
import 'player/player_service.dart';
import 'player/radio_controller.dart';
import 'stats/stats_models.dart';
import 'stats/stats_repository.dart';
import 'theme/app_theme.dart';
import 'theme/cover_palette.dart';
import 'theme/font_service.dart';
import 'theme/image_palette.dart';
import 'theme/theme_repository.dart';
import 'sync/device_identity.dart';
import 'sync/peer_repository.dart';
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

/// This device's sync TLS identity (loaded in `main()`).
final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => _unwired('deviceIdentityProvider'),
);

final peerRepositoryProvider = Provider<PeerRepository>(
  (ref) => PeerRepository(ref.watch(databaseProvider)),
);

/// The name other devices see: the saved `device_name`, else the hostname on
/// desktop and `Android` on Android.
final deviceNameProvider = StreamProvider.autoDispose<String>((ref) {
  final fallback = ref.watch(isAndroidProvider)
      ? 'Android'
      : Platform.localHostname;
  return ref
      .watch(settingsRepositoryProvider)
      .watchString(kDeviceName)
      .map((v) => v == null || v.trim().isEmpty ? fallback : v.trim());
});

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

// --- Lyrics ----------------------------------------------------------------

final lyricsServiceProvider = Provider<LyricsService>(
  (ref) => _unwired('lyricsServiceProvider'),
);

/// Search again for one track: each bump forces a fresh lookup that ignores
/// the stored result.
class LyricsRetry extends Notifier<int> {
  LyricsRetry(this.trackId);

  final String trackId;

  @override
  int build() => 0;

  void searchAgain() => state++;
}

final lyricsRetryProvider = NotifierProvider.autoDispose
    .family<LyricsRetry, int, String>(LyricsRetry.new);

/// One track's lyrics, looked up while a lyrics view watches it. The track
/// comes from the player's queue, else the library.
final lyricsProvider = FutureProvider.autoDispose.family<LyricsState, String>((
  ref,
  trackId,
) async {
  final force = ref.watch(lyricsRetryProvider(trackId)) > 0;
  final service = ref.watch(lyricsServiceProvider);
  final queued = ref
      .read(playerServiceProvider)
      .state
      .queue
      .where((t) => t.id == trackId);
  final track = queued.isNotEmpty
      ? queued.first
      : await ref.read(libraryRepositoryProvider).trackById(trackId);
  if (track == null) return const LyricsNone();
  return service.lookup(track, force: force);
}, retry: (_, _) => null);

/// Whether the desktop lyrics panel is open. Session-only: it starts closed
/// on every launch.
class LyricsPanelOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final lyricsPanelOpenProvider = NotifierProvider<LyricsPanelOpen, bool>(
  LyricsPanelOpen.new,
);

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

final ytSessionStoreProvider = Provider<YtSessionStore>(
  (ref) => _unwired('ytSessionStoreProvider'),
);

final ytAuthProvider = NotifierProvider<YtAuth, YtAuthState>(YtAuth.new);

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
      (ref, arg) => _ytmLoad(ref, (ytm) => ytm.search(arg.$1, arg.$2)),
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
///
/// Signed in to YouTube ([YtSignedIn]), the first request goes out with the
/// session (read from the keyring on first need, R5). When YouTube refuses
/// it (HTTP 401/403) or answers explicitly signed out (R6: a missing marker
/// counts as signed in), or a stored cookie can't be sent (`invalidInput`),
/// the sign-in is marked expired
/// ([YtExpired]) and the regular feed is fetched once instead: no loop, and
/// later loads stay signed out until the user signs in again. Signing in
/// reloads Home; signing out reloads it when it shows (or is fetching) the
/// signed-in feed, so a late signed-in answer is never shown.
final ytmHomeProvider = FutureProvider<YtmHome>((ref) {
  // Whether this load went out signed in and its feed is the account's.
  var signedInFeed = false;
  ref.listen(ytAuthProvider, (prev, next) {
    final signedIn = next is YtSignedIn && prev is! YtSignedIn;
    final signedOut = next is YtSignedOut && signedInFeed;
    if (signedIn || signedOut) ref.invalidateSelf();
  });
  return _ytmLoad(ref, (ytm) async {
    final auth = ref.read(ytAuthProvider.notifier);
    final session = await auth.ensureSession();
    if (!ref.mounted) return const Err(Failure(FailureKind.unknown, 'stale'));
    if (session == null) return ytm.home();
    signedInFeed = true;
    final res = await ytm.home(session: session);
    if (!ref.mounted) return res;
    final bool refused;
    switch (res) {
      case Ok(:final value):
        if (value.markerMissing) {
          AppLog.i('ytm home: no signed-in marker; assuming signed in');
        }
        refused = !value.signedIn;
      case Err(:final failure):
        AppLog.w('ytm home (signed in) failed: ${failure.message}');
        final status = httpStatusOf(failure);
        // invalidInput: a stored cookie can't go in a header, so this
        // session will never work; treated like a refusal, not an error.
        refused =
            status == 401 ||
            status == 403 ||
            failure.kind == FailureKind.invalidInput;
    }
    if (!refused) return res;
    signedInFeed = false;
    AppLog.w('ytm home: YouTube sign-in expired; showing the regular feed');
    auth.markExpired();
    return ytm.home();
  });
}, retry: (_, _) => null);

/// Loads one YouTube Music page for a user's action: fails with [YtmOffline]
/// when offline (without a request) or when a network failure turns out to
/// be the device going offline, else [YtmLoadFailed].
Future<T> _ytmLoad<T>(
  Ref ref,
  Future<Result<T>> Function(YtmService) load,
) async {
  final network = ref.watch(networkStatusProvider);
  final ytm = ref.watch(ytmServiceProvider);
  if (await network.current() == NetworkKind.offline) {
    throw const YtmOffline();
  }
  switch (await load(ytm)) {
    case Ok(:final value):
      return value;
    case Err(:final failure):
      if (failure.kind == FailureKind.network &&
          await network.current() == NetworkKind.offline) {
        throw const YtmOffline();
      }
      throw YtmLoadFailed(failure);
  }
}

/// A YouTube Music artist page, fetched when its page opens and while it is
/// shown. Never retried on its own (Retry invalidates it).
final ytmArtistProvider = FutureProvider.autoDispose
    .family<YtmArtistPage, String>(
      (ref, browseId) => _ytmLoad(ref, (ytm) => ytm.artist(browseId)),
      retry: (_, _) => null,
    );

/// A YouTube Music album page; like [ytmArtistProvider].
final ytmAlbumProvider = FutureProvider.autoDispose
    .family<YtmAlbumPage, String>(
      (ref, browseId) => _ytmLoad(ref, (ytm) => ytm.album(browseId)),
      retry: (_, _) => null,
    );

/// The first page of a YouTube Music playlist; like [ytmArtistProvider]. Its
/// page fetches the continuations itself.
final ytmPlaylistProvider = FutureProvider.autoDispose
    .family<YtmPlaylistPage, String>(
      (ref, browseId) => _ytmLoad(ref, (ytm) => ytm.playlist(browseId)),
      retry: (_, _) => null,
    );

/// The image a YouTube Music cover shows for a thumbnail URL, decoded at
/// [cacheWidth] pixels wide (like `Image.network`'s `cacheWidth`). Tests
/// replace it so that nothing touches the network.
final ytmImageProvider =
    Provider<ImageProvider Function(String url, int? cacheWidth)>(
      (ref) =>
          (url, cacheWidth) =>
              ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(url)),
    );

/// The palette of a YouTube Music cover for a page's hero, from the very
/// [ImageProvider] the hero shows: read through Flutter's image cache, so
/// opening a page (again) makes no second request and browsing writes nothing
/// to the art cache. Null without an image or when it cannot be read.
final ytmCoverPaletteProvider = FutureProvider.autoDispose
    .family<CoverPalette?, ImageProvider?>(
      (ref, image) async => image == null ? null : paletteOfImage(image),
    );

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

// --- Listening stats -------------------------------------------------------

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => _unwired('statsRepositoryProvider'),
);

/// Stats for one period, live while a page or card shows them.
final periodStatsProvider = StreamProvider.autoDispose
    .family<PeriodStats, StatsPeriod>(
      (ref, period) => ref.watch(statsRepositoryProvider).watch(period),
    );

/// A track still in the library (not deleted) by id, or null: for rows that
/// show a recorded song, such as the stats page's top songs.
final libraryTrackProvider = FutureProvider.autoDispose.family<Track?, String>(
  (ref, id) => ref.watch(libraryRepositoryProvider).trackById(id),
);

/// The stats page's chosen period. Session-only: it starts at 7 days on
/// every launch.
class SelectedStatsPeriod extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod.week;

  void select(StatsPeriod period) => state = period;
}

final statsPeriodProvider = NotifierProvider<SelectedStatsPeriod, StatsPeriod>(
  SelectedStatsPeriod.new,
);
