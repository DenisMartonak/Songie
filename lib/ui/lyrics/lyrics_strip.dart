import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// The slim row above the phone's lyrics: the song's title and artist, and
/// play/pause. Shows nothing when no song is loaded.
class LyricsStrip extends ConsumerWidget {
  const LyricsStrip({super.key});

  static const double height = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    if (track == null) return const SizedBox.shrink();
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
    );
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    key: const Key('lyricsStrip.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The page header's 70 % text, readable on this
                    // background (see blurScrim).
                    style: TextStyle(
                      color: colors.text.withAlpha(179),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('lyricsStrip.playPause'),
              tooltip: playing ? 'Pause' : 'Play',
              color: colors.text,
              iconSize: 32,
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              onPressed: () => ref.read(playerServiceProvider).togglePlay(),
            ),
          ],
        ),
      ),
    );
  }
}
