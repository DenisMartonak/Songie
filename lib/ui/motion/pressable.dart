import 'package:flutter/material.dart';

import 'motion.dart';

/// Makes [child] tappable with a little physical feedback: it scales down to
/// [pressedScale] over [Motion.quick] while pressed, keeps the ink ripple,
/// and on desktop lightens the surface by 4 % under the mouse. Like
/// [InkWell], it needs a [Material] ancestor. With neither [onTap] nor
/// [onLongPress] it is inert.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  /// Clips the ripple and the hover highlight.
  final BorderRadius? borderRadius;

  /// The hover highlight: white at 4 %.
  static final Color hoverColor = Colors.white.withValues(alpha: 0.04);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed ? widget.pressedScale : 1,
    duration: Motion.of(context).quick,
    curve: Motion.standardCurve,
    child: InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      hoverColor: Pressable.hoverColor,
      borderRadius: widget.borderRadius,
      child: widget.child,
    ),
  );
}
