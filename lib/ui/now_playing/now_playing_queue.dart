import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../remote/remote_controller.dart' show kRemoteUnknownSource;
import '../../theme/app_theme.dart';
import '../motion/equalizer_bars.dart';
import '../motion/pressable.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../widgets/favorite_star.dart';

/// What plays next: the playing song at the top, then the songs after it as
/// a reorderable list. Drag a handle to move a song (the row lifts with a
/// shadow), swipe a row away to remove it, tap one to play it, long-press or
/// right-click one for the song menu. The playing row shows [EqualizerBars].
/// Songs that already played are not shown.
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
        ref.watch(playerViewStateProvider.select((s) => s.value?.queue)) ??
        const <Track>[];
    final playingIndex = ref.watch(
      playerViewStateProvider.select((s) => s.value?.index ?? -1),
    );
    final playing = ref.watch(
      playerViewStateProvider.select((s) => s.value?.playing ?? false),
    );
    if (queue.isEmpty) {
      return Center(
        child: Text(
          'The queue is empty',
          style: TextStyle(color: colors.mutedText),
        ),
      );
    }
    final player = ref.read(playerViewProvider);
    final keys = _slotKeys(queue);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Upcoming rows start after the playing one; row i is queue[first + i].
    final first = playingIndex < 0 ? 0 : playingIndex + 1;
    final upcoming = queue.length - first;

    return CustomScrollView(
      slivers: [
        if (playingIndex >= 0) ...[
          const SliverToBoxAdapter(child: _SectionLabel('Now playing')),
          SliverToBoxAdapter(
            child: _QueueRow(
              index: playingIndex,
              track: queue[playingIndex],
              current: true,
              playing: playing,
              onTap: () => player.playAt(playingIndex),
              menu: _menu(context, ref, queue[playingIndex]),
            ),
          ),
        ],
        if (upcoming > 0) ...[
          const SliverToBoxAdapter(child: _SectionLabel('Next up')),
          SliverReorderableList(
            itemCount: upcoming,
            onReorderItem: (from, to) => player.move(first + from, first + to),
            proxyDecorator: (child, _, animation) =>
                _LiftedRow(animation: animation, child: child),
            itemBuilder: (context, i) {
              final q = first + i;
              return Dismissible(
                key: keys[q],
                direction: DismissDirection.endToStart,
                onDismissed: (_) => player.removeAt(q),
                background: Container(
                  color: colors.text.withAlpha(30),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: Icon(Icons.delete_outline_rounded, color: colors.text),
                ),
                child: _QueueRow(
                  index: q,
                  dragIndex: i,
                  track: queue[q],
                  current: false,
                  playing: playing,
                  onTap: () => player.playAt(q),
                  menu: _menu(context, ref, queue[q]),
                ),
              );
            },
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
      ],
    );
  }

  /// The song menu of a row; none for a song this device doesn't have.
  static SongMenuOpeners? _menu(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) => track.source == kRemoteUnknownSource
      ? null
      : songMenuOpeners(context, ref, MenuSong.track(track));

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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: TextStyle(
          color: colors.mutedText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    this.dragIndex,
    required this.track,
    required this.current,
    required this.playing,
    required this.onTap,
    required this.menu,
  });

  /// Position in the queue.
  final int index;

  /// Position in the reorderable list; null for the playing row, which has no
  /// drag handle.
  final int? dragIndex;
  final Track track;
  final bool current;

  /// Whether playback is running (the playing row's bars move).
  final bool playing;
  final VoidCallback onTap;

  /// Opens the song menu.
  final SongMenuOpeners? menu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      key: Key('queue.row.$index'),
      type: MaterialType.transparency,
      child: Pressable(
        onTap: onTap,
        onLongPress: menu?.onLongPress,
        onSecondaryTapUp: menu?.onSecondaryTapUp,
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
                FavoriteStar(song: MenuSong.track(track)),
                if (dragIndex case final dragIndex?)
                  ReorderableDragStartListener(
                    key: Key('queue.handle.$index'),
                    index: dragIndex,
                    child: SizedBox(
                      width: 56,
                      height: NowPlayingQueue.rowHeight,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: colors.text.withAlpha(153),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 56),
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
