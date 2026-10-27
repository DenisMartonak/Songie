import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/equalizer_bars.dart';
import '../motion/pressable.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';

/// The playing order as a reorderable list: drag a handle to move a song
/// (the row lifts with a shadow), swipe a row away to remove it, tap one to
/// play it, long-press or right-click one for the song menu. The playing row
/// shows [EqualizerBars].
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
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
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
      proxyDecorator: (child, _, animation) =>
          _LiftedRow(animation: animation, child: child),
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
          playing: playing,
          onTap: () => player.playAt(i),
          menu: songMenuOpeners(context, ref, MenuSong.track(queue[i])),
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
    required this.playing,
    required this.onTap,
    required this.menu,
  });

  final int index;
  final Track track;
  final bool current;

  /// Whether playback is running (the playing row's bars move).
  final bool playing;
  final VoidCallback onTap;

  /// Opens the song menu.
  final SongMenuOpeners menu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      key: Key('queue.row.$index'),
      type: MaterialType.transparency,
      child: Pressable(
        onTap: onTap,
        onLongPress: menu.onLongPress,
        onSecondaryTapUp: menu.onSecondaryTapUp,
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
                      Row(
                        children: [
                          if (current) ...[
                            EqualizerBars(playing: playing, size: 12),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
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
                        ],
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

/// The row being dragged: lifted off the list on the surface colour with a
/// shadow that grows as the drag starts.
class _LiftedRow extends StatelessWidget {
  const _LiftedRow({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  /// Elevation once fully lifted.
  static const double _lift = 8;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Material(
        key: const Key('queue.lifted'),
        color: colors.surface,
        shadowColor: Colors.black,
        elevation: _lift * Curves.easeOut.transform(animation.value),
        borderRadius: BorderRadius.circular(colors.radius),
        child: child,
      ),
      child: child,
    );
  }
}
