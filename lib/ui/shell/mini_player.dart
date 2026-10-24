import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../now_playing/now_playing_page.dart' show nowPlayingArtHeroTag;
import '../widgets/artwork.dart';

/// The phone's mini-player: 48 high with an 8 px side margin, filled with the
/// theme's mini-player colour and a 2 px accent progress line along the bottom.
/// Renders nothing while the queue is empty. Tapping it opens Now Playing.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const double height = 48;
  static const double sideMargin = 8;

  /// Space the shell leaves between the mini-player and the nav.
  static const double gapAboveNav = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    if (track == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: sideMargin),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openNowPlaying(GoRouter.of(context)),
        child: Container(
          key: const Key('miniPlayer.pill'),
          height: height,
          decoration: BoxDecoration(
            color: colors.miniPlayer,
            borderRadius: BorderRadius.circular(colors.radius),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Hero(
                      tag: nowPlayingArtHeroTag,
                      // Stays visible while Now Playing is dragged down.
                      placeholderBuilder: (_, _, child) => child,
                      child: Artwork(
                        track.artworkRef,
                        size: 34,
                        radius: 8,
                        seed: track.id,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.text.withAlpha(153),
                              fontSize: 10,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('miniPlayer.playPause'),
                      tooltip: playing ? 'Pause' : 'Play',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      iconSize: 26,
                      color: colors.text,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: () =>
                          ref.read(playerServiceProvider).togglePlay(),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 0,
                height: 2,
                child: Container(
                  key: const Key('miniPlayer.track'),
                  color: Colors.white.withAlpha(51),
                  alignment: Alignment.centerLeft,
                  child: const _Progress(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The accent fill of the progress line; rebuilds on position changes only.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final fraction = ref.watch(
      playerStateProvider.select((s) {
        final state = s.value;
        final total = state?.duration?.inMilliseconds ?? 0;
        if (state == null || total <= 0) return 0.0;
        return (state.position.inMilliseconds / total).clamp(0.0, 1.0);
      }),
    );
    return FractionallySizedBox(
      widthFactor: fraction,
      child: Container(
        key: const Key('miniPlayer.progress'),
        color: colors.accent,
      ),
    );
  }
}
