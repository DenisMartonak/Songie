import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/log.dart';
import 'core/paths.dart';
import 'data/database.dart';
import 'data/sync_stamp.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/search_repository.dart';
import 'library/tag_reader.dart';
import 'player/audio_session_binding.dart';
import 'player/just_audio_backend.dart';
import 'player/media_controls.dart';
import 'player/player_service.dart';
import 'player/track_resolver.dart';
import 'providers.dart';
import 'router.dart';

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
  final artCache = ArtCache(paths.art);
  final scanner = LibraryScanner(
    db,
    stamp,
    AudioMetadataTagReader(),
    artCache,
    library,
  );

  final backend = JustAudioBackend();
  final player = PlayerService(
    backend,
    LocalTrackResolver(db),
    onMissing: scanner.markMissing,
  );
  bindAudioSession(
    becomingNoisy: backend.becomingNoisy,
    interruptions: backend.interruptions,
    player: player,
  );

  final router = buildRouter();
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
        libraryScannerProvider.overrideWithValue(scanner),
        artCacheProvider.overrideWithValue(artCache),
        playerServiceProvider.overrideWithValue(player),
      ],
      child: SongiesApp(router: router),
    ),
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
