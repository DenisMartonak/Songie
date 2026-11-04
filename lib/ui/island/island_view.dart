import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import '../widgets/artwork.dart';
import 'island_controller.dart';

/// The island is black in every theme.
const Color _black = Color(0xFF000000);
const Color _white = Color(0xFFFFFFFF);

/// Height of a one-line island; its ends are fully round.
const double _height = 38;
const double _inset = 8;
const double _leadingSize = _height - 2 * _inset;
const BorderRadius _shape = BorderRadius.all(Radius.circular(_height / 2));

/// The pill that shows [controller]'s message. It pops up from below its
/// bottom edge (the host clips it there, so it seems to come from behind the
/// bar), morphs into each new message, and sinks back when dismissed.
class IslandView extends StatefulWidget {
  const IslandView({
    required this.controller,
    required this.maxWidth,
    super.key,
  });

  final IslandController controller;

  /// The widest the pill gets.
  final double maxWidth;

  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: Motion.standard,
  )..addStatusListener(_onStatus);
  late final Animation<double> _curve = CurvedAnimation(
    parent: _presence,
    curve: Motion.standardCurve,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.6,
    end: 1,
  ).animate(_curve);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);

  /// Opaque well before it is fully up, so it never looks washed out.
  late final Animation<double> _fade = CurvedAnimation(
    parent: _presence,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
  );

  /// The message drawn: the current one, or the last one while it sinks.
  IslandMessage? _shown;
  int _serial = 0;
  bool _hovering = false;
  double _dragged = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _onChange();
  }

  @override
  void didUpdateWidget(IslandView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      _onChange();
    }
  }

  void _onChange() {
    final m = widget.controller.current;
    if (m != null) {
      setState(() {
        _shown = m;
        _serial = widget.controller.serial;
      });
      _presence.forward();
      // A new message under the pointer waits, like the one it replaced.
      if (_hovering) widget.controller.pause();
    } else if (_shown != null) {
      setState(() {});
      _presence.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _shown = null);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _shown;
    if (m == null) return const SizedBox.shrink();
    final reduced = Motion.of(context).reduced;
    final controller = widget.controller;

    Widget pill = _Pill(
      message: m,
      serial: _serial,
      maxWidth: widget.maxWidth,
      reduced: reduced,
      onAction: controller.runAction,
    );
    pill = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _hovering = true;
        controller.pause();
      },
      onExit: (_) {
        _hovering = false;
        controller.resume();
      },
      child: GestureDetector(
        onTap: controller.dismiss,
        onVerticalDragStart: (_) => _dragged = 0,
        onVerticalDragUpdate: (d) => _dragged += d.delta.dy,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 0 || _dragged > 16) {
            controller.dismiss();
          }
        },
        child: pill,
      ),
    );
    // While sinking it is no longer there to be touched.
    pill = IgnorePointer(ignoring: controller.current == null, child: pill);

    if (reduced) return FadeTransition(opacity: _presence, child: pill);
    return SlideTransition(
      position: _slide,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: _fade, child: pill),
      ),
    );
  }
}

/// The black pill, which animates its size and cross-fades its content when
/// the message changes.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.message,
    required this.serial,
    required this.maxWidth,
    required this.reduced,
    required this.onAction,
  });

  final IslandMessage message;
  final int serial;
  final double maxWidth;
  final bool reduced;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('island'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: const BoxDecoration(
          color: _black,
          borderRadius: _shape,
          boxShadow: [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        // A faint outline keeps it visible on an all-black theme. Drawn on
        // top, so it takes no room.
        foregroundDecoration: BoxDecoration(
          borderRadius: _shape,
          border: Border.all(color: _white.withValues(alpha: 0.10)),
        ),
        child: AnimatedSize(
          duration: reduced ? Duration.zero : Motion.standard,
          curve: Motion.standardCurve,
          child: AnimatedSwitcher(
            duration: Motion.standard,
            // The old content is gone before the new one shows much, so the
            // two never read as one jumbled line.
            switchInCurve: const Interval(0.35, 1, curve: Curves.easeOut),
            switchOutCurve: const Interval(0.6, 1, curve: Curves.easeIn),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: [
                // The outgoing content keeps its own size and doesn't hold
                // the pill open, so the pill heads straight for the new size.
                for (final child in previous)
                  Positioned.fill(
                    child: OverflowBox(
                      maxWidth: maxWidth,
                      maxHeight: double.infinity,
                      child: child,
                    ),
                  ),
                ?current,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(serial),
              child: _Content(message: message, onAction: onAction),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.message, required this.onAction});

  final IslandMessage message;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        theme.extension<SongiesColors>()?.accent ?? theme.colorScheme.primary;
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final textStyle = base.copyWith(
      color: _white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.25,
      decoration: TextDecoration.none,
    );
    final action = message.action;

    return Padding(
      padding: EdgeInsets.only(left: _inset, right: action == null ? 16 : 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: _inset),
            child: _Leading(message: message, accent: accent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: _inset),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  message.text,
                  style: textStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                // As tall as a one-line island, so the whole end is the
                // target and its highlight follows the pill's round end.
                minimumSize: const Size(48, _height),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                shape: const StadiumBorder(),
                textStyle: textStyle.copyWith(fontWeight: FontWeight.w700),
              ),
              child: Text(action.label),
            ),
          ],
        ],
      ),
    );
  }
}

/// The song's cover, or the kind's icon.
class _Leading extends StatelessWidget {
  const _Leading({required this.message, required this.accent});

  final IslandMessage message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final song = message.song;
    if (song != null) {
      return Artwork(
        song.artworkRef,
        size: _leadingSize,
        radius: 4,
        seed: song.id,
      );
    }
    final (icon, color) = switch (message.kind) {
      IslandKind.success => (Icons.check_circle_rounded, accent),
      IslandKind.failure => (
        Icons.warning_amber_rounded,
        const Color(0xFFFFB74D),
      ),
      IslandKind.info => (
        Icons.info_outline_rounded,
        _white.withValues(alpha: 0.75),
      ),
    };
    return Icon(icon, size: _leadingSize, color: color);
  }
}
