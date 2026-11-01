import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_version.dart';
import 'core/connectivity.dart';
import 'core/log.dart';
import 'innertube/yt_session_store.dart';
import 'core/paths.dart';
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
import 'providers.dart';
import 'router.dart';
import 'sync/device_identity.dart';
import 'theme/font_service.dart';
import 'theme/theme_repository.dart';
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
  _installErrorLogging();

  final db = AppDatabase.open(paths.db);
  final stamp = await SyncStamp.load(db);
  final listenStore = ListenStore(db, stamp);
  unawaited(listenStore.prune());

  await initAudioPlatform();
  if (Platform.isWindows || Platform.isLinux) await _initDesktopWindow();

  final library = LibraryRepository(db, stamp);
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

  // Imported fonts must be registered before the first frame.
  final fonts = FontService(db, stamp, paths.fonts);
  await fonts.loadImported();

  // The active theme, so the first frame already shows it.
  final themes = ThemeRepository(db, stamp, settings);
  final initialTheme = await loadInitialThemeSpec(themes.watchActive());

  // YouTube. Nothing here touches the network or runs yt-dlp: that only
  // happens on a user action or during playback.
  final runner = await _ytDlpRunner(paths, settings);
  final ytClient = YtDlpClient(runner);
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
  final streams = StreamResolver(
    FallbackStreamSource(
      playbackSources(
        innertube: innertubeStreams,
        ytDlp: ytClient,
        forceYtDlp: _forceYtDlp,
      ),
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

  final backend = JustAudioBackend();
  final player = PlayerService(
    backend,
    resolver,
    onMissing: scanner.markMissing,
    onTrackStarted: (track, playlistId) => history.record(track.id, playlistId),
    onUnavailable: library.markUnavailable,
    network: network,
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

  // Sync's TLS identity. Failure here must not stop the app: only the Sync
  // devices page needs it.
  DeviceIdentity? deviceIdentity;
  try {
    deviceIdentity = await DeviceIdentity.loadOrCreate(paths.sync);
  } catch (e, s) {
    AppLog.e('Device identity unavailable', e, s);
  }

  final navigatorKey = GlobalKey<NavigatorState>();
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
      if (deviceIdentity != null)
        deviceIdentityProvider.overrideWithValue(deviceIdentity),
      databaseProvider.overrideWithValue(db),
      syncStampProvider.overrideWithValue(stamp),
      libraryRepositoryProvider.overrideWithValue(library),
      searchRepositoryProvider.overrideWithValue(search),
      playHistoryRepositoryProvider.overrideWithValue(history),
      libraryScannerProvider.overrideWithValue(scanner),
      artCacheProvider.overrideWithValue(artCache),
      playerServiceProvider.overrideWithValue(player),
      settingsRepositoryProvider.overrideWithValue(settings),
      ytDlpRunnerProvider.overrideWithValue(runner),
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
    ],
  );
  // Reads two device-local settings only: no keyring, no network, no timer.
  // Awaited, so the first Home load already knows whether to go signed in.
  await container.read(ytAuthProvider.notifier).load();
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

/// Sends uncaught errors to the log file, keeping the default presentation.
void _installErrorLogging() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.e(
      'Flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('Uncaught error', error, stack);
    return false;
  };
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
