import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../shell/player_bar.dart' show formatDuration;

/// The seek slider with elapsed and total time underneath. Dragging previews
/// the time; the seek happens when the finger lifts.
class NowPlayingScrubber extends ConsumerStatefulWidget {
  const NowPlayingScrubber({super.key});

  @override
  ConsumerState<NowPlayingScrubber> createState() => _NowPlayingScrubberState();
}

class _NowPlayingScrubberState extends ConsumerState<NowPlayingScrubber> {
  /// Slider value while the user drags; null otherwise.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(playerStateProvider).value;
    final total = state?.duration ?? Duration.zero;
    final seekable = state?.current != null && total > Duration.zero;
    final fraction = seekable
        ? (state!.position.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final elapsed = _drag == null
        ? state?.position ?? Duration.zero
        : total * _drag!;
    final style = TextStyle(color: colors.text.withAlpha(153), fontSize: 11);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: colors.text,
            inactiveTrackColor: colors.text.withAlpha(64),
            thumbColor: colors.text,
            disabledThumbColor: Colors.transparent,
            disabledActiveTrackColor: colors.text.withAlpha(64),
            disabledInactiveTrackColor: colors.text.withAlpha(64),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            key: const Key('nowPlaying.scrubber'),
            value: _drag ?? fraction,
            onChanged: seekable ? (v) => setState(() => _drag = v) : null,
            onChangeEnd: (v) {
              setState(() => _drag = null);
              ref.read(playerServiceProvider).seek(total * v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(elapsed), style: style),
              Text(formatDuration(total), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shuffle, previous, a 64 px play/pause circle, next and repeat.
class NowPlayingControls extends ConsumerWidget {
  const NowPlayingControls({super.key});

  /// Diameter of the play/pause circle.
  static const double playSize = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final player = ref.read(playerServiceProvider);
    final hasTrack = ref.watch(
      playerStateProvider.select((s) => s.value?.current != null),
    );
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
    );
    final shuffle = ref.watch(
      playerStateProvider.select((s) => s.value?.shuffle ?? false),
    );
    final repeat = ref.watch(
      playerStateProvider.select((s) => s.value?.repeat ?? RepeatMode.off),
    );
    final idle = colors.text.withAlpha(179);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ControlButton(
          key: const Key('nowPlaying.shuffle'),
          icon: Icons.shuffle_rounded,
          tooltip: shuffle ? 'Shuffle: on' : 'Shuffle: off',
          color: shuffle ? colors.accent : idle,
          onPressed: () => player.setShuffle(!shuffle),
        ),
        _ControlButton(
          key: const Key('nowPlaying.previous'),
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous',
          size: 38,
          color: colors.text,
          onPressed: hasTrack ? player.previous : null,
        ),
        SizedBox(
          key: const Key('nowPlaying.playPause'),
          width: playSize,
          height: playSize,
          child: Material(
            color: colors.text.withAlpha(hasTrack ? 255 : 90),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message: playing ? 'Pause' : 'Play',
              child: InkWell(
                onTap: hasTrack ? player.togglePlay : null,
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 38,
                  color: colors.background,
                ),
              ),
            ),
          ),
        ),
        _ControlButton(
          key: const Key('nowPlaying.next'),
          icon: Icons.skip_next_rounded,
          tooltip: 'Next',
          size: 38,
          color: colors.text,
          onPressed: hasTrack ? player.next : null,
        ),
        _ControlButton(
          key: const Key('nowPlaying.repeat'),
          icon: repeat == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          tooltip: switch (repeat) {
            RepeatMode.off => 'Repeat: off',
            RepeatMode.all => 'Repeat: all',
            RepeatMode.one => 'Repeat: one',
          },
          color: repeat == RepeatMode.off ? idle : colors.accent,
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.size = 26,
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
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onPressed,
      // The colour goes on the icon itself so a disabled button keeps it.
      icon: Icon(
        icon,
        size: size,
        color: onPressed == null ? color.withAlpha(90) : color,
      ),
    );
  }
}
