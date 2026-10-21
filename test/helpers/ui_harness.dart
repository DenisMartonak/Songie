import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/library/search_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/library/pickers.dart';

import 'fake_audio_backend.dart';
import 'test_db.dart';

/// Resolves every track to a (fake) file so playback "works".
class _FileResolver implements TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

/// A [LibraryScanner] whose scans and imports the test controls.
class FakeScanner implements LibraryScanner {
  final List<String> scannedFolders = [];
  final List<String?> playlistNames = [];
  final List<String> imported = [];

  Stream<ScanProgress> Function(String folder, String? playlistName)? onScan;
  Future<Result<String>> Function(String path)? onImport;

  @override
  Stream<ScanProgress> scanFolder(
    String folderPath, {
    String? createPlaylistNamed,
  }) {
    scannedFolders.add(folderPath);
    playlistNames.add(createPlaylistNamed);
    return onScan?.call(folderPath, createPlaylistNamed) ??
        const Stream.empty();
  }

  @override
  Future<Result<String>> importFile(String path) {
    imported.add(path);
    return onImport?.call(path) ??
        Future.value(
          const Err(Failure(FailureKind.unknown, 'importFile not faked')),
        );
  }

  @override
  Future<void> markMissing(String trackId) async {}
}

/// An in-memory app: database, repositories, a player on a fake backend and a
/// fake scanner, ready to be wired into a [ProviderScope].
class UiHarness {
  UiHarness._(this.db, this.stamp, this.backend)
    : player = PlayerService(backend, _FileResolver());

  final AppDatabase db;
  final SyncStamp stamp;
  late final LibraryRepository repo = LibraryRepository(db, stamp);
  late final SearchRepository search = SearchRepository(db);
  final FakeAudioBackend backend;
  // Created eagerly: its command queue must start on the real clock, or
  // dispose() would wait on a microtask that the fake test clock never runs.
  final PlayerService player;
  final FakeScanner scanner = FakeScanner();

  /// Replaced per test to fake the native dialogs.
  Future<String?> Function() folderPicker = () async => null;
  Future<String?> Function() filePicker = () async => null;
  Future<bool> Function() mediaAccess = () async => true;

  /// Whether Locate picks a folder (Android) instead of a single file.
  bool locateByFolder = false;

  static Future<UiHarness> create() async {
    final db = testDb();
    return UiHarness._(db, await SyncStamp.load(db), FakeAudioBackend());
  }

  Future<void> dispose() async {
    // Not awaited: a command started on the fake test clock can still be
    // queued in the player, and dispose() waits for the queue to drain.
    unawaited(player.dispose());
    await db.close();
  }

  List<Override> get overrides => [
    libraryRepositoryProvider.overrideWithValue(repo),
    searchRepositoryProvider.overrideWithValue(search),
    libraryScannerProvider.overrideWithValue(scanner),
    playerServiceProvider.overrideWithValue(player),
    folderPickerProvider.overrideWithValue(() => folderPicker()),
    audioFilePickerProvider.overrideWithValue(() => filePicker()),
    mediaAccessProvider.overrideWithValue(() => mediaAccess()),
    locateByFolderProvider.overrideWithValue(locateByFolder),
  ];

  /// An app showing [routes], starting at [initialLocation].
  Widget app({required String initialLocation, required List<GoRoute> routes}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        routerConfig: GoRouter(
          initialLocation: initialLocation,
          routes: routes,
        ),
      ),
    );
  }

  Future<void> addTrack(
    String id, {
    String? title,
    String artist = 'Artist',
    int durationMs = 200000,
    bool missing = false,
  }) async {
    await db
        .into(db.tracks)
        .insert(
          trackRow(
            id: id,
            title: title ?? 'Song $id',
            artist: artist,
            durationMs: durationMs,
          ),
        );
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: id,
            path: '/music/$id.mp3',
            state: missing ? 'missing' : 'done',
            bytes: 1000,
            mtimeMs: 1,
          ),
        );
  }

  /// A playlist with [trackIds] (already in the db), returning its id.
  Future<String> addPlaylist(String name, List<String> trackIds) async {
    final id = (await repo.createPlaylist(name) as Ok<String>).value;
    await repo.addTracks(id, trackIds);
    return id;
  }

  Future<List<String>> orderOf(String playlistId) async => [
    for (final e in await repo.watchPlaylistTracks(playlistId).first)
      e.track.id,
  ];
}

/// Lets frames, animations and real-clock work (database queries, the
/// player's command queue) finish. The widget tester's clock is fake, so
/// `pumpAndSettle` alone does not wait for those.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await flush(tester);
  await tester.pumpAndSettle();
}

/// Like [settle] but without waiting for animations to end (use it while an
/// endless one, such as an indeterminate progress bar, is on screen).
///
/// Work started on the fake clock and continued on the real one (and back)
/// needs several turns of each to run to its end.
Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Runs [body] on the real clock (the tester's own clock is fake).
Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

/// Like [testWidgets], then unmounts the app so drift's stream-cancel timers
/// fire before the framework checks for pending timers.
void uiTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    // Commands still queued in the player must finish before it is disposed.
    await flush(tester);
  });
}
