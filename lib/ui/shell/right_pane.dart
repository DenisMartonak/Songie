import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../lyrics/lyrics_view.dart';
import '../motion/motion.dart';
import '../now_playing/now_playing_queue.dart';
import 'right_pane_friends.dart';
import 'right_pane_state.dart';
import 'right_pane_strip.dart';

/// The desktop's right pane, beside the main pane and on the same rounded
/// surface: Friends, Lyrics or the Queue under a slim header with a close
/// button, or, closed, the strip of friends' faces. It slides open and shut; only what it shows is built, so lyrics
/// are looked up only while it shows them.
class RightPane extends ConsumerWidget {
  const RightPane({super.key});

  static const double width = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(rightPaneOpenProvider);
    // Not loaded yet: nothing, and nothing to animate from, so a stored
    // state shows at once rather than sliding in or out.
    if (open == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final Widget pane = open
        ? Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: SizedBox(
              key: const Key('rightPane'),
              width: width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(colors.radius + 4),
                child: ColoredBox(
                  color: colors.background,
                  // Like the rest of the chrome, its buttons must not take
                  // focus, or Space would re-press the last one clicked.
                  child: const ExcludeFocus(child: _OpenPane()),
                ),
              ),
            ),
          )
        : const RightPaneStrip();
    final duration = Motion.of(context).standard;
    // Reduced motion: no AnimatedSize at all, which at zero duration would
    // re-dirty its own layout.
    if (duration == Duration.zero) return pane;
    return AnimatedSize(
      duration: duration,
      curve: Motion.standardCurve,
      alignment: Alignment.centerLeft,
      child: pane,
    );
  }
}

/// The header and what the pane shows.
class _OpenPane extends ConsumerWidget {
  const _OpenPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final content = ref.watch(rightPaneContentProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  switch (content) {
                    RightPaneContent.friends => 'Friends',
                    RightPaneContent.lyrics => 'Lyrics',
                    RightPaneContent.queue => 'Queue',
                  },
                  key: const Key('rightPane.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const Key('rightPane.close'),
                tooltip: 'Close',
                iconSize: 20,
                color: colors.mutedText,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ref.read(rightPaneProvider).close(),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (content) {
            RightPaneContent.friends => const RightPaneFriends(),
            RightPaneContent.lyrics => const LyricsView(
              density: LyricsDensity.compact,
            ),
            RightPaneContent.queue => const NowPlayingQueue(),
          },
        ),
      ],
    );
  }
}
