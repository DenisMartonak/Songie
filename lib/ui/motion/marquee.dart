import 'package:flutter/material.dart';

import 'motion.dart';
import 'visible_ticker.dart';

/// One line of [text]. While [scroll] is true and the text does not fit, it
/// scrolls back and forth as a marquee, pausing 2 s at each end; it only
/// ticks while visible (see [VisibleTicker]). Otherwise, or with reduced
/// motion, it is a still line ending in an ellipsis.
class Marquee extends StatelessWidget {
  const Marquee(this.text, {required this.scroll, this.style, super.key});

  final String text;
  final bool scroll;
  final TextStyle? style;

  /// Rest at each end of the scroll.
  static const Duration pause = Duration(seconds: 2);

  /// Scroll speed, in logical pixels per second.
  static const double speed = 40;

  @override
  Widget build(BuildContext context) {
    final still = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (!scroll || Motion.of(context).reduced) return still;
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final overflow = width - box.maxWidth;
        if (!box.hasBoundedWidth || overflow <= 0) return still;
        return VisibleTicker(
          child: _Scroller(
            overflow: overflow,
            width: box.maxWidth,
            height: height,
            child: Text(text, maxLines: 1, softWrap: false, style: style),
          ),
        );
      },
    );
  }
}

class _Scroller extends StatefulWidget {
  const _Scroller({
    required this.overflow,
    required this.width,
    required this.height,
    required this.child,
  });

  /// How far the text sticks out past [width].
  final double overflow;
  final double width;
  final double height;
  final Widget child;

  @override
  State<_Scroller> createState() => _ScrollerState();
}

class _ScrollerState extends State<_Scroller>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_Scroller old) {
    super.didUpdateWidget(old);
    if (old.overflow != widget.overflow) _start();
  }

  /// One cycle: rest, scroll to the end, rest, scroll back; repeated.
  void _start() {
    final overflow = widget.overflow;
    final pause = Marquee.pause.inMilliseconds.toDouble();
    final travel = overflow / Marquee.speed * 1000;
    _offset = _controller.drive(
      TweenSequence([
        TweenSequenceItem(tween: ConstantTween(0.0), weight: pause),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: overflow,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: travel,
        ),
        TweenSequenceItem(tween: ConstantTween(overflow), weight: pause),
        TweenSequenceItem(
          tween: Tween(
            begin: overflow,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: travel,
        ),
      ]),
    );
    _controller
      ..duration = Duration(milliseconds: (2 * (pause + travel)).round())
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: _offset,
          builder: (context, child) => Transform.translate(
            offset: Offset(-_offset.value, 0),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}
