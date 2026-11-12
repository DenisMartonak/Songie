import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../data/database.dart';
import '../../downloads/download_repository.dart';
import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../remote/remote_protocol.dart';
import '../../theme/app_theme.dart';
import '../library/add_to_playlist_sheet.dart';
import '../motion/motion.dart';
import '../remote/play_on.dart';
import '../../room/room_protocol.dart' show RoomOp, roleAllows;
import '../room/room_button.dart' show roomGuestRoleProvider;
import '../ytm/artist_lookup.dart';
import '../ytm/ytm_nav.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// The song a menu is for: a library [Track] or a YouTube Music [YtmSong]
/// (stored as a track row the first time an action needs one).
@immutable
class MenuSong {
  const MenuSong.track(Track this.track) : ytm = null;
  const MenuSong.ytm(YtmSong this.ytm) : track = null;

  final Track? track;
  final YtmSong? ytm;

  String get title => track?.title ?? ytm!.title;
  String get subtitle => track?.artist ?? ytm!.artistLine;

  /// From YouTube (it streams, has a radio and can be downloaded).
  bool get isYouTube => ytm != null || track!.source == 'yt';

  /// A YouTube song that can no longer be played.
  bool get unavailable => track?.unavailable ?? false;

  /// The first artist with a YouTube Music page; library tracks don't keep
  /// one.
  String? get artistId =>
      ytm?.artists.map((a) => a.browseId).whereType<String>().firstOrNull;

  /// The album's YouTube Music page; library tracks don't keep one.
  String? get albumId => ytm?.albumBrowseId;
}

/// One menu item: its action, icon and label, and for Play on / Add to queue
/// on the device it is for.
typedef _Entry = (SongMenuAction, IconData, String, RemotePresence?);

/// A menu item's key: the action's name, then the device's id if it has one.
Key _entryKey(_Entry e) =>
    Key('songMenu.${e.$1.name}${e.$4 == null ? '' : '.${e.$4!.deviceId}'}');

enum SongMenuAction {
  addToQueue,
  playOn,
  addToQueueOn,
  addToPlaylist,
  favorite,
  startRadio,
  goToArtist,
  goToAlbum,
  download,
  removeDownload,
  removeFromPlaylist,
}

/// A row's handlers that open the song menu, for its `Pressable`.
typedef SongMenuOpeners = ({
  VoidCallback onLongPress,
  GestureTapUpCallback onSecondaryTapUp,
});

/// Long-press and right-click handlers that open [song]'s menu, for a row's
/// `Pressable` (`onLongPress` / `onSecondaryTapUp`): a sheet on long-press,
/// a popup at the pointer on right-click.
SongMenuOpeners songMenuOpeners(
  BuildContext context,
  WidgetRef ref,
  MenuSong song, {
  VoidCallback? onRemoveFromPlaylist,
}) => (
  onLongPress: () => showSongMenu(
    context,
    ref,
    song,
    onRemoveFromPlaylist: onRemoveFromPlaylist,
  ),
  onSecondaryTapUp: (d) => showSongMenu(
    context,
    ref,
    song,
    anchor: d.globalPosition & Size.zero,
    onRemoveFromPlaylist: onRemoveFromPlaylist,
  ),
);

/// Desktop builds open the ⋯ menu as a popup at the button; phones use the
/// sheet.
bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.windows ||
  TargetPlatform.macOS => true,
  _ => false,
};

/// A ⋯ button that opens [song]'s menu.
class SongMenuButton extends ConsumerWidget {
  const SongMenuButton({
    required this.song,
    this.onRemoveFromPlaylist,
    this.color,
    this.size = 20,
    super.key,
  });

  final MenuSong song;
  final VoidCallback? onRemoveFromPlaylist;

  /// The icon's colour; the theme's muted text by default.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return IconButton(
      // Not "More": that is the page's own menu (a playlist's, for one).
      tooltip: 'Song options',
      icon: Icon(Icons.more_vert, size: size, color: color ?? colors.mutedText),
      onPressed: () {
        Rect? anchor;
        if (_desktop) {
          final box = context.findRenderObject()! as RenderBox;
          anchor = box.localToGlobal(Offset.zero) & box.size;
        }
        showSongMenu(
          context,
          ref,
          song,
          anchor: anchor,
          onRemoveFromPlaylist: onRemoveFromPlaylist,
        );
      },
    );
  }
}

/// The one song menu, shown for [song] wherever a song is listed. Each item
/// shows only where it applies: Add to queue and Add to playlist always;
/// Start radio and Download / Remove download for a playable
/// YouTube song; Go to artist and Go to album when YouTube Music knows their
/// pages; Remove from this playlist with [onRemoveFromPlaylist] (inside one
/// of the user's playlists).
///
/// With [anchor] (global coordinates: a right-click's point, or a desktop ⋯
/// button) it is a popup menu there; without, a bottom sheet. Nothing is sent
/// to the user's YouTube account.
Future<void> showSongMenu(
  BuildContext context,
  WidgetRef ref,
  MenuSong song, {
  Rect? anchor,
  VoidCallback? onRemoveFromPlaylist,
}) async {
  // Read before the first await: the row (and its ref) may be gone after.
  final store = ref.read(ytTrackStoreProvider);
  final downloads = ref.read(downloadRepositoryProvider);
  final player = ref.read(playerServiceProvider);
  final radio = ref.read(radioControllerProvider);
  final askPermission = ref.read(notificationPermissionProvider);
  final favorites = ref.read(favoritesRepositoryProvider);
  final islands = Islands.of(context);
  // A room's guest adds to the host's queue, as its role allows, and never
  // its own local files (the others don't have them).
  final guestRole = ref.read(roomGuestRoleProvider);
  final guestView = guestRole == null ? null : ref.read(playerViewProvider);
  final offerQueue = guestRole == null || roleAllows(guestRole, RoomOp.addNext);
  final disabled = <SongMenuAction>{
    if (guestRole != null && song.track?.source == 'local')
      SongMenuAction.addToQueue,
  };
  // The menu closes when an entry is chosen: the sends outlive `ref`.
  final container = ProviderScope.containerOf(context);
  // remoteHostFollowerProvider (listened to in main) keeps this loaded on
  // every screen; unloaded, none are offered.
  final devices = playOnDevices(ref.read(remoteDevicesProvider).value);
  // In a room this device controls no other one: no Play on.
  final inRoom = ref.read(inRoomProvider);
  final playable = song.isYouTube && !song.unavailable;
  // Only Remove download needs it. Null where the app paths are not set up
  // (Remove download then says it couldn't).
  Directory? ytDir;
  if (playable) {
    try {
      ytDir = ref.read(appPathsProvider).libraryYt;
    } catch (e, s) {
      AppLog.w('Song menu: no app paths for downloads', e, s);
    }
  }

  var favorite = false;
  try {
    final known = song.track ?? await store.find(song.ytm!.videoId);
    if (known != null) {
      favorite = (await favorites.watchIds().first).contains(known.id);
    }
  } catch (e, s) {
    // The menu still opens; it offers Add to Favorites.
    AppLog.w('Song menu: reading Favorites failed', e, s);
  }
  if (!context.mounted) return;

  var downloaded = false;
  if (playable) {
    final known = song.track ?? await store.find(song.ytm!.videoId);
    if (known != null) {
      try {
        downloaded = (await downloads.rowIds([known.id])).isNotEmpty;
      } catch (e, s) {
        // The menu still opens; it offers Download.
        AppLog.w('Song menu: reading the download state failed', e, s);
      }
    }
    if (!context.mounted) return;
  }

  final entries = <_Entry>[
    if (offerQueue)
      (SongMenuAction.addToQueue, Icons.queue_music, 'Add to queue', null),
    for (final d in devices) ...[
      if (!inRoom)
        (SongMenuAction.playOn, Icons.cast_rounded, 'Play on ${d.name}', d),
      (
        SongMenuAction.addToQueueOn,
        Icons.queue_music,
        'Add to queue on ${d.name}',
        d,
      ),
    ],
    (SongMenuAction.addToPlaylist, Icons.playlist_add, 'Add to playlist', null),
    favorite
        ? (
            SongMenuAction.favorite,
            Icons.star_rounded,
            'Remove from Favorites',
            null,
          )
        : (
            SongMenuAction.favorite,
            Icons.star_outline_rounded,
            'Add to Favorites',
            null,
          ),
    if (playable)
      (SongMenuAction.startRadio, Icons.radio_outlined, 'Start radio', null),
    if (song.artistId != null || (song.track?.source == 'yt'))
      (SongMenuAction.goToArtist, Icons.person_outline, 'Go to artist', null),
    if (song.albumId != null)
      (SongMenuAction.goToAlbum, Icons.album_outlined, 'Go to album', null),
    if (playable)
      downloaded
          ? (
              SongMenuAction.removeDownload,
              Icons.delete_outline,
              'Remove download',
              null,
            )
          : (
              SongMenuAction.download,
              Icons.download_outlined,
              'Download',
              null,
            ),
    if (onRemoveFromPlaylist != null)
      (
        SongMenuAction.removeFromPlaylist,
        Icons.remove_circle_outline,
        'Remove from this playlist',
        null,
      ),
  ];

  final chosen = anchor == null
      ? await _sheet(context, song, entries, disabled)
      : await _popup(context, anchor, entries, disabled);
  // The row may be gone now (the list changed while the menu was open): the
  // actions that need its context check it; the others run regardless.
  if (chosen == null) return;
  final action = chosen.$1;

  /// [song]'s track row, storing a YouTube Music song first; null (with a
  /// island message) when it cannot be stored.
  Future<Track?> track() async {
    if (song.track case final t?) return t;
    final s = song.ytm!;
    switch (await store.upsert(s)) {
      case Ok(:final value):
        return value;
      case Err(:final failure):
        AppLog.w('Storing ${s.videoId} failed: ${failure.message}');
        islands.show("Couldn't add that song", kind: IslandKind.failure);
        return null;
    }
  }

  switch (action) {
    case SongMenuAction.addToQueue:
      if (await track() case final t?) {
        if (guestView != null) {
          await guestView.addNext([t]);
        } else {
          await player.addToQueue([t]);
        }
        islands.show('Added to queue', kind: IslandKind.success, song: t);
      }
    case SongMenuAction.playOn:
    case SongMenuAction.addToQueueOn:
      if (await track() case final t?) {
        await sendIdsTo(
          container,
          islands,
          chosen.$4!,
          ids: [t.id],
          play: action == SongMenuAction.playOn,
        );
      }
    case SongMenuAction.addToPlaylist:
      final t = await track();
      if (t != null && context.mounted) {
        await showAddToPlaylistSheet(context, ref, [t.id]);
      }
    case SongMenuAction.favorite:
      if (await track() case final t?) await favorites.toggle(t.id);
    case SongMenuAction.startRadio:
      if (song.ytm case final s?) {
        await radio.playWithRadio(s);
      } else {
        await radio.startRadio(song.track!);
      }
    case SongMenuAction.goToArtist:
      if (context.mounted) {
        await openArtist(
          context,
          ref,
          browseId: song.artistId,
          track: song.track,
          name: song.track?.artist ?? '',
        );
      }
    case SongMenuAction.goToAlbum:
      if (context.mounted) context.goYtmAlbum(song.albumId!);
    case SongMenuAction.download:
      final t = await track();
      if (t == null) return;
      unawaited(askPermission());
      try {
        if (!await downloads.downloadTrack(t.id)) {
          islands.show("Couldn't download that song", kind: IslandKind.failure);
        }
      } on DownloadDbException catch (e, s) {
        AppLog.w('Downloading a song failed', e, s);
        islands.show("Couldn't change that download", kind: IslandKind.failure);
      }
    case SongMenuAction.removeDownload:
      final t = await track();
      final dir = ytDir;
      if (t == null) return;
      if (dir == null) {
        islands.show("Couldn't change that download", kind: IslandKind.failure);
        return;
      }
      try {
        await downloads.removeTrackDownload(t.id, dir);
      } on DownloadDbException catch (e, s) {
        AppLog.w('Removing a song download failed', e, s);
        islands.show("Couldn't change that download", kind: IslandKind.failure);
      }
    case SongMenuAction.removeFromPlaylist:
      onRemoveFromPlaylist!();
  }
}

/// Reduced motion opens and closes the menu at once.
AnimationStyle _animation(BuildContext context) {
  final motion = Motion.of(context);
  return AnimationStyle(
    curve: Motion.standardCurve,
    duration: motion.standard,
    reverseDuration: motion.quick,
  );
}

Future<_Entry?> _sheet(
  BuildContext context,
  MenuSong song,
  List<_Entry> entries,
  Set<SongMenuAction> disabled,
) {
  return showModalBottomSheet<_Entry>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: _animation(context),
    builder: (sheet) {
      final colors = Theme.of(sheet).extension<SongiesColors>()!;
      return SingleChildScrollView(
        key: const Key('songMenu.sheet'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (song.subtitle.trim().isNotEmpty)
                    Text(
                      song.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.mutedText, fontSize: 13),
                    ),
                ],
              ),
            ),
            for (final e in entries)
              ListTile(
                key: _entryKey(e),
                enabled: !disabled.contains(e.$1),
                leading: Icon(e.$2, color: _entryColor(colors, e, disabled)),
                title: Text(
                  e.$3,
                  style: TextStyle(color: _entryColor(colors, e, disabled)),
                ),
                onTap: () => Navigator.of(sheet).pop(e),
              ),
          ],
        ),
      );
    },
  );
}

/// A greyed entry takes the muted colour.
Color _entryColor(
  SongiesColors colors,
  _Entry e,
  Set<SongMenuAction> disabled,
) => disabled.contains(e.$1) ? colors.mutedText : colors.text;

Future<_Entry?> _popup(
  BuildContext context,
  Rect anchor,
  List<_Entry> entries,
  Set<SongMenuAction> disabled,
) {
  final colors = Theme.of(context).extension<SongiesColors>()!;
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;
  final local = Rect.fromPoints(
    overlay.globalToLocal(anchor.topLeft),
    overlay.globalToLocal(anchor.bottomRight),
  );
  return showMenu<_Entry>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(local, Offset.zero & overlay.size),
    color: colors.surface,
    popUpAnimationStyle: _animation(context),
    items: [
      for (final e in entries)
        PopupMenuItem(
          key: _entryKey(e),
          value: e,
          enabled: !disabled.contains(e.$1),
          child: Row(
            children: [
              Icon(e.$2, size: 20, color: _entryColor(colors, e, disabled)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  e.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _entryColor(colors, e, disabled)),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
