import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import 'lyrics_view.dart';

/// The desktop's right-side lyrics panel, beside the main pane and on the
/// same rounded surface. It slides open and shut with the player bar's
/// Lyrics button; the lyrics view (and so any lookup) exists only while it is
/// open.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key});

  static const double width = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(lyricsPanelOpenProvider);
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final Widget panel = open
        ? Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: SizedBox(
              key: const Key('lyricsPanel'),
              width: width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(colors.radius + 4),
                child: ColoredBox(
                  color: colors.background,
                  // Like the rest of the chrome, its buttons must not take
                  // focus, or Space would re-press the last one clicked.
                  child: const ExcludeFocus(
                    child: LyricsView(density: LyricsDensity.compact),
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    final duration = Motion.of(context).standard;
    // Reduced motion: no AnimatedSize at all, which at zero duration would
    // re-dirty its own layout.
    if (duration == Duration.zero) return panel;
    return AnimatedSize(
      duration: duration,
      curve: Motion.standardCurve,
      alignment: Alignment.centerLeft,
      child: panel,
    );
  }
}
