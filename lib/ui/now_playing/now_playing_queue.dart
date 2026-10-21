import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/artwork.dart';

/// The playing order as a reorderable list: drag a handle to move a song,
/// swipe a row away to remove it, tap one to play it.
class NowPlayingQueue extends ConsumerWidget {
  const NowPlayingQueue({super.key});

  static const double rowHeight = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Only the queue and the playing index: watching the whole state would
    // rebuild the list on every position tick, which can rebuild a swiped-away
    // row before the queue update that removes it arrives.
    final queue =
        ref.watch(playerStateProvider.select((s) => s.value?.queue)) ??
        const <Track>[];
    final playingIndex = ref.watch(
      playerStateProvider.select((s) => s.value?.index ?? -1),
    );
    if (queue.isEmpty) {
      return Center(
        child: Text(
          'The queue is empty',
          style: TextStyle(color: colors.mutedText),
        ),
      );
    }
    final player = ref.read(playerServiceProvider);
    final keys = _slotKeys(queue);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.only(bottom: bottom + 16),
      itemCount: queue.length,
      onReorderItem: player.move,
      itemBuilder: (context, i) => Dismissible(
        key: keys[i],
        direction: DismissDirection.endToStart,
        onDismissed: (_) => player.removeAt(i),
        background: Container(
          color: colors.text.withAlpha(30),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline_rounded, color: colors.text),
        ),
        child: _QueueRow(
          index: i,
          track: queue[i],
          current: i == playingIndex,
          onTap: () => player.playAt(i),
        ),
      ),
    );
  }

  /// A key per slot that stays with its song when the list is reordered; the
  /// same song queued twice gets distinct keys.
  static List<Key> _slotKeys(List<Track> queue) {
    final seen = <String, int>{};
    return [
      for (final track in queue)
        ValueKey(
          '${track.id}#${seen.update(track.id, (n) => n + 1, ifAbsent: () => 0)}',
        ),
    ];
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    required this.track,
    required this.current,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: NowPlayingQueue.rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              children: [
                Artwork(track.artworkRef, size: 40, seed: track.id),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current ? colors.accent : colors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text.withAlpha(153),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  key: Key('queue.handle.$index'),
                  index: index,
                  child: SizedBox(
                    width: 56,
                    height: NowPlayingQueue.rowHeight,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: colors.text.withAlpha(153),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
