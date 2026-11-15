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
import 'artist_link.dart' show firstArtistName;
import 'profile_art.dart';
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

  final panel = _SongMenuPanel(
    song: song,
    favorite: favorite,
    entries: entries,
    disabled: disabled,
  );
  final chosen = anchor == null
      ? await _sheet(context, panel)
      : await _card(context, anchor, panel);
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
        await showAddToPlaylistSheet(context, ref, t.id);
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
          name: firstArtistName(song.track?.artist ?? ''),
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

/// The entries shown as big tiles, in this order.
const _tileActions = [
  SongMenuAction.addToQueue,
  SongMenuAction.addToPlaylist,
  SongMenuAction.startRadio,
];

String _tileLabel(SongMenuAction a) => switch (a) {
  SongMenuAction.addToQueue => 'Queue',
  SongMenuAction.addToPlaylist => 'Playlist',
  _ => 'Radio',
};

Future<_Entry?> _sheet(BuildContext context, _SongMenuPanel panel) {
  return showModalBottomSheet<_Entry>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    sheetAnimationStyle: _animation(context),
    builder: (sheet) => SingleChildScrollView(
      key: const Key('songMenu.sheet'),
      padding: const EdgeInsets.only(bottom: 8),
      child: panel,
    ),
  );
}

/// The menu as a card at [anchor] (global coordinates), kept on screen.
Future<_Entry?> _card(BuildContext context, Rect anchor, _SongMenuPanel panel) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final local = Rect.fromPoints(
    overlay.globalToLocal(anchor.topLeft),
    overlay.globalToLocal(anchor.bottomRight),
  );
  return navigator.push(
    _CardRoute(
      anchor: local,
      style: _animation(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      child: panel,
    ),
  );
}

class _CardRoute extends PopupRoute<_Entry> {
  _CardRoute({
    required this.anchor,
    required this.style,
    required this.child,
    required this.barrierLabel,
  });

  final Rect anchor;
  final AnimationStyle style;
  final Widget child;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => style.duration ?? Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      style.reverseDuration ?? transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return CustomSingleChildLayout(
      delegate: _CardLayout(anchor),
      child: Material(
        key: const Key('songMenu.card'),
        color: colors.surface,
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: style.curve ?? Curves.linear,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// Places the card at the anchor's bottom-left, flipped left or up when it
/// would leave the screen, then kept [_margin] inside it.
class _CardLayout extends SingleChildLayoutDelegate {
  _CardLayout(this.anchor);

  final Rect anchor;

  static const double _margin = 8;
  static const double _width = 360;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    return BoxConstraints(
      maxWidth: (size.width - 2 * _margin).clamp(0, _width),
      maxHeight: size.height * 0.8,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = anchor.left;
    if (x + child.width > size.width - _margin) x = anchor.right - child.width;
    var y = anchor.bottom;
    if (y + child.height > size.height - _margin) y = anchor.top - child.height;
    double fit(double v, double extent, double room) =>
        v.clamp(_margin, (room - extent - _margin).clamp(_margin, room));
    return Offset(
      fit(x, child.width, size.width),
      fit(y, child.height, size.height),
    );
  }

  @override
  bool shouldRelayout(_CardLayout old) => old.anchor != anchor;
}

/// The menu itself: the song's header with the Favorites star, the big
/// tiles, the other entries as rows, and Remove from this playlist below a
/// divider. Choosing pops the route with the entry.
class _SongMenuPanel extends StatelessWidget {
  const _SongMenuPanel({
    required this.song,
    required this.favorite,
    required this.entries,
    required this.disabled,
  });

  final MenuSong song;
  final bool favorite;
  final List<_Entry> entries;
  final Set<SongMenuAction> disabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final error = Theme.of(context).colorScheme.error;
    void choose(_Entry e) => Navigator.of(context).pop(e);
    _Entry? find(SongMenuAction a) =>
        entries.where((e) => e.$1 == a && e.$4 == null).firstOrNull;
    final star = find(SongMenuAction.favorite);
    final remove = find(SongMenuAction.removeFromPlaylist);
    final tiles = [for (final a in _tileActions) ?find(a)];
    final rows = [
      for (final e in entries)
        if (!identical(e, star) &&
            !identical(e, remove) &&
            !tiles.any((t) => identical(t, e)))
          e,
    ];
    final cover = song.ytm?.thumbnailUrl;
    final seed = song.track?.id ?? song.ytm!.videoId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
          child: Row(
            children: [
              ProfileArt(
                url: cover,
                artworkRef: song.track?.artworkRef,
                seed: seed,
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (song.subtitle.trim().isNotEmpty)
                      Text(
                        song.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.mutedText, fontSize: 14),
                      ),
                  ],
                ),
              ),
              if (star != null)
                KeyedSubtree(
                  key: const Key('songMenu.star'),
                  child: IconButton.filledTonal(
                    key: _entryKey(star),
                    tooltip: star.$3,
                    icon: Icon(
                      favorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: favorite ? colors.accent : colors.text,
                    ),
                    onPressed: () => choose(star),
                  ),
                ),
            ],
          ),
        ),
        if (tiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final (i, t) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: Key('songMenu.tile.${t.$1.name}'),
                      child: SongMenuTile(
                        key: _entryKey(t),
                        icon: t.$2,
                        label: _tileLabel(t.$1),
                        enabled: !disabled.contains(t.$1),
                        onTap: () => choose(t),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        for (final e in rows)
          _Row(
            entry: e,
            color: disabled.contains(e.$1) ? colors.mutedText : colors.text,
            enabled: !disabled.contains(e.$1),
            onTap: () => choose(e),
          ),
        if (remove != null) ...[
          Divider(
            indent: 16,
            endIndent: 16,
            color: colors.mutedText.withValues(alpha: 0.3),
          ),
          _Row(
            entry: remove,
            color: error,
            enabled: true,
            onTap: () => choose(remove),
          ),
        ],
      ],
    );
  }
}

/// One of the menu's big tiles: an icon above a short label.
class SongMenuTile extends StatelessWidget {
  const SongMenuTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final color = enabled ? colors.text : colors.mutedText;
    return Material(
      color: Color.alphaBlend(
        colors.accent.withValues(alpha: 0.16),
        colors.surface,
      ),
      borderRadius: BorderRadius.circular(colors.radius + 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final _Entry entry;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: _entryKey(entry),
      enabled: enabled,
      leading: Icon(entry.$2, color: color),
      title: Text(entry.$3, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}
