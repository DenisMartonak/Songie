import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion.dart';
import 'visible_ticker.dart';

/// Three bars that bounce while [playing], in the theme's primary colour.
/// Paused, or with reduced motion, they are static bars and nothing runs.
///
/// They step about 10 times a second rather than animating every frame: a
/// smooth 60 fps loop kept the whole window redrawing for as long as music
/// played (SON-30). They also hold still while the window isn't focused,
/// minimized, or the bars are off screen (see [VisibleTicker]).
class EqualizerBars extends StatelessWidget {
  const EqualizerBars({required this.playing, this.size = 14, super.key});

  final bool playing;

  /// Width and height of the square the bars fill.
  final double size;

  /// Time between steps of the bounce.
  static const Duration step = Duration(milliseconds: 100);

  /// How many times bars have been painted (tests count repaints).
  @visibleForTesting
  static int debugPaintCount = 0;

  @override
  Widget build(BuildContext context) {
    final animate = playing && !Motion.of(context).reduced;
    return VisibleTicker(
      active: animate,
      onlyWhileFocused: true,
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

class _BarsState extends State<_Bars> {
  /// Steps in one bounce cycle (0.9 s, as before).
  static const _stepsPerCycle = 9;

  final _phase = ValueNotifier<double>(0);
  Timer? _timer;
  bool _tickersOn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // VisibleTicker's TickerMode says whether moving is allowed right now.
    _tickersOn = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(_Bars old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    final run = widget.animate && _tickersOn;
    if (run && _timer == null) {
      _timer = Timer.periodic(EqualizerBars.step, (_) {
        _phase.value = (_phase.value + 1 / _stepsPerCycle) % 1.0;
      });
    } else if (!run) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: _BarsPainter(
        progress: _phase,
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

  final ValueListenable<double> progress;
  final bool animate;
  final Color color;

  /// Heights (as a fraction of the box) of the still bars.
  static const _still = [0.45, 0.8, 0.6];

  /// Phase offsets so the bars move out of step.
  static const _phase = [0.0, 0.35, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    EqualizerBars.debugPaintCount++;
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
