import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart' show Track;
import '../../player/player_service.dart';
import '../../providers.dart';
import '../../remote/remote_controller.dart' show kRemoteUnknownSource;
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import '../now_playing/now_playing_page.dart' show nowPlayingArtHeroTag;
import '../widgets/artwork.dart';
import '../widgets/favorite_star.dart';
import '../widgets/song_menu.dart';
import '../widgets/steady_track_shape.dart';

/// The desktop's bottom player bar, 72 px high: the current track on the left;
/// shuffle, previous, play/pause, next, repeat and a scrubber in the middle;
/// lyrics, queue and volume on the right. The background is the surface
/// blended with the theme's tint at 40 %.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  static const double height = 72;

  /// How much of the tint goes into the background.
  static const double _tintBlend = 0.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return SizedBox(
      key: const Key('playerBar'),
      height: height,
      child: ColoredBox(
        key: const Key('playerBar.background'),
        color: Color.lerp(colors.surface, colors.miniPlayer, _tintBlend)!,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: LayoutBuilder(
            builder: (context, box) {
              final middle = (box.maxWidth * 0.4).clamp(300.0, 620.0);
              return Row(
                children: [
                  const Expanded(child: _NowPlaying()),
                  SizedBox(width: middle, child: const _Transport()),
                  const Expanded(child: _QueueAndVolume()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerViewStateProvider.select((s) => s.value?.current),
    );
    if (track == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Right-click opens the playing song's menu at the pointer.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: track.source == kRemoteUnknownSource
          ? null
          : (d) => showSongMenu(
              context,
              ref,
              MenuSong.track(track),
              anchor: d.globalPosition & Size.zero,
            ),
      child: _row(track, colors),
    );
  }

  Widget _row(Track track, SongiesColors colors) {
    return Row(
      children: [
        Hero(
          tag: nowPlayingArtHeroTag,
          // Stays visible under the desktop panel after the flight.
          placeholderBuilder: (_, _, child) => child,
          child: Artwork(track.artworkRef, size: 46, radius: 6, seed: track.id),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The star follows the title; a long title shrinks with an
              // ellipsis so the star stays visible.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FavoriteStar(
                    song: MenuSong.track(track),
                    size: 16,
                    dense: true,
                  ),
                ],
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.mutedText, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final player = ref.read(playerViewProvider);
    final hasTrack = ref.watch(
      playerViewStateProvider.select((s) => s.value?.current != null),
    );
    final playing = ref.watch(
      playerViewStateProvider.select((s) => s.value?.playing ?? false),
    );
    final shuffle = ref.watch(
      playerViewStateProvider.select((s) => s.value?.shuffle ?? false),
    );
    final repeat = ref.watch(
      playerViewStateProvider.select((s) => s.value?.repeat ?? RepeatMode.off),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BarButton(
              key: const Key('playerBar.shuffle'),
              icon: Icons.shuffle_rounded,
              tooltip: shuffle ? 'Shuffle: on' : 'Shuffle: off',
              color: shuffle ? colors.accent : colors.mutedText,
              onPressed: () => player.setShuffle(!shuffle),
            ),
            _BarButton(
              key: const Key('playerBar.previous'),
              icon: Icons.skip_previous_rounded,
              tooltip: 'Previous',
              size: 26,
              color: colors.text,
              onPressed: hasTrack ? player.previous : null,
            ),
            _PlayPauseButton(
              playing: playing,
              onPressed: hasTrack ? player.togglePlay : null,
            ),
            _BarButton(
              key: const Key('playerBar.next'),
              icon: Icons.skip_next_rounded,
              tooltip: 'Next',
              size: 26,
              color: colors.text,
              onPressed: hasTrack ? player.next : null,
            ),
            _BarButton(
              key: const Key('playerBar.repeat'),
              icon: repeat == RepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              tooltip: switch (repeat) {
                RepeatMode.off => 'Repeat: off',
                RepeatMode.all => 'Repeat: all',
                RepeatMode.one => 'Repeat: one',
              },
              color: repeat == RepeatMode.off
                  ? colors.mutedText
                  : colors.accent,
              onPressed: () => player.setRepeat(switch (repeat) {
                RepeatMode.off => RepeatMode.all,
                RepeatMode.all => RepeatMode.one,
                RepeatMode.one => RepeatMode.off,
              }),
            ),
          ],
        ),
        const _Scrubber(),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: playing ? 'Pause' : 'Play',
        child: GestureDetector(
          key: const Key('playerBar.playPause'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.text.withAlpha(onPressed == null ? 90 : 255),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 24,
              color: colors.background,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.size = 20,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: size,
      color: color,
      disabledColor: color.withAlpha(90),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// Elapsed time, seek slider and total time. Rebuilds as the position moves.
class _Scrubber extends ConsumerStatefulWidget {
  const _Scrubber();

  @override
  ConsumerState<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<_Scrubber> {
  /// Slider value while the user drags; null otherwise.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(playerViewStateProvider).value;
    final total = state?.duration ?? Duration.zero;
    final seekable = state?.current != null && total > Duration.zero;
    final fraction = seekable
        ? (state!.position.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final shown = _drag ?? fraction;
    final elapsed = _drag == null
        ? state?.position ?? Duration.zero
        : total * _drag!;

    final style = TextStyle(color: colors.mutedText, fontSize: 10.5);
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              formatDuration(elapsed),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          const SizedBox(width: _timeGap),
          Expanded(
            child: _HoverSlider(
              sliderKey: const Key('playerBar.scrubber'),
              dragging: _drag != null,
              theme: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accent,
                inactiveTrackColor: colors.text.withAlpha(51),
                thumbColor: colors.text,
                disabledThumbColor: Colors.transparent,
                disabledActiveTrackColor: colors.text.withAlpha(51),
                disabledInactiveTrackColor: colors.text.withAlpha(51),
              ),
              value: shown,
              onChanged: seekable ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: (v) {
                setState(() => _drag = null);
                ref.read(playerViewProvider).seek(total * v);
              },
            ),
          ),
          const SizedBox(width: _timeGap),
          SizedBox(width: 38, child: Text(formatDuration(total), style: style)),
        ],
      ),
    );
  }

  /// Room between each time and the bar.
  static const double _timeGap = 12;
}

class _QueueAndVolume extends ConsumerWidget {
  const _QueueAndVolume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final volume = ref.watch(
      playerViewStateProvider.select((s) => s.value?.volume ?? 1.0),
    );
    final lyricsOpen = ref.watch(lyricsPanelOpenProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          key: const Key('playerBar.lyrics'),
          tooltip: 'Lyrics',
          iconSize: 20,
          color: lyricsOpen ? colors.accent : colors.mutedText,
          isSelected: lyricsOpen,
          icon: const Icon(Icons.lyrics_outlined),
          selectedIcon: const Icon(Icons.lyrics),
          onPressed: () => ref.read(lyricsPanelOpenProvider.notifier).toggle(),
        ),
        IconButton(
          key: const Key('playerBar.queue'),
          tooltip: 'Queue',
          iconSize: 20,
          color: colors.mutedText,
          icon: const Icon(Icons.queue_music_rounded),
          onPressed: () => openNowPlaying(GoRouter.of(context)),
        ),
        const SizedBox(width: 4),
        Icon(
          volume == 0
              ? Icons.volume_off_rounded
              : volume < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          size: 20,
          color: colors.mutedText,
        ),
        const SizedBox(width: 8),
        // Gives way in the narrowest desktop windows.
        Flexible(
          child: SizedBox(
            width: 104,
            child: _HoverSlider(
              sliderKey: const Key('playerBar.volume'),
              theme: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.text,
                inactiveTrackColor: colors.text.withAlpha(51),
                thumbColor: colors.text,
              ),
              value: volume,
              onChanged: (v) => ref.read(playerViewProvider).setVolume(v),
            ),
          ),
        ),
      ],
    );
  }
}

/// A slider whose track thickens from 4 to 6 px, and whose thumb appears,
/// while the mouse is over it (or it is being dragged); one [Motion.quick]
/// transition each way.
class _HoverSlider extends StatefulWidget {
  const _HoverSlider({
    required this.theme,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.dragging = false,
    this.sliderKey,
  });

  static const double _restTrack = 4;
  static const double _hoverTrack = 6;
  static const double _thumbRadius = 6;

  /// Colours and shapes; track height and thumb are set here.
  final SliderThemeData theme;
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Keeps the hover look while a drag is in progress.
  final bool dragging;

  /// The key of the [Slider] inside.
  final Key? sliderKey;

  @override
  State<_HoverSlider> createState() => _HoverSliderState();
}

class _HoverSliderState extends State<_HoverSlider> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final lifted = _hovered || widget.dragging;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: lifted ? 1 : 0),
        duration: Motion.of(context).quick,
        builder: (context, t, _) => SliderTheme(
          data: widget.theme.copyWith(
            trackHeight:
                _HoverSlider._restTrack +
                (_HoverSlider._hoverTrack - _HoverSlider._restTrack) * t,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: _HoverSlider._thumbRadius * t,
              disabledThumbRadius: 0,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: SliderComponentShape.noOverlay,
            // The bar keeps its length when the thumb appears.
            trackShape: const SteadyTrackShape(),
          ),
          child: Slider(
            key: widget.sliderKey,
            value: widget.value,
            onChanged: widget.onChanged,
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ),
    );
  }
}

/// `m:ss`, or `h:mm:ss` from one hour up.
String formatDuration(Duration d) {
  final total = math.max(0, d.inSeconds);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
