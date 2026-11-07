import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import '../shell/player_bar.dart' show formatDuration;
import '../widgets/steady_track_shape.dart';

/// The seek slider with elapsed and remaining time underneath. Dragging
/// previews the time (both labels follow the finger); the seek happens when
/// the finger lifts. The 6 px track takes touches across a [touchHeight] band,
/// the thumb grows from nothing to 16 px while dragging, and the buffered part
/// is drawn at 30 % opacity.
class NowPlayingScrubber extends ConsumerStatefulWidget {
  const NowPlayingScrubber({super.key});

  /// Thumb radius while dragging (a 16 px thumb).
  static const double thumbRadius = 8;

  /// Height of the band that takes touches, centred on the track.
  static const double touchHeight = 32;

  /// From the track's centre down to the top of the time labels.
  static const double labelGap = 8;

  @override
  ConsumerState<NowPlayingScrubber> createState() => _NowPlayingScrubberState();
}

class _NowPlayingScrubberState extends ConsumerState<NowPlayingScrubber> {
  /// Slider value while the user drags; null otherwise.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final motion = Motion.of(context);
    final state = ref.watch(playerViewStateProvider).value;
    final total = state?.duration ?? Duration.zero;
    final seekable = state?.current != null && total > Duration.zero;
    double fractionOf(Duration d) => seekable
        ? (d.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final fraction = fractionOf(state?.position ?? Duration.zero);
    final buffered = fractionOf(state?.buffered ?? Duration.zero);
    final elapsed = _drag == null
        ? state?.position ?? Duration.zero
        : total * _drag!;
    final remaining = total > elapsed ? total - elapsed : Duration.zero;
    final style = TextStyle(color: colors.text.withAlpha(153), fontSize: 11);
    final bufferedColor = colors.text.withValues(alpha: 0.3);

    const half = NowPlayingScrubber.touchHeight / 2;
    // The labels sit inside the touch band's lower half (they let touches
    // through), so the bar is easy to hit without pushing the labels away.
    return SizedBox(
      height: half + NowPlayingScrubber.labelGap + 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: NowPlayingScrubber.touchHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                end: _drag == null ? 0 : NowPlayingScrubber.thumbRadius,
              ),
              duration: motion.quick,
              curve: Motion.standardCurve,
              builder: (context, radius, slider) => SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: colors.text,
                  inactiveTrackColor: colors.text.withAlpha(64),
                  secondaryActiveTrackColor: bufferedColor,
                  thumbColor: colors.text,
                  disabledThumbColor: Colors.transparent,
                  disabledActiveTrackColor: colors.text.withAlpha(64),
                  disabledInactiveTrackColor: colors.text.withAlpha(64),
                  disabledSecondaryActiveTrackColor: colors.text.withAlpha(64),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: radius,
                    disabledThumbRadius: 0,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: const SteadyTrackShape(),
                ),
                child: slider!,
              ),
              child: Slider(
                key: const Key('nowPlaying.scrubber'),
                value: _drag ?? fraction,
                secondaryTrackValue: buffered,
                onChanged: seekable ? (v) => setState(() => _drag = v) : null,
                onChangeEnd: (v) {
                  setState(() => _drag = null);
                  ref.read(playerViewProvider).seek(total * v);
                },
              ),
            ),
          ),
          Positioned(
            top: half + NowPlayingScrubber.labelGap,
            left: 6,
            right: 6,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(elapsed), style: style),
                  Text('-${formatDuration(remaining)}', style: style),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shuffle, previous, a 64 px accent play/pause circle, next and repeat.
class NowPlayingControls extends ConsumerWidget {
  const NowPlayingControls({super.key});

  /// Diameter of the play/pause circle.
  static const double playSize = 64;

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
        _PlayPauseButton(
          playing: playing,
          onPressed: hasTrack ? player.togglePlay : null,
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
          onPressed: () => player.setRepeat(switch (repeat) {
            RepeatMode.off => RepeatMode.all,
            RepeatMode.all => RepeatMode.one,
            RepeatMode.one => RepeatMode.off,
          }),
        ),
      ],
    );
  }
}

/// An [AnimatedIcons.play_pause] on an accent-filled circle: the icon morphs
/// over [Motion.standard] and the circle pulses once (1.0 → 1.06 → 1.0) when
/// pressed.
class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback? onPressed;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with TickerProviderStateMixin {
  /// 0 shows play, 1 shows pause.
  late final AnimationController _icon = AnimationController(
    vsync: this,
    value: widget.playing ? 1 : 0,
  );
  late final AnimationController _pulse = AnimationController(vsync: this);
  late final Animation<double> _scale = _pulse.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Motion.standardCurve)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Motion.standardCurve.flipped)),
        weight: 1,
      ),
    ]),
  );

  @override
  void didUpdateWidget(_PlayPauseButton old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      _icon.animateTo(
        widget.playing ? 1 : 0,
        duration: Motion.of(context).standard,
        curve: Motion.standardCurve,
      );
    }
  }

  void _press() {
    _pulse
      ..duration = Motion.of(context).standard
      ..forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _icon.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final enabled = widget.onPressed != null;
    return SizedBox(
      key: const Key('nowPlaying.playPause'),
      width: NowPlayingControls.playSize,
      height: NowPlayingControls.playSize,
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: enabled ? colors.accent : colors.accent.withAlpha(90),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Tooltip(
            message: widget.playing ? 'Pause' : 'Play',
            child: InkWell(
              onTap: enabled ? _press : null,
              child: Center(
                child: AnimatedIcon(
                  icon: AnimatedIcons.play_pause,
                  progress: _icon,
                  size: 38,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
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
