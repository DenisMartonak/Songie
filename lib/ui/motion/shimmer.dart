import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'motion.dart';
import 'visible_ticker.dart';

/// A loading sweep over [child] (usually [SkeletonBox]es) every 1.2 s while
/// visible. It stops in the background (see [VisibleTicker]) and, with
/// reduced motion, shows the boxes without the sweep.
class Shimmer extends StatelessWidget {
  const Shimmer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context).reduced) return child;
    return VisibleTicker(child: _Sweep(child: child));
  }
}

class _Sweep extends StatefulWidget {
  const _Sweep({required this.child});

  final Widget child;

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  /// One pass of the sweep (a loop, not a transition).
  static const _period = Duration(milliseconds: 1200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      // The highlight band travels from off the left edge to off the right.
      final t = _controller.value * 3 - 1;
      return ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.35, 0.5, 0.65],
          transform: _SlideGradient(t),
        ).createShader(bounds),
        child: child,
      );
    },
  );
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.offset);

  /// In widths of the bounds.
  final double offset;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * offset, 0, 0);
}

/// A placeholder block in the theme's surface colour, for [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({required this.width, required this.height, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SongiesColors>();
    final surface =
        colors?.surface ?? theme.colorScheme.surfaceContainerHighest;
    final radius = math.min(colors?.radius ?? 4, height / 2);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
