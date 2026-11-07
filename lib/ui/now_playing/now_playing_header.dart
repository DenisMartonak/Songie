import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../remote/remote_controller.dart' show kRemoteUnknownSource;
import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import '../widgets/song_menu.dart';

/// The page's top row: a close button (a chevron on a phone, an X on the
/// desktop panel), where the music is playing from, and a ⋯ button with the
/// current song's menu (on the side away from the close button).
class NowPlayingHeader extends ConsumerWidget {
  const NowPlayingHeader({
    required this.wide,
    required this.onClose,
    super.key,
  });

  final bool wide;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final sourceId = ref.watch(
      playerViewStateProvider.select((s) => s.value?.sourcePlaylistId),
    );
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final source = sourceId == null
        ? null
        : playlists.where((p) => p.id == sourceId).firstOrNull?.name;

    final close = IconButton(
      key: const Key('nowPlaying.close'),
      tooltip: 'Close',
      color: colors.text,
      iconSize: 28,
      icon: Icon(
        wide ? Icons.close_rounded : Icons.keyboard_arrow_down_rounded,
      ),
      onPressed: onClose,
    );
    final track = ref.watch(
      playerViewStateProvider.select((s) => s.value?.current),
    );
    final Widget more = track == null || track.source == kRemoteUnknownSource
        ? const SizedBox(width: 48)
        : SongMenuButton(
            key: const Key('nowPlaying.more'),
            song: MenuSong.track(track),
            color: colors.text,
            size: 24,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          wide ? more : close,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  source == null ? 'NOW PLAYING' : 'PLAYING FROM',
                  style: TextStyle(
                    color: colors.text.withAlpha(179),
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                if (source != null)
                  Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          wide ? close : more,
        ],
      ),
    );
  }
}

/// The tabs of Now Playing.
enum NowPlayingTab { player, lyrics, queue }

/// Switches between the player, the lyrics and the queue.
class NowPlayingTabs extends StatelessWidget {
  const NowPlayingTabs({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final NowPlayingTab selected;
  final ValueChanged<NowPlayingTab> onChanged;

  static const _labels = {
    NowPlayingTab.player: 'Now playing',
    NowPlayingTab.lyrics: 'Lyrics',
    NowPlayingTab.queue: 'Queue',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 24,
        children: [
          for (final tab in NowPlayingTab.values)
            _Tab(
              key: Key('nowPlaying.tab.${tab.name}'),
              label: _labels[tab]!,
              selected: tab == selected,
              onTap: () => onChanged(tab),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.text : colors.text.withAlpha(153),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A small download_done mark next to the artist when the playing YouTube
/// song is downloaded on this device; it fades in.
class NowPlayingDownloadedIcon extends ConsumerWidget {
  const NowPlayingDownloadedIcon({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(trackDownloadStateProvider(trackId)).value == 'done';
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return AnimatedSwitcher(
      duration: Motion.of(context).standard,
      transitionBuilder: (child, animation) => FadeTransition(
        key: const Key('nowPlaying.downloadedFade'),
        opacity: animation,
        child: child,
      ),
      child: done
          ? Padding(
              key: const ValueKey('downloaded'),
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.download_done,
                size: 16,
                semanticLabel: 'Downloaded',
                color: colors.accent,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
