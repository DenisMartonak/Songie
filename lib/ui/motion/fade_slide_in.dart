import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Fades [child] in while sliding it up 12 px over [Motion.standard], after
/// a stagger of 30 ms per [index] (capped at index 8), for lists and grids
/// as they fill.
///
/// Each item enters once: built again later in the same scroll view (or,
/// outside one, the same route), such as when scrolled back to, it appears
/// at once. Items that first appear later (a list that loads after the page,
/// rows scrolled into view) still enter, staggered from the first of them.
/// Items are told apart by [id], or by [index] when there is none; give
/// each an [id] when several lists share one scroll view. With reduced
/// motion everything appears at once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.index,
    required this.child,
    this.id,
    super.key,
  });

  /// The item's position in its list; sets the stagger.
  final int index;
  final Widget child;

  /// Identifies the item within its scroll view (defaults to [index]).
  final Object? id;

  /// Delay added per index.
  static const Duration stagger = Duration(milliseconds: 30);

  /// Indexes past this one start with the same delay.
  static const int maxStaggeredIndex = 8;

  /// How far below its place the child starts.
  static const double offset = 12;

  /// Items first built within this long of each other enter as one
  /// staggered group.
  static Duration get groupWindow =>
      stagger * maxStaggeredIndex + Motion.standard;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

/// The items of one scroll view (or route) that have entered, and the group
/// entering now.
class _Entrances {
  final Set<Object> entered = {};

  /// When the current group started, in frame time; null before the first.
  Duration? groupStart;

  /// The index the current group's stagger counts from: 0 for the first
  /// group (the page filling), else the group's first item.
  int groupOrigin = 0;
}

final Expando<_Entrances> _entrances = Expando('FadeSlideIn entrances');

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
    final scope = Scrollable.maybeOf(context) ?? ModalRoute.of(context);
    var position = widget.index;
    var elapsed = Duration.zero;
    if (scope != null) {
      final entrances = _entrances[scope] ??= _Entrances();
      if (!entrances.entered.add(widget.id ?? widget.index)) return;
      final groupStart = entrances.groupStart;
      if (groupStart == null || now - groupStart > FadeSlideIn.groupWindow) {
        entrances
          ..groupOrigin = groupStart == null ? 0 : widget.index
          ..groupStart = now;
      }
      position = widget.index - entrances.groupOrigin;
      elapsed = now - entrances.groupStart!;
    }

    final steps = position.clamp(0, FadeSlideIn.maxStaggeredIndex);
    var delay = FadeSlideIn.stagger * steps - elapsed;
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
