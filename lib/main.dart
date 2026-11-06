import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:window_manager/window_manager.dart';
import 'package:just_audio/just_audio.dart'
    show AndroidEqualizer, AudioPipeline;

import 'account/account_backend.dart';
import 'account/account_service.dart';
import 'account/secure_session_storage.dart';
import 'app.dart';
import 'core/app_version.dart';
import 'core/connectivity.dart';
import 'core/crash_reporting/crash_breadcrumbs.dart';
import 'core/crash_reporting/crash_config.dart';
import 'core/crash_reporting/crash_reporter.dart';
import 'core/log.dart';
import 'player/age_restricted_stream_source.dart';
import 'player/runtime_prompter.dart';
import 'youtube/deno_installer.dart';
import 'youtube/js_runtime.dart';
import 'innertube/yt_session_store.dart';
import 'core/paths.dart';
import 'core/result.dart';
import 'data/database.dart';
import 'data/settings_repository.dart';
import 'discord/discord_ipc.dart';
import 'discord/discord_presence.dart';
import 'data/sync_stamp.dart';
import 'downloads/android_download_notifier.dart';
import 'downloads/download_notifier.dart';
import 'downloads/download_repository.dart';
import 'downloads/download_service.dart';
import 'innertube/innertube_client.dart';
import 'innertube/play_reporter.dart';
import 'innertube/player_stream_source.dart';
import 'innertube/transport.dart';
import 'innertube/ytm_service.dart';
import 'library/favorites.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/play_history_repository.dart';
import 'library/search_repository.dart';
import 'library/tag_reader.dart';
import 'library/yt_tracks.dart';
import 'lyrics/file_lyrics.dart';
import 'lyrics/lrclib.dart';
import 'lyrics/lyrics_service.dart';
import 'lyrics/lyrics_store.dart';
import 'lyrics/ytm_lyrics.dart';
import 'stats/listen_recorder.dart';
import 'stats/listen_store.dart';
import 'stats/stats_repository.dart';
import 'player/audio_session_binding.dart';
import 'player/composite_track_resolver.dart';
import 'player/just_audio_backend.dart';
import 'player/media_controls.dart';
import 'player/player_service.dart';
import 'player/stream_resolver.dart';
import 'player/stream_source.dart';
import 'player/track_resolver.dart';
import 'player/equalizer.dart';
import 'providers.dart';
import 'router.dart';
import 'sync/cloud/cloud_files.dart';
import 'sync/cloud/cloud_remote.dart';
import 'sync/cloud/cloud_sync.dart';
import 'theme/font_service.dart';
import 'theme/theme_repository.dart';
import 'ui/account/account_dialogs.dart' show askMergeOrStartEmpty;
import 'ui/library/import_dialog.dart';
import 'youtube/android_ytdlp_runner.dart';
import 'youtube/desktop_ytdlp_runner.dart';
import 'youtube/share_intents.dart';
import 'youtube/thumbnail_fetcher.dart';
import 'youtube/yt_import_service.dart';
import 'youtube/ytdlp_client.dart';
import 'youtube/ytdlp_installer.dart';
import 'youtube/ytdlp_runner.dart';

/// Dev-only: `--dart-define=SONGIES_FORCE_YTDLP=true` plays every stream
/// through yt-dlp (no Innertube), for timing the slow route. Ignored in
/// release builds.
const _forceYtDlp =
    !kReleaseMode && bool.fromEnvironment('SONGIES_FORCE_YTDLP');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final paths = await AppPaths.resolve();
  await paths.ensureCreated();
  await AppLog.init(paths.logs);
  installErrorLogging();
  _deleteOldSyncDir(paths.root);

  final db = AppDatabase.open(paths.db);
  final stamp = await SyncStamp.load(db);
  final listenStore = ListenStore(db, stamp);
  unawaited(listenStore.prune());

  await initAudioPlatform();
  if (Platform.isWindows || Platform.isLinux) await _initDesktopWindow();

  final library = LibraryRepository(db, stamp);
  // The built-in Favorites exists from the first start, so a star always
  // has somewhere to go.
  final favorites = FavoritesRepository(db, stamp);
  await favorites.ensureFavorites();
  final search = SearchRepository(db);
  final history = PlayHistoryRepository(db);
  final artCache = ArtCache(paths.art);
  final scanner = LibraryScanner(
    db,
    stamp,
    AudioMetadataTagReader(),
    artCache,
    library,
  );

  final settings = SettingsRepository(db);

  // Crash reports: only in a release build with a DSN, and only while the
  // setting is on. The setting lives in the database, so crashes before it
  // opens aren't reported. Started after the log handlers, so Sentry hands
  // errors on to them.
  final crashReporter = CrashReporter.sentry(
    dataRoot: paths.root.path,
    settings: settings,
  );
  await crashReporter.applySetting(
    await settings.getBool(kCrashReports, fallback: true),
  );
  crashReporter.follow(settings.watchBool(kCrashReports, fallback: true));

  // Imported fonts must be registered before the first frame.
  final fonts = FontService(db, stamp, paths.fonts);
  await fonts.loadImported();

  // The active theme, so the first frame already shows it.
  final themes = ThemeRepository(db, stamp, settings);
  final initialTheme = await loadInitialThemeSpec(themes.watchActive());

  // YouTube. Nothing here touches the network or runs yt-dlp: that only
  // happens on a user action or during playback.
  final runner = await _ytDlpRunner(paths, settings);
  final cookiesDir = Directory(p.join(paths.root.path, 'tmp'));
  _deleteLeftoverCookies(cookiesDir);
  final ytClient = YtDlpClient(runner, cookiesDir: cookiesDir);
  final thumbnails = ThumbnailFetcher(
    artCache,
    (u) => httpDownload(u, totalTimeout: const Duration(seconds: 15)),
  );
  final ytImport = YtImportService(db, stamp, ytClient, thumbnails);
  final ytTracks = YtTrackStore(db, stamp, thumbnails);
  final innertube = InnertubeClient(HttpInnertubeTransport(), settings);
  final network = ConnectivityPlusStatus();
  // Instant streams from Innertube; yt-dlp when every client is refused.
  final innertubeStreams = InnertubeStreamSource(innertube);
  if (_forceYtDlp) AppLog.i('SONGIES_FORCE_YTDLP: Innertube streams off');
  // Age-restricted songs retry signed in, with a JS runtime for yt-dlp.
  // The session comes from the provider container, made further down.
  SessionLoader loadSession = () async => null;
  final runtimes = JsRuntimeFinder(
    binDir: paths.bin,
    isAndroid: Platform.isAndroid,
    isWindows: Platform.isWindows,
  );
  final ageAuth = AgeRestrictedAuth(() => loadSession(), runtimes);
  final denoInstaller = Platform.isAndroid
      ? null
      : DenoInstaller(
          paths.bin,
          download: (uri, {onProgress}) =>
              httpDownload(uri, onProgress: onProgress),
          isWindows: Platform.isWindows,
        );
  final runtimePrompter = RuntimePrompter();
  final streams = StreamResolver(
    AgeRestrictedStreamSource(
      FallbackStreamSource(
        playbackSources(
          innertube: innertubeStreams,
          ytDlp: ytClient,
          forceYtDlp: _forceYtDlp,
        ),
      ),
      ytClient,
      ageAuth,
    ),
    network,
    settings,
  );
  final resolver = CompositeTrackResolver(
    LocalTrackResolver(db),
    streams,
    onStreamMetadata: (t, s) {
      // Fire-and-forget: upgrades blurry pre-yt2 covers while the song plays.
      ytImport.refreshArtwork([t]);
      return library.updateTrackMetadata(
        t.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        durationMs: s.durationMs,
      );
    },
  );

  // Downloads: start() only resumes work already queued; nothing runs when
  // the queue is empty.
  final downloadRepo = DownloadRepository(db);
  final DownloadNotifier downloadNotifier = Platform.isAndroid
      ? AndroidDownloadNotifier()
      : const NoopDownloadNotifier();
  final downloads = DownloadService(
    repo: downloadRepo,
    client: ytClient,
    network: network,
    settings: settings,
    ytDir: paths.libraryYt,
    concurrency: Platform.isAndroid ? 2 : 3,
    wifiOnlyFallback: Platform.isAndroid,
    notifier: downloadNotifier,
    ageAuth: ageAuth,
    onDownloaded: (trackId, d) async {
      await library.updateTrackMetadata(
        trackId,
        title: d.title,
        artist: d.artist,
        album: d.album,
        durationMs: d.durationMs,
      );
      final t = await library.trackById(trackId);
      if (t != null) ytImport.refreshArtwork([t]);
    },
    onUnavailable: (trackId) async {
      await library.markUnavailable(trackId);
    },
  );
  unawaited(downloads.start());

  // The equalizer: Android's system effect in the player's pipeline; mpv's
  // filter on desktop (hooked before the first mpv player is made).
  final androidEq = Platform.isAndroid ? AndroidEqualizer() : null;
  final equalizer = equalizerFor(
    android: Platform.isAndroid,
    windows: Platform.isWindows,
    androidEq: androidEq,
    mpv: MediaKitMpvCommands.new,
  );
  final backend = JustAudioBackend(
    pipeline: androidEq == null
        ? null
        : AudioPipeline(androidAudioEffects: [androidEq]),
  );
  // Not awaited: Android's bands are only known once a song has loaded.
  unawaited(
    applyStoredEqPreset(
      read: () => settings.getString(kEqPreset),
      apply: equalizer.apply,
    ),
  );
  final player = PlayerService(
    backend,
    resolver,
    onMissing: scanner.markMissing,
    onTrackStarted: (track, playlistId) => history.record(track.id, playlistId),
    onUnavailable: library.markUnavailable,
    network: network,
    onNeedsRuntime: denoInstaller == null ? null : runtimePrompter.ask,
  );
  // A cover or details that land after a song was queued reach the player.
  ytTracks.changes.listen(player.updateTrack);
  bindAudioSession(
    becomingNoisy: backend.becomingNoisy,
    interruptions: backend.interruptions,
    player: player,
  );

  // Lyrics: looked up only while a lyrics view is open.
  final ytm = YtmService(innertube);
  final lyrics = LyricsService(
    db: db,
    store: LyricsStore(db, stamp),
    file: FileLyricsSource(AudioMetadataTagReader()),
    lrclib: LrclibSource(
      ioHttpGet,
      userAgent:
          'Songies/$appVersion (https://github.com/DenisMartonak/Songie)',
    ),
    ytm: YtmLyricsSource(ytm),
    network: network,
  );

  // Accounts: Supabase starts in the background, so a slow keyring or no
  // network never holds up the first frame; signed out, it never touches
  // the keyring. If it fails, the app runs signed out.
  // Cloud sync: follows the account (see cloudSyncFollowerProvider); signed
  // out it never touches Supabase, so the client is read only when needed.
  final cloudRemote = SupabaseCloudRemote(() => Supabase.instance.client);
  final cloudFiles = CloudFiles(
    db: db,
    remote: cloudRemote,
    fontsDir: paths.fonts,
    artDir: paths.art,
    // Registers fonts that arrived; the theme asks again (registrations).
    onFontsArrived: fonts.loadImported,
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  final cloudSync = CloudSync(
    db: db,
    stamp: stamp,
    remote: cloudRemote,
    files: cloudFiles,
    settings: settings,
    network: network.changes,
    fontsDir: paths.fonts,
    // Signing in as another account than last time: asked on the app's
    // navigator once it is up.
    askMerge: (cancelled, unsent) => askMergeOrStartEmpty(
      navigatorKey,
      cancelled: cancelled,
      unsent: unsent,
    ),
  );
  final accounts = AccountService(
    PendingAccountBackend(connectSupabase(SettingsSessionMarker(settings))),
    network: network.changes,
    deleteSyncFiles: cloudFiles.deleteAll,
    // Stopped first, so it can't upload files while they are deleted.
    stopSync: cloudSync.stop,
    startSync: cloudSync.start,
  );

  final router = buildRouter(navigatorKey: navigatorKey);
  try {
    final controls = await MediaControlsBinding.create(player, artCache);
    controls.openNowPlayingRequests.listen((_) => openNowPlaying(router));
  } catch (e, s) {
    AppLog.e('System media controls unavailable', e, s);
  }

  final container = ProviderContainer(
    overrides: [
      appPathsProvider.overrideWithValue(paths),
      databaseProvider.overrideWithValue(db),
      syncStampProvider.overrideWithValue(stamp),
      libraryRepositoryProvider.overrideWithValue(library),
      favoritesRepositoryProvider.overrideWithValue(favorites),
      searchRepositoryProvider.overrideWithValue(search),
      playHistoryRepositoryProvider.overrideWithValue(history),
      libraryScannerProvider.overrideWithValue(scanner),
      artCacheProvider.overrideWithValue(artCache),
      playerServiceProvider.overrideWithValue(player),
      settingsRepositoryProvider.overrideWithValue(settings),
      ytDlpRunnerProvider.overrideWithValue(runner),
      equalizerProvider.overrideWithValue(equalizer),
      jsRuntimeFinderProvider.overrideWithValue(runtimes),
      denoInstallerProvider.overrideWithValue(denoInstaller),
      runtimePrompterProvider.overrideWithValue(runtimePrompter),
      ytImportServiceProvider.overrideWithValue(ytImport),
      ytTrackStoreProvider.overrideWithValue(ytTracks),
      innertubeClientProvider.overrideWithValue(innertube),
      ytSessionStoreProvider.overrideWithValue(SecureYtSessionStore()),
      networkStatusProvider.overrideWithValue(network),
      lyricsServiceProvider.overrideWithValue(lyrics),
      downloadRepositoryProvider.overrideWithValue(downloadRepo),
      downloadNotifierProvider.overrideWithValue(downloadNotifier),
      downloadServiceProvider.overrideWithValue(downloads),
      fontServiceProvider.overrideWithValue(fonts),
      themeRepositoryProvider.overrideWithValue(themes),
      statsRepositoryProvider.overrideWithValue(StatsRepository(db)),
      initialThemeSpecProvider.overrideWithValue(initialTheme),
      accountServiceProvider.overrideWithValue(accounts),
      cloudSyncProvider.overrideWithValue(cloudSync),
    ],
  );
  container.read(cloudSyncFollowerProvider);
  // Reads two device-local settings only: no keyring, no network, no timer.
  // Awaited, so the first Home load already knows whether to go signed in.
  await container.read(ytAuthProvider.notifier).load();
  loadSession = container.read(ytAuthProvider.notifier).ensureSession;
  await _recheckUnavailableOnce(library, settings);
  // Reports songs heard for 30 s to YouTube (to the account's history when
  // signed in); reacts to player state only.
  PlayReporter(
    player.states,
    innertubeStreams,
    HttpInnertubeTransport(),
    session: container.read(ytAuthProvider.notifier).ensureSession,
    accountTracking: ytm.accountTracking,
  );
  // Records listening statistics; reacts to player events only.
  ListenRecorder(player.states, player.trackStarts, listenStore);
  // Shows the playing song on Discord when the setting is on (desktop, with
  // the Discord app open); reacts to player and setting changes only.
  if ((Platform.isWindows || Platform.isLinux) && kDiscordClientId.isNotEmpty) {
    DiscordPresence(
      states: player.states,
      enabled: settings.watchBool(kDiscordPresence, fallback: false),
      rpc: DiscordRpc(connectToDiscord),
      clientId: kDiscordClientId,
    );
  }
  // Route templates and play/pause/skip words as crash breadcrumbs; nothing
  // is recorded while Sentry is off.
  if (crashReportingBuilt()) {
    followRoutes(router);
    followPlayer(player.states);
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: SongiesApp(router: router, checkForUpdates: true),
    ),
  );

  // Android Share: each shared playlist link opens the import dialog,
  // prefilled. Subscribed after the first frame so the navigator exists.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    sharedPlaylistLinks(null).listen((link) {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      showImportDialog(context, initialLink: link, router: router);
    });
  });
}

/// Android runs yt-dlp through youtubedl-android; desktop runs the binary in
/// `<appData>/bin` (installed on demand), or on Linux optionally the system
/// one from PATH.
Future<YtDlpRunner> _ytDlpRunner(
  AppPaths paths,
  SettingsRepository settings,
) async {
  if (Platform.isAndroid) return AndroidYtDlpRunner();
  final installer = YtDlpInstaller(
    paths.bin,
    download: httpDownload,
    isWindows: Platform.isWindows,
  );
  final useSystem =
      Platform.isLinux &&
      await settings.getBool(kYtdlpUseSystem, fallback: false);
  return DesktopYtDlpRunner(
    binary: () => installer.binary,
    installer: installer,
    systemBinary: useSystem ? 'yt-dlp' : null,
  );
}

/// Unflags YouTube songs marked unavailable before age-restricted songs had
/// their own error, once per device, so each gets one more try.
Future<void> _recheckUnavailableOnce(
  LibraryRepository library,
  SettingsRepository settings,
) async {
  if (await settings.getBool(kUnavailableRecheckDone, fallback: false)) {
    return;
  }
  switch (await library.clearUnavailableYtTracks()) {
    case Ok(:final value):
      AppLog.i('Unflagged $value unavailable YouTube songs for a re-check');
      await settings.setBool(kUnavailableRecheckDone, true);
    case Err(:final failure):
      AppLog.w('Unavailable re-check failed: ${failure.message}');
  }
}

/// Deletes the home-network sync's directory (its TLS certificate and key),
/// left behind by versions before cloud sync.
void _deleteOldSyncDir(Directory root) {
  try {
    final dir = Directory(p.join(root.path, 'sync'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (e) {
    AppLog.w('Could not remove the old sync directory: $e');
  }
}

/// Deletes cookies files a crashed signed-in yt-dlp run left behind.
void _deleteLeftoverCookies(Directory dir) {
  try {
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (p.basename(f.path).startsWith('cookies-')) f.deleteSync();
    }
  } catch (e) {
    AppLog.w('Could not clear old yt-dlp cookies files: $e');
  }
}

Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    minimumSize: Size(900, 600),
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
