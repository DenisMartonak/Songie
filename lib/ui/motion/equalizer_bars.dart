import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'visible_ticker.dart';

/// Three bars that bounce while [playing] and visible (see [VisibleTicker]),
/// in the theme's primary colour. Paused, or with reduced motion, they are
/// static bars and nothing ticks.
class EqualizerBars extends StatelessWidget {
  const EqualizerBars({required this.playing, this.size = 14, super.key});

  final bool playing;

  /// Width and height of the square the bars fill.
  final double size;

  @override
  Widget build(BuildContext context) {
    final animate = playing && !Motion.of(context).reduced;
    return VisibleTicker(
      active: animate,
      child: _Bars(animate: animate, size: size),
    );
  }
}

class _Bars extends StatefulWidget {
  const _Bars({required this.animate, required this.size});

  final bool animate;
  final double size;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  /// One bounce cycle of the bars (a loop, not a transition).
  static const _cycle = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Bars old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: _BarsPainter(
        progress: _controller,
        animate: widget.animate,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.progress,
    required this.animate,
    required this.color,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final bool animate;
  final Color color;

  /// Heights (as a fraction of the box) of the still bars.
  static const _still = [0.45, 0.8, 0.6];

  /// Phase offsets so the bars move out of step.
  static const _phase = [0.0, 0.35, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final gap = size.width / 7;
    final barWidth = (size.width - 2 * gap) / 3;
    for (var i = 0; i < 3; i++) {
      final fraction = animate
          ? 0.25 + 0.75 * math.sin((progress.value + _phase[i]) * math.pi).abs()
          : _still[i];
      final height = size.height * fraction;
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          Radius.circular(barWidth / 3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.animate != animate || old.color != color || old.progress != progress;
}
