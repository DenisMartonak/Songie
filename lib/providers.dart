import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart'
    show ImageProvider, NetworkImage, ResizeImage, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'account/account_service.dart';
import 'bug_report/bug_report.dart';
import 'bug_report/bug_report_sender.dart';
import 'core/app_version.dart';
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
import 'library/saved_artists_repository.dart';
import 'library/search_repository.dart';
import 'library/favorites.dart';
import 'library/yt_tracks.dart';
import 'lyrics/lyrics_service.dart';
import 'player/player_inputs.dart';
import 'player/player_service.dart';
import 'player/radio_controller.dart';
import 'player/runtime_prompter.dart';
import 'player/eq_presets.dart';
import 'player/equalizer.dart';
import 'remote/device_name.dart';
import 'remote/player_view.dart';
import 'remote/remote_channel.dart';
import 'remote/remote_controller.dart';
import 'remote/remote_host.dart';
import 'remote/remote_protocol.dart';
import 'friends/activity_backend.dart';
import 'friends/activity_publisher.dart';
import 'friends/friends_backend.dart';
import 'friends/friends_service.dart';
import 'playlists/playlist_sharing.dart';
import 'playlists/sharing_backend.dart';
import 'room/room_backend.dart';
import 'room/room_channel.dart';
import 'room/room_service.dart';
import 'room/room_songs.dart';
import 'stats/stats_models.dart';
import 'stats/stats_repository.dart';
import 'theme/app_theme.dart';
import 'theme/cover_palette.dart';
import 'theme/font_service.dart';
import 'theme/image_palette.dart';
import 'theme/theme_repository.dart';
import 'sync/cloud/cloud_sync.dart';
import 'sync/cloud/sync_status.dart';
import 'theme/theme_service.dart';
import 'theme/theme_spec.dart';
import 'ui/shell/window_controls.dart';
import 'update/release.dart';
import 'update/update_checker.dart';
import 'update/update_controller.dart';
import 'update/update_notifications.dart';
import 'update/update_downloader.dart';
import 'youtube/deno_installer.dart';
import 'youtube/js_runtime.dart';
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

/// A rising count each time synced covers arrived on this device
/// ([CloudFiles.artArrivals]); [Artwork] reloads on it.
final artArrivalsProvider = StreamProvider<int>((ref) => const Stream.empty());

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
final resolvedFontFamilyProvider = Provider<String>((ref) {
  // Asks again when a font is registered later (its file arrived by sync).
  ref.watch(fontRegistrationsProvider);
  return ref
      .watch(fontServiceProvider)
      .resolveFamily(ref.watch(themeSpecProvider));
});

/// How many imported fonts were registered since start (see
/// `FontService.registrations`).
final fontRegistrationsProvider = StreamProvider<int>(
  (ref) => ref.watch(fontServiceProvider).registrations,
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

/// The engine's equalizer; none until `main.dart` wires the real one.
final equalizerProvider = Provider<Equalizer>((ref) => const NoEqualizer());

/// The chosen equalizer preset; picking one stores and applies it.
final eqPresetProvider = NotifierProvider<EqPresetNotifier, EqPreset>(
  EqPresetNotifier.new,
);

/// The stored preset name; no value (Off) where there is no settings store.
final _storedEqPresetProvider = StreamProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchString(kEqPreset),
);

class EqPresetNotifier extends Notifier<EqPreset> {
  @override
  EqPreset build() =>
      eqPresetFromName(ref.watch(_storedEqPresetProvider).value);

  Future<void> select(EqPreset p) async {
    state = p;
    await ref.read(settingsRepositoryProvider).setString(kEqPreset, p.name);
    await ref.read(equalizerProvider).apply(p);
  }
}

/// Stars and un-stars songs (the built-in Favorites playlist).
final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => _unwired('favoritesRepositoryProvider'),
);

/// The ids of the songs in Favorites; every star watches it.
final favoriteIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(favoritesRepositoryProvider).watchIds(),
);

/// Finds yt-dlp's JavaScript runtime (age-restricted songs).
final jsRuntimeFinderProvider = Provider<JsRuntimeFinder>(
  (ref) => _unwired('jsRuntimeFinderProvider'),
);

/// The runtime yt-dlp would use now; refreshed after an install or removal.
final jsRuntimeProvider = FutureProvider.autoDispose<JsRuntime?>(
  (ref) => ref.watch(jsRuntimeFinderProvider).find(),
);

/// Installs Deno as that runtime; desktop only, null on Android.
final denoInstallerProvider = Provider<DenoInstaller?>((ref) => null);

/// Lets the player ask the user to install the runtime; the desktop shell
/// answers with a dialog.
final runtimePrompterProvider = Provider<RuntimePrompter>(
  (ref) => RuntimePrompter(),
);

final ytImportServiceProvider = Provider<YtImportService>(
  (ref) => _unwired('ytImportServiceProvider'),
);

/// Accounts (Supabase); made in `main()`.
final accountServiceProvider = Provider<AccountService>(
  (ref) => _unwired('accountServiceProvider'),
);

/// The account state, starting with the current one.
final accountStateProvider = StreamProvider<AccountState>(
  (ref) => ref.watch(accountServiceProvider).states,
);

/// Cloud sync with the signed-in account; made once in `main()`.
final cloudSyncProvider = Provider<CloudSync>(
  (ref) => _unwired('cloudSyncProvider'),
);

/// Starts cloud sync when an account signs in and stops it when it signs
/// out. `main()` listens to it once (a read alone would leave it paused); it
/// lives as long as the app.
final cloudSyncFollowerProvider = Provider<void>((ref) {
  final sync = ref.watch(cloudSyncProvider);
  ref.listen(accountStateProvider, (_, next) {
    switch (next.value) {
      case SignedIn(:final profile):
        unawaited(sync.start(profile.id));
      case SignedOut():
        unawaited(sync.stop());
      case null:
    }
  }, fireImmediately: true);
});

/// Cloud sync's state, for the profile page.
final cloudSyncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(cloudSyncProvider).status,
);

// --- Remote control --------------------------------------------------------

/// Makes the `remote:<user id>` channel for a signed-in account; overridden
/// in `main()`.
final remoteChannelProvider = Provider<RemoteChannel Function(String userId)>(
  (ref) => _unwired('remoteChannelProvider'),
);

/// The name other devices see for this one.
final remoteDeviceNameProvider = FutureProvider<String>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return remoteDeviceName(
    storedName: () => settings.getString(kDeviceName),
    isAndroid: ref.watch(isAndroidProvider),
    readDevice: ref.watch(deviceSummaryProvider),
    hostname: Platform.localHostname,
  );
});

/// The signed-in account's id; null signed out (or while it loads).
final _remoteUserIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(accountStateProvider).value) {
    SignedIn(:final profile) => profile.id,
    _ => null,
  },
);

/// One account's remote control: the channel, this device's host and the
/// controller. Made on sign-in; disposed on sign-out or an account change,
/// which leaves the channel and ends any link.
class _RemoteSession {
  _RemoteSession({
    required this.channel,
    required this.deviceId,
    required PlayerService player,
    required Future<Map<String, Track>> Function(List<String> ids) lookup,
    required this._inRoom,
  }) : _player = player,
       _lookup = lookup,
       controller = RemoteController(
         channel: channel,
         deviceId: deviceId,
         lookup: lookup,
       ) {
    _wasPlaying = player.state.playing;
    _playerSub = player.states.listen(_onPlayer);
  }

  final RemoteChannel channel;
  final String deviceId;
  final RemoteController controller;
  final PlayerService _player;
  final Future<Map<String, Track>> Function(List<String> ids) _lookup;
  final bool Function() _inRoom;
  late final StreamSubscription<PlayerState> _playerSub;
  late bool _wasPlaying;
  RemoteHost? _host;
  bool _disposed = false;

  /// P3: local playback starting (anything but the remote view's own
  /// controls, which never touch this player) ends the remote view.
  void _onPlayer(PlayerState s) {
    final started = s.playing && !_wasPlaying;
    _wasPlaying = s.playing;
    if (started && controller.link != null) controller.deselect();
  }

  /// Joins the channel as [name].
  Future<void> start(String name) async {
    if (_disposed || _host != null) return;
    final host = _host = RemoteHost(
      channel: channel,
      player: _player,
      presence: (s) => RemotePresence(
        deviceId: deviceId,
        name: name,
        platform: Platform.operatingSystem,
        appVersion: appVersion,
        playing: s.playing,
        title: s.current?.title,
        inRoom: _inRoom(),
      ),
      lookup: _lookup,
    );
    await host.start();
  }

  /// A room started or ended on this device: a room takes no remote
  /// control, so any link ends, and the presence says so.
  void roomChanged(bool inRoom) {
    if (_disposed) return;
    if (inRoom) controller.deselect();
    final host = _host;
    if (host != null) unawaited(host.refreshPresence());
  }

  void dispose() {
    _disposed = true;
    unawaited(_playerSub.cancel());
    controller.deselect(RemoteEndReason.signedOut);
    controller.dispose();
    final host = _host;
    if (host != null) unawaited(host.stop());
  }
}

final _remoteSessionProvider = Provider<_RemoteSession?>((ref) {
  final userId = ref.watch(_remoteUserIdProvider);
  if (userId == null) return null;
  final library = ref.watch(libraryRepositoryProvider);
  final session = _RemoteSession(
    channel: ref.watch(remoteChannelProvider)(userId),
    deviceId: ref.watch(deviceIdProvider),
    player: ref.watch(playerServiceProvider),
    lookup: library.tracksByIds,
    inRoom: () => ref.read(roomServiceProvider).status is! RoomIdle,
  );
  ref.onDispose(session.dispose);
  ref.listen(roomStatusProvider, (_, next) {
    final status = next.value;
    if (status != null) session.roomChanged(status is! RoomIdle);
  });
  unawaited(
    ref.read(remoteDeviceNameProvider.future).then(session.start).catchError((
      Object e,
      StackTrace s,
    ) {
      AppLog.w('remote: starting the host failed', e, s);
    }),
  );
  return session;
});

/// Joins the remote channel when an account signs in (this device's host and
/// controller) and leaves it on sign-out or an account change. `main()`
/// listens to it once (a read alone would leave it paused); it lives as long
/// as the app.
final remoteHostFollowerProvider = Provider<void>((ref) {
  // A listener, not just a read, so the session follows the account even
  // while nothing else watches it.
  ref.listen(_remoteSessionProvider, (_, _) {}, fireImmediately: true);
  // Also keeps the online devices loaded, so the song and playlist menus
  // (opened on any screen, with no devices button mounted) can offer Play on.
  ref.listen(remoteDevicesProvider, (_, _) {}, fireImmediately: true);
});

/// Controls another device; null signed out.
final remoteControllerProvider = Provider<RemoteController?>(
  (ref) => ref.watch(_remoteSessionProvider)?.controller,
);

/// The other devices online on the account (this one excluded), incompatible
/// ones included; empty signed out.
final remoteDevicesProvider = StreamProvider<List<RemotePresence>>((ref) {
  final session = ref.watch(_remoteSessionProvider);
  if (session == null) return Stream.value(const []);
  final channel = session.channel;
  List<RemotePresence> others(List<RemotePresence> all) => [
    for (final p in all)
      if (p.deviceId != session.deviceId) p,
  ];
  return Stream<List<RemotePresence>>.multi((c) {
    final sub = channel.presences.listen(
      (all) => c.addSync(others(all)),
      onError: c.addErrorSync,
      onDone: c.closeSync,
    );
    c.addSync(others(channel.present));
    c.onCancel = sub.cancel;
  });
});

/// The device being controlled and how the link stands; null for This
/// device. Consumers switch on this, not only on the view's states.
final remoteLinkProvider = StreamProvider<RemoteLink?>((ref) {
  final controller = ref.watch(remoteControllerProvider);
  if (controller == null) return Stream.value(null);
  return Stream<RemoteLink?>.multi((c) {
    final sub = controller.links.listen(
      c.addSync,
      onError: c.addErrorSync,
      onDone: c.closeSync,
    );
    c.addSync(controller.link);
    c.onCancel = sub.cancel;
  });
});

/// Each link that ended, with its device (for the island). A stream, not a
/// StreamProvider, so the same device ending twice the same way is told
/// twice. Signed out it never emits.
final remoteEndedProvider = Provider<Stream<(RemotePresence, RemoteEndReason)>>(
  (ref) {
    final controller = ref.watch(remoteControllerProvider);
    if (controller == null) return const Stream.empty();
    return Stream<(RemotePresence, RemoteEndReason)>.multi((c) {
      // The link is already null when its end is reported: remember the
      // last device linked.
      var device = controller.link?.device;
      final links = controller.links.listen((l) {
        if (l != null) device = l.device;
      });
      final ended = controller.ended.listen((reason) {
        final d = device;
        if (d != null) c.addSync((d, reason));
      }, onDone: c.closeSync);
      c.onCancel = () async {
        await links.cancel();
        await ended.cancel();
      };
    });
  },
);

/// What the player UI shows and commands: the device being controlled while
/// a link exists, else this device's player.
final playerViewProvider = Provider<PlayerView>((ref) {
  final player = ref.watch(playerServiceProvider);
  final guesting = ref.watch(
    roomStatusProvider.select((s) => s.value is RoomGuesting),
  );
  if (guesting) {
    final guest = ref.watch(roomServiceProvider).guestView;
    if (guest != null) return guest;
  }
  final controller = ref.watch(remoteControllerProvider);
  final linked = ref.watch(remoteLinkProvider.select((l) => l.value != null));
  if (controller != null && linked) {
    final sync = ref.watch(cloudSyncProvider);
    return RemotePlayerView(controller, sync.syncNow);
  }
  return LocalPlayerView(player);
});

/// The view's state, starting with its current value (as
/// [playerStateProvider]).
final playerViewStateProvider = StreamProvider<PlayerState>((ref) {
  final view = ref.watch(playerViewProvider);
  return Stream<PlayerState>.multi((c) {
    final sub = view.states.listen(
      c.addSync,
      onError: c.addErrorSync,
      onDone: c.closeSync,
    );
    c.addSync(view.state);
    c.onCancel = sub.cancel;
  });
});

// --- Listen together -------------------------------------------------------

/// Where this device's own playback inputs go (shortcuts, media buttons,
/// song taps, radio): the player, or the room while this device is a guest,
/// as its role allows. `main()` overrides it with the instance the system
/// media controls use.
final playerInputsProvider = Provider<PlayerInputs>(
  (ref) => PlayerInputs(
    ref.watch(playerServiceProvider),
    room: () => ref.read(roomServiceProvider).guestView,
  ),
);

/// Friendships and profiles behind Supabase (lazy like
/// [roomBackendProvider]).
final friendsBackendProvider = Provider<FriendsBackend>(
  (ref) => SupabaseFriendsBackend(() => Supabase.instance.client),
);

/// The activity rows behind Supabase (lazy like [friendsBackendProvider]).
final activityBackendProvider = Provider<ActivityBackend>(
  (ref) => SupabaseActivityBackend(() => Supabase.instance.client),
);

/// Publishes what this account plays now and its top 10 for friends, while
/// signed in. `main()` listens to it once so it follows the account.
final activityPublisherProvider = Provider<ActivityPublisher>((ref) {
  final player = ref.watch(playerServiceProvider);
  final room = ref.watch(roomServiceProvider);
  final stats = ref.watch(statsRepositoryProvider);
  final publisher = ActivityPublisher(
    backend: ref.watch(activityBackendProvider),
    states: player.states,
    current: () => player.state,
    roomCode: () => switch (room.status) {
      RoomHosting(:final code) => code,
      _ => null,
    },
    roomChanges: room.statuses,
    top: () async {
      final month = await stats.period(StatsPeriod.month);
      return TopSummary(
        artists: [
          for (final a in month.topArtists.take(TopSummary.most)) a.name,
        ],
        songs: [
          for (final song in month.topSongs.take(TopSummary.most))
            NowPlaying(title: song.title, artist: song.displayArtist),
        ],
      );
    },
  );
  ref.onDispose(publisher.dispose);
  // Cleared while the session still works: after it, the server refuses.
  ref.onDispose(
    ref.read(accountServiceProvider).addBeforeLogOut(publisher.signedOut),
  );
  if (ref.read(_remoteUserIdProvider) != null) {
    unawaited(publisher.signedIn());
  }
  ref.listen(_remoteUserIdProvider, (previous, next) {
    if (previous != null && previous != next) unawaited(publisher.signedOut());
    if (next != null && previous != next) unawaited(publisher.signedIn());
  });
  return publisher;
});

/// Shared playlists behind Supabase (lazy like [friendsBackendProvider]).
final sharingBackendProvider = Provider<SharingBackend>(
  (ref) => SupabaseSharingBackend(() => Supabase.instance.client),
);

/// Playlist sharing: keeps this account's shares and follows current while
/// signed in. `main()` listens to it once so it follows the account.
final playlistSharingProvider = Provider<PlaylistSharing>((ref) {
  // Shares and follows wait for sync's first pull since the app started:
  // until then a shared or followed playlist here may be an old copy. Sync
  // is looked at only once they start (signed in).
  final since = DateTime.now();
  final pulled = Completer<void>();
  StreamSubscription<SyncStatus>? statusSub;
  void check(SyncStatus status) {
    if (!pulled.isCompleted && syncPulledSince(status, since)) {
      pulled.complete();
    }
  }

  Future<void> ready() {
    if (statusSub == null && !pulled.isCompleted) {
      final sync = ref.read(cloudSyncProvider);
      check(sync.current);
      statusSub = sync.status.listen(check);
    }
    return pulled.future;
  }

  ref.onDispose(() {
    unawaited(statusSub?.cancel());
    if (!pulled.isCompleted) pulled.complete();
  });
  final sharing = PlaylistSharing(
    backend: ref.watch(sharingBackendProvider),
    library: ref.watch(libraryRepositoryProvider),
    tracksFor: (songs) => tracksForSongs(songs, ref.read(ytTrackStoreProvider)),
    ready: ready,
  );
  ref.onDispose(sharing.dispose);
  if (ref.read(_remoteUserIdProvider) != null) sharing.signedIn();
  ref.listen(_remoteUserIdProvider, (previous, next) {
    if (previous != next) sharing.signedOut();
    if (next != null) sharing.signedIn();
  });
  return sharing;
});

/// The signed-in account's friends and requests: loads on sign-in, every 5
/// minutes and after each change; cleared on sign-out.
final friendsServiceProvider = Provider<FriendsService>((ref) {
  final service = FriendsService(
    ref.watch(friendsBackendProvider),
    activity: ref.watch(activityBackendProvider),
  );
  ref.onDispose(service.dispose);
  void follow(String? userId) {
    if (userId == null) {
      service.signedOut();
    } else {
      unawaited(service.signedIn(userId));
    }
  }

  follow(ref.read(_remoteUserIdProvider));
  ref.listen(_remoteUserIdProvider, (_, next) => follow(next));
  return service;
});

/// [FriendsService.state] as it changes.
final friendsStateProvider = StreamProvider<FriendsState>(
  (ref) => ref.watch(friendsServiceProvider).states,
);

/// The room tables behind Supabase. Not overridden in `main()`: the client
/// is read only when a call is made, so a signed-out app never touches
/// Supabase, and tests that never open a room need no wiring.
final roomBackendProvider = Provider<RoomBackend>(
  (ref) => SupabaseRoomBackend(() => Supabase.instance.client),
);

/// Makes the `room:<room id>` channel (lazy like [roomBackendProvider]).
final roomChannelProvider = Provider<RoomChannel Function(String roomId)>(
  (ref) =>
      (roomId) => SupabaseRoomChannel(() => Supabase.instance.client, roomId),
);

/// This device's one room session, hosting or guesting. Stops when the
/// account signs out or changes.
final roomServiceProvider = Provider<RoomService>((ref) {
  final service = RoomService(
    backend: ref.watch(roomBackendProvider),
    channelFor: ref.watch(roomChannelProvider),
    player: ref.watch(playerServiceProvider),
    tracksFor: (songs) => tracksForSongs(songs, ref.read(ytTrackStoreProvider)),
    deviceId: ref.watch(deviceIdProvider),
    platform: Platform.operatingSystem,
  );
  ref.listen(_remoteUserIdProvider, (previous, next) {
    if (previous != null && previous != next) unawaited(service.signedOut());
  });
  ref.onDispose(service.dispose);
  return service;
});

/// How the room session stands, starting with its current value.
final roomStatusProvider = StreamProvider<RoomStatus>((ref) {
  final service = ref.watch(roomServiceProvider);
  return Stream<RoomStatus>.multi((c) {
    final sub = service.statuses.listen(
      c.addSync,
      onError: c.addErrorSync,
      onDone: c.closeSync,
    );
    c.addSync(service.status);
    c.onCancel = sub.cancel;
  });
});

/// Whether this device is in a room, hosting or guesting. While it is, it
/// controls no other device (no picking one, no Play on).
final inRoomProvider = Provider<bool>(
  (ref) => ref.watch(
    roomStatusProvider.select(
      (s) => switch (s.value) {
        RoomHosting() || RoomGuesting() => true,
        _ => false,
      },
    ),
  ),
);

/// What the room tells the user (for islands).
final roomNoticesProvider = Provider<Stream<RoomNotice>>(
  (ref) => ref.watch(roomServiceProvider).notices,
);

/// A room code waiting for the user to join (from a link, see Task 6).
class RoomInvite extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String code) => state = code;

  void clear() => state = null;
}

final roomInviteProvider = NotifierProvider<RoomInvite, String?>(
  RoomInvite.new,
);

/// A shared playlist's code from an opened link, until the app has offered
/// to follow or copy it.
class PlaylistInvite extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String code) => state = code;

  void clear() => state = null;
}

final playlistInviteProvider = NotifierProvider<PlaylistInvite, String?>(
  PlaylistInvite.new,
);

/// Starts controlling [device]: pauses this device's playback first, so the
/// two don't play at once.
Future<void> selectRemote(
  PlayerService local,
  RemoteController controller,
  RemotePresence device,
) async {
  try {
    await local.pause();
  } on Object catch (e, s) {
    AppLog.w('remote: pausing before select failed', e, s);
  }
  await controller.select(device);
}

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
    inputs: ref.watch(playerInputsProvider),
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

/// Platform flags for platform-specific settings; tests override them.
final isAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);
final isLinuxProvider = Provider<bool>((ref) => Platform.isLinux);
final isWindowsProvider = Provider<bool>((ref) => Platform.isWindows);

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

/// The platform whose release file this build installs; null where Songies
/// has no updates.
final updatePlatformProvider = Provider<UpdatePlatform?>((ref) {
  if (ref.watch(isAndroidProvider)) return UpdatePlatform.android;
  if (ref.watch(isWindowsProvider)) return UpdatePlatform.windows;
  if (ref.watch(isLinuxProvider)) return UpdatePlatform.linux;
  return null;
});

/// Checks GitHub for a newer release; null where Songies has no updates.
final updateCheckerProvider = Provider<UpdateChecker?>((ref) {
  final platform = ref.watch(updatePlatformProvider);
  final current = AppVersion.tryParse(appVersion);
  if (platform == null || current == null) return null;
  return UpdateChecker(
    settings: ref.watch(settingsRepositoryProvider),
    current: current,
    platform: platform,
  );
});

/// Downloads and verifies update files into the app's `updates` folder.
final updateDownloaderProvider = Provider<UpdateDownloader>(
  (ref) => UpdateDownloader(dir: ref.watch(appPathsProvider).updates),
);

/// The Android update notification's app side; null off Android.
final updateNotificationsProvider = Provider<UpdateNotifications?>(
  (ref) => ref.watch(isAndroidProvider)
      ? ChannelUpdateNotifications(
          settings: ref.watch(settingsRepositoryProvider),
        )
      : null,
);

/// The in-app update flow behind the update dialog and Settings → About.
final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

// --- Bug reports -----------------------------------------------------------

/// Whether this build can send bug reports; a provider so tests can fake it.
final bugReportsBuiltProvider = Provider<bool>((ref) => bugReportsBuilt());

/// The one sender of the app run, so its one-a-minute limit holds.
final bugReportSenderProvider = Provider<BugReportSender>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return BugReportSender(client: client);
});

/// Reads the device for a bug report; replaceable in tests.
final deviceSummaryProvider = Provider<Future<DeviceSummary> Function()>(
  (ref) => readDeviceSummary,
);

/// Artists the user saved.
final savedArtistsRepositoryProvider = Provider<SavedArtistsRepository>(
  (ref) => SavedArtistsRepository(
    ref.watch(databaseProvider),
    ref.watch(syncStampProvider),
  ),
);

/// Saved artists, newest first.
final savedArtistsProvider = StreamProvider<List<SavedArtist>>(
  (ref) => ref.watch(savedArtistsRepositoryProvider).watchAll(),
);
