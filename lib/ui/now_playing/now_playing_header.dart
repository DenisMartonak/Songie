import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// The page's top row: a close button (a chevron on a phone, an X on the
/// desktop panel) and where the music is playing from.
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
      playerStateProvider.select((s) => s.value?.sourcePlaylistId),
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
    const spacer = SizedBox(width: 48);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          wide ? spacer : close,
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
          wide ? close : spacer,
        ],
      ),
    );
  }
}

/// Switches between the player and the queue.
class NowPlayingTabs extends StatelessWidget {
  const NowPlayingTabs({
    required this.showQueue,
    required this.onChanged,
    super.key,
  });

  final bool showQueue;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Tab(
            key: const Key('nowPlaying.tab.player'),
            label: 'Now playing',
            selected: !showQueue,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 24),
          _Tab(
            key: const Key('nowPlaying.tab.queue'),
            label: 'Queue',
            selected: showQueue,
            onTap: () => onChanged(true),
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
