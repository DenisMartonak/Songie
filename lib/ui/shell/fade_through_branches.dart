import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../motion/motion.dart';

/// Holds the shell's branch navigators like an [IndexedStack] (each keeps
/// its state while hidden) and fades through to the newly selected one over
/// [Motion.standard], at once with reduced motion. Hidden branches are
/// offstage with their tickers off; nothing animates between switches.
class FadeThroughBranches extends StatefulWidget {
  const FadeThroughBranches({
    required this.currentIndex,
    required this.children,
    super.key,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );

  /// The branch fading out, while the switch runs.
  int? _previous;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _previous != null) {
        setState(() => _previous = null);
      }
    });
  }

  @override
  void didUpdateWidget(FadeThroughBranches old) {
    super.didUpdateWidget(old);
    if (old.currentIndex == widget.currentIndex) return;
    final duration = Motion.of(context).standard;
    if (duration == Duration.zero) {
      _previous = null;
      _controller.value = 1;
      return;
    }
    _previous = old.currentIndex;
    _controller
      ..duration = duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.currentIndex;
    final previous = _previous;
    final order = [
      for (var i = 0; i < widget.children.length; i++)
        if (i != current) i,
      current,
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in order)
          _Branch(
            // Keeps each branch's element (and navigator) while the order
            // changes.
            key: ValueKey(i),
            visible: i == current || i == previous,
            interactive: i == current,
            animation: i == current ? _controller : kAlwaysCompleteAnimation,
            secondaryAnimation: i == previous
                ? _controller
                : kAlwaysDismissedAnimation,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({
    required this.visible,
    required this.interactive,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    super.key,
  });

  final bool visible;
  final bool interactive;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !visible,
    child: TickerMode(
      enabled: visible,
      child: IgnorePointer(
        ignoring: !interactive,
        child: FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          fillColor: Colors.transparent,
          child: child,
        ),
      ),
    ),
  );
}
