import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../account/account_service.dart';
import '../../library/favorites.dart';
import '../../core/log.dart';
import '../../core/result.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../remote/remote_protocol.dart';
import '../../room/room_protocol.dart' show RoomOp, roleAllows;
import '../../room/room_service.dart' show RoomIdle;
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../downloads/download_status_line.dart';
import '../downloads/download_toggle.dart';
import '../downloads/track_download_icon.dart';
import '../library/add_folder_flow.dart' show folderPickFailureMessage;
import '../library/add_songs_sheet.dart';
import '../library/pickers.dart';
import '../motion/equalizer_bars.dart';
import '../motion/pressable.dart';
import '../motion/shimmer.dart';
import '../remote/play_on.dart';
import '../room/room_button.dart' show roomGuestRoleProvider;
import '../room/room_panel.dart' show showRoomPanel;
import '../playlists/share_playlist_sheet.dart';
import '../widgets/artist_link.dart';
import '../widgets/artwork.dart';
import '../widgets/name_dialog.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../widgets/song_menu.dart';
import '../widgets/favorite_star.dart';
import '../widgets/playlist_art.dart';
import 'hero_backdrop.dart';
import 'yt_playlist_actions.dart';

const double _rowHeight = 64;

/// The track-number column, where the playing row shows its equalizer.
const double _numberWidth = 28;

/// "N songs · H h M min", e.g. "3 songs · 0 h 10 min".
String playlistSummaryText(int count, int durationMs) {
  final minutes = durationMs ~/ Duration.millisecondsPerMinute;
  final songs = count == 1 ? '1 song' : '$count songs';
  return '$songs · ${minutes ~/ 60} h ${minutes % 60} min';
}

/// "m:ss" for a track length.
String trackDurationText(int durationMs) {
  final seconds = durationMs ~/ Duration.millisecondsPerSecond;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// One playlist: hero, actions and the reorderable track list.
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  /// The list as the user just left it (after a drop or a swipe), shown until
  /// the database stream catches up so rows do not jump back for a moment.
  List<PlaylistTrack>? _pending;

  String get _id => widget.id;

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  /// Kept to clear this page's pending import when it goes away.
  late final PendingImports _pendingImports = ref.read(
    pendingImportsProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    _pendingImports; // read now: `ref` is unusable in dispose
    // Entries that were already loaded when the page opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _settlePendingImport(ref.read(playlistTracksProvider(_id)));
    });
  }

  @override
  void dispose() {
    // After the frame: providers may not change while the tree is locked.
    final id = _id;
    final pending = _pendingImports;
    Future.microtask(() => pending.remove(id));
    super.dispose();
  }

  /// A pending import is over once the entries stream answers with data
  /// (even none: an import whose videos were all unavailable) or an error.
  /// The import itself has finished before its page opens, so this answer
  /// is its result.
  void _settlePendingImport(AsyncValue<List<PlaylistTrack>> entries) {
    if (entries.hasError || entries.hasValue) _pendingImports.remove(_id);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playlistTracksProvider(_id), (_, next) {
      if (_pending != null) setState(() => _pending = null);
      _settlePendingImport(next);
    });
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final playlists = ref.watch(playlistsProvider);
    final streamed = ref.watch(playlistTracksProvider(_id));
    final importing = ref.watch(
      pendingImportsProvider.select((ids) => ids.contains(_id)),
    );

    final summary = playlists.value
        ?.where((p) => p.id == _id)
        .cast<PlaylistSummary?>()
        .firstOrNull;
    if (summary == null) {
      // A just-imported playlist may not have reached the list yet (until
      // its entries have loaded).
      final waiting = importing && !streamed.hasValue && !streamed.hasError;
      return playlists.hasValue && !waiting
          ? _NotFound(onBack: () => context.go('/library'))
          : const Center(child: CircularProgressIndicator());
    }
    final rows = _pending ?? streamed.value;
    final failed = rows == null && streamed.hasError;
    final skeleton = !failed && (rows == null || (importing && rows.isEmpty));

    final (current, playing) = ref.watch(
      playerViewStateProvider.select((s) {
        final state = s.value;
        return state?.sourcePlaylistId == _id
            ? (state?.current?.id, state?.playing ?? false)
            : (null, false);
      }),
    );
    final insets = MediaQuery.paddingOf(context);
    // The hero grows with the text so a two-line title always fits.
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final list = rows ?? const <PlaylistTrack>[];
    final totalMs = list.fold<int>(0, (sum, r) => sum + r.track.durationMs);
    final dominant = ref
        .watch(artPaletteProvider(summary.coverRef))
        .value
        ?.dominant;
    // A room's guest queues songs only as its role allows, and never its
    // local files.
    final guestRole = ref.watch(roomGuestRoleProvider);
    bool canQueue(PlaylistTrack row) =>
        guestRole == null ||
        (roleAllows(guestRole, RoomOp.addNext) && row.track.source != 'local');
    final signedIn = ref.watch(accountStateProvider).value is SignedIn;
    final listenTogether =
        list.isNotEmpty &&
        signedIn &&
        ref.watch(roomStatusProvider.select((s) => s.value is RoomIdle));
    // Playlist sharing: followed playlists are read-only.
    final playlistRow = ref.watch(playlistRowProvider(_id)).value;
    final followed = playlistRow?.isFollowed ?? false;
    final ended = playlistRow?.followEnded ?? false;
    final owner = playlistRow?.followOwner ?? '';

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeroDelegate(
            insets: insets,
            coverRowHeight: _coverRowPadding + max(_coverSize, 104 * textScale),
            summary: summary,
            summaryText: rows == null
                ? ''
                : playlistSummaryText(rows.length, totalMs),
            // Without a cover palette, the soft accent wash of the mockup.
            heroColor: playlistHeroTop(
              dominant ??
                  Color.alphaBlend(
                    colors.accent.withValues(alpha: 0.28),
                    colors.background,
                  ),
              colors,
            ),
            canGoBack: Navigator.canPop(context),
            canPlay: list.isNotEmpty,
            onPlay: () => _play(list, shuffle: false),
            onShuffle: () => _play(list, shuffle: true),
            onMenu: (action) => _onMenu(action, summary),
            listenTogether: listenTogether,
            devices: playOnDevices(ref.watch(remoteDevicesProvider).value),
            // In a room this device controls no other one.
            playOn: !ref.watch(inRoomProvider),
            onSendTo: _sendTo,
            followed: followed,
            canShare:
                signedIn && !followed && summary.id != kFavoritesPlaylistId,
          ),
        ),
        if (followed || ended)
          _sideSafe(
            SliverToBoxAdapter(
              child: _SharingLine(
                text: followed
                    ? 'Following · by $owner'
                    : '$owner stopped sharing this',
                following: followed,
              ),
            ),
          ),
        if (summary.source == 'yt' || list.any((r) => r.track.source == 'yt'))
          _sideSafe(
            SliverToBoxAdapter(
              child: _YtActions(
                playlistId: summary.id,
                imported: summary.source == 'yt',
              ),
            ),
          ),
        if (failed)
          _sideSafe(const SliverToBoxAdapter(child: _LoadFailed()))
        else if (skeleton)
          _sideSafe(const SliverToBoxAdapter(child: _SkeletonRows()))
        else if (list.isEmpty)
          _sideSafe(
            SliverToBoxAdapter(
              child: _EmptyPlaylist(onAdd: followed ? null : _addSongs),
            ),
          )
        else
          _sideSafe(
            SliverReorderableList(
              itemCount: list.length,
              onReorderItem: (from, to) => _reorder(list, from, to),
              proxyDecorator: _liftWhileDragged,
              itemBuilder: (context, i) {
                final row = list[i];
                return Dismissible(
                  key: ValueKey(row.entryId),
                  // A followed playlist's rows only queue (no removing).
                  direction: followed
                      ? (canQueue(row)
                            ? DismissDirection.startToEnd
                            : DismissDirection.none)
                      : canQueue(row)
                      ? DismissDirection.horizontal
                      : DismissDirection.endToStart,
                  // Swiping right queues the song and springs back; swiping
                  // left removes it.
                  background: const _SwipeBackground.queue(),
                  secondaryBackground: const _SwipeBackground.remove(),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.endToStart) return true;
                    _queue(row);
                    return false;
                  },
                  onDismissed: (_) => _remove(list, i),
                  child: _TrackRow(
                    key: ValueKey('row.${row.entryId}'),
                    playlistId: _id,
                    row: row,
                    index: i,
                    current: row.track.id == current,
                    playing: playing,
                    onTap: () => _playFrom(list, i),
                    onLocate: () => _locate(row),
                    onRemove: followed ? null : () => _removeEntry(row.entryId),
                    reorderable: !followed,
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: insets.bottom + 16)),
      ],
    );
  }

  /// Keeps [sliver] clear of landscape side insets (cutouts).
  static Widget _sideSafe(Widget sliver) =>
      SliverSafeArea(top: false, bottom: false, sliver: sliver);

  static Widget _liftWhileDragged(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Material(
      elevation: 6 * Curves.easeInOut.transform(animation.value),
      type: MaterialType.transparency,
      child: child,
    ),
    child: child,
  );

  // --- playback -------------------------------------------------------------

  Future<void> _playFrom(List<PlaylistTrack> rows, int index) {
    // Also for a row flagged missing: the file may be back, and the player
    // skips and reports it if it is not.
    return ref
        .read(playerViewProvider)
        .playTracks(
          [for (final r in rows) r.track],
          startIndex: index,
          sourcePlaylistId: _id,
        );
  }

  Future<void> _play(List<PlaylistTrack> rows, {required bool shuffle}) {
    final player = ref.read(playerViewProvider);
    player.setShuffle(shuffle);
    return player.playTracks(
      [for (final r in rows) r.track],
      // Shuffle starts anywhere, not always on the first song.
      startIndex: shuffle ? Random().nextInt(rows.length) : 0,
      sourcePlaylistId: _id,
    );
  }

  // --- editing --------------------------------------------------------------

  /// [target] is the row's new index once it has been taken out of the list.
  Future<void> _reorder(List<PlaylistTrack> rows, int from, int target) async {
    if (target == from) return;
    final moved = rows[from];
    final list = [...rows]..removeAt(from);
    final after = target > 0 ? list[target - 1].entryId : null;
    final before = target < list.length ? list[target].entryId : null;
    list.insert(target, moved);
    setState(() => _pending = list);

    final result = await _repo.moveEntry(
      moved.entryId,
      afterEntryId: after,
      beforeEntryId: before,
    );
    if (result is Err<void> && mounted) {
      setState(() => _pending = null);
      _say('Couldn\'t move that song');
    }
  }

  void _queue(PlaylistTrack row) {
    ref.read(playerViewProvider).addNext([row.track]);
    Islands.of(context).show(
      'Added to queue',
      kind: IslandKind.success,
      song: row.track,
      duration: _queuedIsland,
    );
  }

  static const Duration _queuedIsland = Duration(seconds: 2);

  Future<void> _remove(List<PlaylistTrack> rows, int index) async {
    final removed = rows[index];
    final previous = index > 0 ? rows[index - 1].entryId : null;
    final next = index < rows.length - 1 ? rows[index + 1].entryId : null;
    setState(() => _pending = [...rows]..removeAt(index));

    final islands = Islands.of(context);
    final repo = _repo;
    final result = await repo.removeEntry(removed.entryId);
    if (!mounted) return;
    if (result is Err<void>) {
      setState(() => _pending = null);
      _say('Couldn\'t remove that song');
      return;
    }
    islands.show(
      'Removed ${removed.track.title}',
      kind: IslandKind.success,
      song: removed.track,
      action: IslandAction(
        label: 'Undo',
        onPressed: () => _undoRemove(repo, removed.track.id, previous, next),
      ),
    );
  }

  /// [_remove] for the menu's Remove from this playlist: the row is looked up
  /// again, as the list may have changed while the menu was open.
  void _removeEntry(String entryId) {
    if (!mounted) return;
    final rows = _pending ?? ref.read(playlistTracksProvider(_id)).value;
    final index = rows?.indexWhere((r) => r.entryId == entryId) ?? -1;
    if (rows != null && index >= 0) _remove(rows, index);
  }

  /// Puts a removed track back between its old neighbours. The track returns
  /// as a new entry (the removed one stays a tombstone for sync).
  Future<void> _undoRemove(
    LibraryRepository repo,
    String trackId,
    String? previous,
    String? next,
  ) async {
    final added = await repo.addTracks(_id, [trackId]);
    if (added is Err<void>) {
      _say('Couldn\'t undo that');
      return;
    }
    final entries = await repo.watchPlaylistTracks(_id).first;
    final live = {for (final e in entries) e.entryId};
    final restored = entries.last.entryId; // appended last
    final after = live.contains(previous) ? previous : null;
    final before = live.contains(next) ? next : null;

    var moved = await repo.moveEntry(
      restored,
      afterEntryId: after,
      beforeEntryId: before,
    );
    if (moved is Err<void>) {
      // The neighbours were reordered meanwhile and no longer bracket a slot:
      // settle for one side of them.
      if (after != null) {
        moved = await repo.moveEntry(restored, afterEntryId: after);
      } else if (before != null) {
        moved = await repo.moveEntry(restored, beforeEntryId: before);
      }
    }
    if (moved is Err<void>) _say("Couldn't restore the song's position");
  }

  Future<void> _locate(PlaylistTrack row) {
    return ref.read(locateByFolderProvider)
        ? _locateInFolder(row)
        : _locateFile(row);
  }

  /// Desktop: pick the moved file itself.
  Future<void> _locateFile(PlaylistTrack row) async {
    final path = await ref.read(audioFilePickerProvider)();
    if (path == null || !mounted) return;
    final imported = await ref.read(libraryScannerProvider).importFile(path);
    if (!mounted) return;
    switch (imported) {
      case Err(:final failure):
        AppLog.w('Locate failed for $path: ${failure.message}');
        _say("Couldn't use that file");
      case Ok(:final value):
        // The same content is already repaired; a different file is a different
        // track, so the entry has to point at it.
        if (value == row.track.id) return;
        final swapped = await _repo.replaceEntryTrack(row.entryId, value);
        if (swapped is Err<void>) _say("Couldn't use that file");
    }
  }

  /// Android: the file picker would hand back a temporary copy, which breaks
  /// "referenced in place". Scan a folder instead; the scan repairs a missing
  /// file whose content it finds there.
  Future<void> _locateInFolder(PlaylistTrack row) async {
    final islands = Islands.of(context);
    final repo = _repo;
    final queue = ref.read(scanQueueProvider);
    final pick = await ref.read(folderPickerProvider)();
    final String folder;
    switch (pick) {
      case FolderPicked(:final path):
        folder = path;
      case FolderPickCancelled():
        return;
      case FolderPickFailed(:final error):
        islands.show(folderPickFailureMessage(error), kind: IslandKind.failure);
        return;
    }
    final name = p.basename(folder).isEmpty ? folder : p.basename(folder);
    try {
      await queue.enqueue(folder, registerFolder: false);
    } catch (_) {
      // ScanQueue has already logged the details.
      islands.show("Couldn't scan $name", kind: IslandKind.failure);
      return;
    }
    final entries = await repo.watchPlaylistTracks(_id).first;
    final stillMissing = entries.any(
      (e) => e.entryId == row.entryId && e.fileMissing,
    );
    if (stillMissing) {
      islands.show(
        "Couldn't find that song in $name",
        kind: IslandKind.failure,
      );
    }
  }

  // --- menu -----------------------------------------------------------------

  /// Play on / Add to queue on [device] for the whole playlist.
  void _sendTo(RemotePresence device, {required bool play}) {
    final rows = _pending ?? ref.read(playlistTracksProvider(_id)).value;
    if (rows == null || rows.isEmpty) return;
    // The menu closes as it is chosen, and the sync takes a while: send from
    // the container, not `ref`.
    unawaited(
      sendIdsTo(
        ProviderScope.containerOf(context),
        Islands.of(context),
        device,
        ids: [for (final r in rows) r.track.id],
        play: play,
        sourcePlaylistId: _id,
      ),
    );
  }

  Future<void> _onMenu(_MenuAction action, PlaylistSummary summary) async {
    switch (action) {
      case _MenuAction.rename:
        final name = await showPlaylistNameDialog(
          context,
          title: 'Rename playlist',
          initial: summary.name,
        );
        if (name == null) return;
        final result = await _repo.renamePlaylist(_id, name);
        if (result is Err<void>) _say("Couldn't rename the playlist");
      case _MenuAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text(
              '"${summary.name}" will be deleted. Your music files stay '
              'where they are.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final result = await _repo.deletePlaylist(_id);
        if (!mounted) return;
        if (result is Err<void>) {
          _say('Couldn\'t delete the playlist');
        } else if (Navigator.canPop(context)) {
          context.pop(); // back to the page it was opened from
        } else {
          context.go('/library');
        }
      case _MenuAction.changeCover:
        await _changeCover();
      case _MenuAction.removeCover:
        final result = await _repo.setPlaylistCover(_id, null);
        if (result is Err<void>) _say("Couldn't remove the cover");
      case _MenuAction.addSongs:
        await _addSongs();
      case _MenuAction.listenTogether:
        await _listenTogether();
      case _MenuAction.share:
        await showSharePlaylistSheet(context, _id);
      case _MenuAction.makeCopy:
        final router = GoRouter.of(context);
        final islands = Islands.of(context);
        final copy = await ref
            .read(playlistSharingProvider)
            .copy(playlistId: _id);
        islands.show('Copied to your library', kind: IslandKind.success);
        router.go('/library/playlist/$copy');
      case _MenuAction.stopFollowing:
        await ref.read(playlistSharingProvider).stopFollowing(_id);
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          context.pop();
        } else {
          context.go('/library');
        }
    }
  }

  /// Opens a room playing this playlist, and the room panel to share it.
  Future<void> _listenTogether() async {
    final account = ref.read(accountStateProvider).value;
    final rows = _pending ?? ref.read(playlistTracksProvider(_id)).value;
    if (account is! SignedIn || rows == null || rows.isEmpty) return;
    final service = ref.read(roomServiceProvider);
    if (service.status is! RoomIdle) return;
    try {
      await service.open(
        userId: account.profile.id,
        name: account.profile.username,
        avatarUrl: account.profile.avatarUrl,
        play: [for (final r in rows) r.track],
      );
    } on StateError catch (e, s) {
      // Another open or join is under way.
      AppLog.w('room: open skipped', e, s);
      return;
    }
    if (mounted && service.status is! RoomIdle) {
      await showRoomPanel(context, ref);
    }
  }

  /// Asks for a picture, stores it square in the art cache (so it syncs like
  /// song covers do) and makes it the playlist's cover.
  Future<void> _changeCover() async {
    final art = ref.read(artCacheProvider);
    final repo = _repo;
    final Uint8List? bytes;
    try {
      bytes = await ref.read(imagePickerProvider)();
    } catch (e, s) {
      AppLog.w('Picking a cover failed', e, s);
      _say("Couldn't open that picture");
      return;
    }
    if (bytes == null) return;
    final coverRef = await art.put(bytes, squareCrop: true);
    if (coverRef == null) {
      _say("Couldn't use that picture");
      return;
    }
    final result = await repo.setPlaylistCover(_id, coverRef);
    if (result is Err<void>) _say("Couldn't change the cover");
  }

  Future<void> _addSongs() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => AddSongsSheet(playlistId: _id),
  );

  void _say(String message) {
    if (!mounted) return;
    Islands.of(context).show(message, kind: IslandKind.failure);
  }
}

typedef _SendTo = void Function(RemotePresence device, {required bool play});

enum _MenuAction {
  rename,
  changeCover,
  removeCover,
  delete,
  addSongs,
  listenTogether,
  share,
  makeCopy,
  stopFollowing,
}

/// The hero's pinned top bar.
const double _barHeight = 56;

/// The hero cover's full size, and the padding around its row.
const double _coverSize = 112;
const double _coverRowPadding = 32;

/// The cover, title and summary below the bar, at the default text size.
const double _coverRowHeight = _coverRowPadding + _coverSize;

/// Shuffle and the menu, beside the Play button.
const double _actionsHeight = 56;

/// The floating Play button.
const double _playSize = 48;

/// How far the playlist scrolls before its hero has collapsed into the bar,
/// at the default text size (larger text makes the hero taller).
const double playlistHeroCollapseRange = _coverRowHeight + _actionsHeight;

/// The top colour of the playlist hero for a cover's [dominant] colour: the
/// colour itself when the theme's text and muted text read on it at 4.5:1,
/// else the nearest blend towards the background that does.
Color playlistHeroTop(Color dominant, SongiesColors colors) {
  // Muted text that fails on the background itself can't be helped here.
  final checkMuted = contrastRatio(colors.mutedText, colors.background) >= 4.5;
  bool readable(Color c) =>
      contrastRatio(colors.text, c) >= 4.5 &&
      (!checkMuted || contrastRatio(colors.mutedText, c) >= 4.5);
  for (var step = 0; step < 20; step++) {
    final c = Color.lerp(dominant, colors.background, step / 20)!;
    if (readable(c)) return c;
  }
  return colors.background;
}

/// Collapse fraction past which the title shows in the bar (and the hero's
/// own title and cover have faded away).
const double _barTitleFrom = 0.6;

/// The collapsing hero: a gradient from the cover's dominant colour, the
/// cover and title (shrinking and fading as the list scrolls), and a pinned
/// top bar that takes the title past 60 % collapse. The Play button rides
/// with the hero, then pins to the bar.
class _HeroDelegate extends SliverPersistentHeaderDelegate {
  _HeroDelegate({
    required this.insets,
    required this.coverRowHeight,
    required this.summary,
    required this.summaryText,
    required this.heroColor,
    required this.canGoBack,
    required this.canPlay,
    required this.onPlay,
    required this.onShuffle,
    required this.onMenu,
    required this.listenTogether,
    required this.devices,
    required this.playOn,
    required this.onSendTo,
    this.followed = false,
    this.canShare = false,
  });

  /// Followed from someone's share: no editing (Make a copy, Stop following).
  final bool followed;

  /// Offers Share (signed in, the user's own playlist).
  final bool canShare;

  /// The safe-area padding: the bar sits below [EdgeInsets.top], and the
  /// content keeps clear of the sides.
  final EdgeInsets insets;

  /// The cover row's height (taller with larger text).
  final double coverRowHeight;
  final PlaylistSummary summary;
  final String summaryText;
  final Color heroColor;
  final bool canGoBack;
  final bool canPlay;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final ValueChanged<_MenuAction> onMenu;

  /// The menu offers Listen together.
  final bool listenTogether;

  /// The devices the menu offers Play on / Add to queue on.
  final List<RemotePresence> devices;

  /// Offers Play on (not while in a room).
  final bool playOn;
  final _SendTo onSendTo;

  double get topInset => insets.top;

  double get collapseRange => coverRowHeight + _actionsHeight;

  @override
  double get minExtent => topInset + _barHeight;

  @override
  double get maxExtent => minExtent + collapseRange;

  @override
  bool shouldRebuild(_HeroDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final t = (shrinkOffset / collapseRange).clamp(0.0, 1.0);
    final heroFade = (1 - t / _barTitleFrom).clamp(0.0, 1.0);
    final barFade = ((t - _barTitleFrom) / (1 - _barTitleFrom)).clamp(0.0, 1.0);
    final barBottom = topInset + _barHeight;
    final playTop = max(
      topInset + (_barHeight - _playSize) / 2,
      barBottom +
          coverRowHeight +
          (_actionsHeight - _playSize) / 2 -
          shrinkOffset,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // The whole gradient, so the collapsed bar shows its top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: maxExtent,
          child: HeroBackdrop(
            color: heroColor,
            backgroundKey: const Key('playlist.heroBackground'),
          ),
        ),
        // The hero scrolls up under the bar.
        Positioned(
          top: barBottom,
          left: 0,
          right: 0,
          bottom: 0,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: -shrinkOffset,
                left: insets.left,
                right: insets.right,
                height: collapseRange,
                child: Column(
                  children: [
                    SizedBox(
                      height: coverRowHeight,
                      child: heroFade == 0
                          ? null
                          : Opacity(
                              opacity: heroFade,
                              child: _HeroCover(
                                summary: summary,
                                summaryText: summaryText,
                                coverSize: _coverSize * (1 - 0.4 * t),
                              ),
                            ),
                    ),
                    SizedBox(
                      height: _actionsHeight,
                      child: _HeroActions(
                        canPlay: canPlay,
                        hasOwnCover: summary.hasOwnCover,
                        builtIn: summary.id == kFavoritesPlaylistId,
                        onShuffle: onShuffle,
                        onMenu: onMenu,
                        listenTogether: listenTogether,
                        devices: devices,
                        playOn: playOn,
                        onSendTo: onSendTo,
                        followed: followed,
                        canShare: canShare,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: topInset,
          left: insets.left,
          right: insets.right,
          height: _barHeight,
          child: SizedBox(
            key: const Key('playlist.topBar'),
            child: Row(
              children: [
                if (canGoBack)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: IconButton(
                      tooltip: 'Back',
                      color: colors.text,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  )
                else
                  const SizedBox(width: 16),
                Expanded(
                  child: barFade == 0
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: barFade,
                          child: Text(
                            summary.name,
                            key: const Key('playlist.barTitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                // Room for the pinned Play button.
                const SizedBox(width: 16 + _playSize + 8),
              ],
            ),
          ),
        ),
        Positioned(
          top: playTop,
          right: insets.right + 16,
          child: _PlayButton(enabled: canPlay, onPlay: onPlay),
        ),
      ],
    );
  }
}

class _HeroCover extends StatelessWidget {
  const _HeroCover({
    required this.summary,
    required this.summaryText,
    required this.coverSize,
  });

  final PlaylistSummary summary;
  final String summaryText;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final kindStyle = TextStyle(
      color: colors.mutedText,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox.square(
            dimension: _coverSize,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(colors.radius + 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: PlaylistArt(
                  key: const Key('playlist.cover'),
                  playlistId: summary.id,
                  coverRef: summary.coverRef,
                  size: coverSize,
                  radius: colors.radius + 4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.source == 'yt')
                  YtHeroSubtitle(playlistId: summary.id, style: kindStyle)
                else
                  Text('Local playlist', style: kindStyle),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    summary.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  summaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shuffle and the ⋯ menu; the Play button floats at the row's end.
class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.canPlay,
    required this.hasOwnCover,
    required this.builtIn,
    required this.onShuffle,
    required this.onMenu,
    required this.listenTogether,
    required this.devices,
    required this.playOn,
    required this.onSendTo,
    required this.followed,
    required this.canShare,
  });

  final bool canPlay;

  /// Followed (read-only): Make a copy and Stop following, no editing.
  final bool followed;
  final bool canShare;

  /// Favorites: no Rename and no Delete.
  final bool builtIn;

  /// Offers Remove cover (back to the first song's artwork).
  final bool hasOwnCover;
  final VoidCallback onShuffle;
  final ValueChanged<_MenuAction> onMenu;

  /// Offers Listen together (signed in, not in a room).
  final bool listenTogether;
  final List<RemotePresence> devices;
  final bool playOn;
  final _SendTo onSendTo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          OutlinedButton.icon(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            onPressed: canPlay ? onShuffle : null,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Shuffle'),
          ),
          const Spacer(),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz),
            onSelected: onMenu,
            itemBuilder: (_) => [
              if (!builtIn && !followed)
                const PopupMenuItem(
                  value: _MenuAction.rename,
                  child: Text('Rename'),
                ),
              if (!followed)
                const PopupMenuItem(
                  key: Key('playlist.changeCover'),
                  value: _MenuAction.changeCover,
                  child: Text('Change cover'),
                ),
              if (hasOwnCover && !followed)
                const PopupMenuItem(
                  key: Key('playlist.removeCover'),
                  value: _MenuAction.removeCover,
                  child: Text('Remove cover'),
                ),
              if (!followed)
                const PopupMenuItem(
                  value: _MenuAction.addSongs,
                  child: Text('Add songs'),
                ),
              if (canShare)
                const PopupMenuItem(
                  key: Key('playlist.share'),
                  value: _MenuAction.share,
                  child: Text('Share'),
                ),
              if (followed) ...[
                const PopupMenuItem(
                  key: Key('playlist.makeCopy'),
                  value: _MenuAction.makeCopy,
                  child: Text('Make a copy'),
                ),
                const PopupMenuItem(
                  key: Key('playlist.stopFollowing'),
                  value: _MenuAction.stopFollowing,
                  child: Text('Stop following'),
                ),
              ],
              if (listenTogether)
                const PopupMenuItem(
                  key: Key('playlist.listenTogether'),
                  value: _MenuAction.listenTogether,
                  child: Text('Listen together'),
                ),
              for (final d in devices) ...[
                if (playOn)
                  PopupMenuItem(
                    key: Key('playlist.playOn.${d.deviceId}'),
                    onTap: () => onSendTo(d, play: true),
                    child: Text('Play on ${d.name}'),
                  ),
                PopupMenuItem(
                  key: Key('playlist.addToQueueOn.${d.deviceId}'),
                  onTap: () => onSendTo(d, play: false),
                  child: Text('Add to queue on ${d.name}'),
                ),
              ],
              if (!builtIn && !followed)
                const PopupMenuItem(
                  value: _MenuAction.delete,
                  child: Text('Delete'),
                ),
            ],
          ),
          // The floating Play button sits here.
          const SizedBox(width: 16 + _playSize + 8),
        ],
      ),
    );
  }
}

/// The floating accent circle that plays the playlist from the top.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.enabled, required this.onPlay});

  final bool enabled;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filled(
      key: const Key('playlist.play'),
      tooltip: 'Play',
      iconSize: 30,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_playSize),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shadowColor: const Color(0x80000000),
      ),
      onPressed: enabled ? onPlay : null,
      icon: const Icon(Icons.play_arrow_rounded),
    );
  }
}

/// A YouTube playlist's Sync and Download, and how its downloads are going.
/// Download (any playlist with YouTube songs) and, for an imported playlist,
/// Sync.
class _YtActions extends StatelessWidget {
  const _YtActions({required this.playlistId, required this.imported});

  final String playlistId;
  final bool imported;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (imported) YtSyncButton(playlistId: playlistId),
              DownloadToggle(playlistId: playlistId),
            ],
          ),
          DownloadStatusLine(playlistId: playlistId),
        ],
      ),
    );
  }
}

/// Placeholder rows while an import's entries are on their way.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  static const int count = 8;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            KeyedSubtree(
              key: ValueKey(i),
              child: SizedBox(
                key: const Key('playlist.skeleton'),
                height: _rowHeight,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(width: _numberWidth),
                      SkeletonBox(width: 44, height: 44),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 160, height: 12),
                            SizedBox(height: 8),
                            SkeletonBox(width: 96, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A song in the playlist. Its ⋯, long-press and right-click open the song
/// menu, with Remove from this playlist.
class _TrackRow extends ConsumerWidget {
  const _TrackRow({
    required this.playlistId,
    required this.row,
    required this.index,
    required this.current,
    required this.playing,
    required this.onTap,
    required this.onLocate,
    required this.onRemove,
    this.reorderable = true,
    super.key,
  });

  final String playlistId;
  final PlaylistTrack row;

  /// Shows the drag handle (not on a followed playlist).
  final bool reorderable;
  final int index;

  /// The player's current track is this row's (played from this playlist).
  final bool current;

  /// The player is playing (not paused).
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLocate;

  /// Removes the row (with Undo); null on a followed playlist.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = row.track;
    final song = MenuSong.track(track);
    final menu = songMenuOpeners(
      context,
      ref,
      song,
      onRemoveFromPlaylist: onRemove,
    );
    final missing = row.fileMissing;
    final removed = row.status == 'removed_on_yt';
    final unavailable = track.unavailable;
    final dim = missing || removed || unavailable ? 0.45 : 1.0;
    return Material(
      color: colors.background,
      child: Pressable(
        onTap: onTap,
        onLongPress: menu.onLongPress,
        onSecondaryTapUp: menu.onSecondaryTapUp,
        child: SizedBox(
          height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                SizedBox(
                  width: _numberWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: current
                        ? EqualizerBars(playing: playing)
                        : Opacity(
                            opacity: dim,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
                Opacity(
                  opacity: dim,
                  child: Artwork(track.artworkRef, size: 44, seed: track.id),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: dim,
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: current ? colors.accent : colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (missing) ...[
                            const _MissingTag(),
                            const SizedBox(width: 6),
                          ],
                          if (removed) ...[
                            const YtRowTag('removed on YT'),
                            const SizedBox(width: 6),
                          ] else if (unavailable) ...[
                            const YtRowTag('unavailable'),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Opacity(
                              opacity: dim,
                              // Only as wide as its text, so the rest of the
                              // row stays a play tap.
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ArtistLink(
                                  text: track.artist,
                                  track: track,
                                  style: TextStyle(
                                    color: colors.mutedText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (missing)
                  TextButton(onPressed: onLocate, child: const Text('Locate')),
                if (removed) YtRemovedActions(entryId: row.entryId),
                if (track.source == 'yt')
                  TrackDownloadIcon(playlistId: playlistId, trackId: track.id),
                Opacity(
                  opacity: dim,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      trackDurationText(track.durationMs),
                      style: TextStyle(color: colors.mutedText, fontSize: 12),
                    ),
                  ),
                ),
                FavoriteStar(song: song),
                SongMenuButton(
                  key: Key('track.menu.${row.entryId}'),
                  song: song,
                  onRemoveFromPlaylist: onRemove,
                ),
                if (reorderable)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.drag_handle,
                        size: 22,
                        color: colors.mutedText,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingTag extends StatelessWidget {
  const _MissingTag();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          'File missing',
          maxLines: 1,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// "Following · by ‹owner›" on a followed playlist, or that its owner
/// stopped sharing it.
class _SharingLine extends StatelessWidget {
  const _SharingLine({required this.text, required this.following});

  final String text;
  final bool following;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      key: Key(following ? 'playlist.following' : 'playlist.ended'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(
            following ? Icons.link_rounded : Icons.link_off_rounded,
            size: 18,
            color: colors.mutedText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: colors.mutedText)),
          ),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground.queue() : _remove = false;
  const _SwipeBackground.remove() : _remove = true;

  final bool _remove;

  @override
  Widget build(BuildContext context) {
    if (_remove) {
      return Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primary,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.queue_music, color: scheme.onPrimary),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist({required this.onAdd});

  /// Add songs; null on a followed playlist.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.queue_music_rounded, size: 48, color: colors.mutedText),
          const SizedBox(height: 12),
          Text(
            'Add songs to get started',
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAdd, child: const Text('Add songs')),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          "Couldn't load this playlist",
          style: TextStyle(color: colors.mutedText),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This playlist no longer exists'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onBack, child: const Text('Back to Library')),
        ],
      ),
    );
  }
}
