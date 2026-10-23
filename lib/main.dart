import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/connectivity.dart';
import 'core/log.dart';
import 'core/paths.dart';
import 'data/database.dart';
import 'data/settings_repository.dart';
import 'data/sync_stamp.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/play_history_repository.dart';
import 'library/search_repository.dart';
import 'library/tag_reader.dart';
import 'player/audio_session_binding.dart';
import 'player/composite_track_resolver.dart';
import 'player/just_audio_backend.dart';
import 'player/media_controls.dart';
import 'player/player_service.dart';
import 'player/stream_resolver.dart';
import 'player/track_resolver.dart';
import 'providers.dart';
import 'router.dart';
import 'ui/library/import_dialog.dart';
import 'youtube/android_ytdlp_runner.dart';
import 'youtube/desktop_ytdlp_runner.dart';
import 'youtube/share_intents.dart';
import 'youtube/thumbnail_fetcher.dart';
import 'youtube/yt_import_service.dart';
import 'youtube/ytdlp_client.dart';
import 'youtube/ytdlp_installer.dart';
import 'youtube/ytdlp_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final paths = await AppPaths.resolve();
  await paths.ensureCreated();
  await AppLog.init(paths.logs);
  _installErrorLogging();

  final db = AppDatabase.open(paths.db);
  final stamp = await SyncStamp.load(db);

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

  // YouTube. Nothing here touches the network or runs yt-dlp: that only
  // happens on a user action or during playback.
  final settings = SettingsRepository(db);
  final runner = await _ytDlpRunner(paths, settings);
  final ytClient = YtDlpClient(runner);
  final ytImport = YtImportService(
    db,
    stamp,
    ytClient,
    ThumbnailFetcher(artCache, httpDownload),
  );
  final streams = StreamResolver(
    ytClient,
    ConnectivityPlusStatus(),
    settings,
    wifiOnlyFallback: Platform.isAndroid,
  );
  final resolver = CompositeTrackResolver(
    LocalTrackResolver(db),
    streams,
    onStreamMetadata: (t, s) => library.updateTrackMetadata(
      t.id,
      title: s.title,
      artist: s.artist,
      album: s.album,
      durationMs: s.durationMs,
    ),
  );

  final backend = JustAudioBackend();
  final player = PlayerService(
    backend,
    resolver,
    onMissing: scanner.markMissing,
    onTrackStarted: (track, playlistId) => history.record(track.id, playlistId),
    onUnavailable: library.markUnavailable,
  );
  bindAudioSession(
    becomingNoisy: backend.becomingNoisy,
    interruptions: backend.interruptions,
    player: player,
  );

  final navigatorKey = GlobalKey<NavigatorState>();
  final router = buildRouter(navigatorKey: navigatorKey);
  try {
    final controls = await MediaControlsBinding.create(player, artCache);
    controls.openNowPlayingRequests.listen((_) => openNowPlaying(router));
  } catch (e, s) {
    AppLog.e('System media controls unavailable', e, s);
  }

  runApp(
    ProviderScope(
      overrides: [
        appPathsProvider.overrideWithValue(paths),
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
      ],
      child: SongiesApp(router: router),
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
