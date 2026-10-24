import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Fades [child] in while sliding it up 12 px over [Motion.standard], after
/// a stagger of 30 ms per [index] (capped at index 8), for lists and grids
/// as a page first fills.
///
/// It plays only while the page is first filling: items built later in the
/// same route (scrolled into view, or scrolled back to) appear at once. With
/// reduced motion everything appears at once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  /// Delay added per index.
  static const Duration stagger = Duration(milliseconds: 30);

  /// Indexes past this one start with the same delay.
  static const int maxStaggeredIndex = 8;

  /// How far below its place the child starts.
  static const double offset = 12;

  /// After a route's first item appeared, items built within this window
  /// still play; later ones appear at once.
  static Duration get fillWindow =>
      stagger * maxStaggeredIndex + Motion.standard;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

/// When each route's first [FadeSlideIn] was built, in frame time.
final Expando<Duration> _routeFillStart = Expando('FadeSlideIn fill start');

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// Stays complete unless the entrance plays.
  Animation<double> _opacity = kAlwaysCompleteAnimation;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }

  void _start() {
    final motion = Motion.of(context);
    if (motion.reduced) return;

    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final route = ModalRoute.of(context);
    var elapsed = Duration.zero;
    if (route != null) {
      final start = _routeFillStart[route] ??= now;
      elapsed = now - start;
      if (elapsed > FadeSlideIn.fillWindow) return;
    }

    final index = widget.index.clamp(0, FadeSlideIn.maxStaggeredIndex);
    var delay = FadeSlideIn.stagger * index - elapsed;
    if (delay < Duration.zero) delay = Duration.zero;
    final total = delay + motion.standard;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _opacity = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Motion.standardCurve,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _opacity;
    return FadeTransition(
      opacity: opacity,
      child: AnimatedBuilder(
        animation: opacity,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, FadeSlideIn.offset * (1 - opacity.value)),
          child: child,
        ),
      ),
    );
  }
}
