import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'motion.dart';

/// Makes [child] tappable with a little physical feedback: it scales down to
/// [pressedScale] over [Motion.quick] from the moment it is touched, keeps
/// the ink ripple, and on desktop tints the surface with the text colour at
/// 4 % under the mouse. A tap too quick to see still dips fully before scaling back. Like
/// [InkWell], it needs a [Material] ancestor. A right-click (desktop) runs
/// [onSecondaryTapUp] with where it happened, without the dip. With none of
/// [onTap], [onLongPress] and [onSecondaryTapUp] it is inert: no scale,
/// ripple, hover, cursor or focus.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.pressedScale = 0.97,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// A right-click; its details carry the pointer's global position, where
  /// a context menu opens.
  final GestureTapUpCallback? onSecondaryTapUp;
  final double pressedScale;

  /// Clips the ripple and the hover highlight.
  final BorderRadius? borderRadius;

  /// The hover highlight: the theme's text colour (white without a Songies
  /// theme) at 4 %, so it shows on light themes too.
  static Color hoverColorOf(BuildContext context) =>
      (Theme.of(context).extension<SongiesColors>()?.text ?? Colors.white)
          .withValues(alpha: 0.04);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  /// 0 at rest, 1 fully pressed.
  late final AnimationController _press = AnimationController(vsync: this)
    ..addStatusListener(_onPressStatus);

  /// The pointer has let go (or the press was taken over by a scroll or a
  /// long press) while the dip was still running.
  bool _released = false;

  /// Where the current press started; null when not pressed.
  Offset? _downAt;

  bool get _enabled =>
      widget.onTap != null ||
      widget.onLongPress != null ||
      widget.onSecondaryTapUp != null;

  void _down() {
    _released = false;
    _press
      ..duration = Motion.of(context).quick
      ..forward();
  }

  void _up() {
    if (_downAt == null) return;
    _downAt = null;
    if (_press.isForwardOrCompleted && _press.isAnimating) {
      // Let the dip finish so a quick tap is still seen, then come back.
      _released = true;
    } else {
      _press.reverse();
    }
  }

  void _onPressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _released) {
      _released = false;
      _press.reverse();
    }
  }

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (!_enabled) {
      _released = false;
      _downAt = null;
      _press.value = 0;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Listener(
      onPointerDown: enabled
          ? (e) {
              if (e.buttons & kPrimaryButton == 0) return;
              _downAt = e.position;
              _down();
            }
          : null,
      // Moving past the touch slop starts a scroll or drag: let go.
      onPointerMove: enabled
          ? (e) {
              final at = _downAt;
              if (at != null && (e.position - at).distance > kTouchSlop) {
                _up();
              }
            }
          : null,
      onPointerUp: enabled ? (_) => _up() : null,
      onPointerCancel: enabled ? (_) => _up() : null,
      child: ScaleTransition(
        scale: _press.drive(
          Tween<double>(
            begin: 1,
            end: widget.pressedScale,
          ).chain(CurveTween(curve: Motion.standardCurve)),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          // Lost to a scroll or a long press: let go now.
          onTapCancel: enabled ? _up : null,
          hoverColor: Pressable.hoverColorOf(context),
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}
