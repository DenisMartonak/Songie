import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/database.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;
import 'island_controller.dart';
import 'island_view.dart';

/// Gap between the island and the anchor's top.
const double _anchorGap = 10;

/// Gap between the island and the screen's bottom (or the keyboard's top)
/// when there is no anchor to come out of.
const double _edgeGap = 16;

/// The widest the island gets on wide layouts.
const double _wideMaxWidth = 420;

/// Shows the island over [child], above everything in it (sheets and dialogs
/// too, when [child] is the navigator). Owns the [IslandController] that
/// [Islands.of] hands out below it.
class IslandHost extends StatefulWidget {
  const IslandHost({required this.child, super.key});

  final Widget child;

  @override
  State<IslandHost> createState() => _IslandHostState();
}

class _IslandHostState extends State<IslandHost> {
  final _controller = IslandController();
  final _anchors = <_IslandAnchorState>[];

  /// Bumped when the anchor moves, comes or goes, so the layer is placed
  /// again.
  final _placement = ValueNotifier<int>(0);
  bool _bumpScheduled = false;
  final _stackKey = GlobalKey();

  void _register(_IslandAnchorState a) {
    _anchors.add(a);
    _bumpLater();
  }

  void _unregister(_IslandAnchorState a) {
    _anchors.remove(a);
    _bumpLater();
  }

  /// Places the island again after this frame. Anchors report during build,
  /// layout and unmounting, when the host can't be marked dirty.
  void _bumpLater() {
    if (_bumpScheduled) return;
    _bumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bumpScheduled = false;
      if (mounted) _placement.value++;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// The rect of the newest anchor on the current route, in the host's
  /// coordinates, or null when there is no usable anchor (none on the current
  /// route, not laid out, or collapsed).
  Rect? _anchorRect() {
    // An older anchor counts too: while the full-screen player closes, its
    // anchor's route is no longer current but the shell's already is.
    final anchor = _anchors.reversed
        .where((a) => a.mounted && a._routeIsCurrent)
        .firstOrNull;
    if (anchor == null) return null;
    final box = anchor.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.height <= 0) return null;
    final global = box.localToGlobal(Offset.zero) & box.size;
    final stack = _stackKey.currentContext?.findRenderObject();
    if (stack is! RenderBox || !stack.attached) return global;
    return global.shift(stack.globalToLocal(Offset.zero));
  }

  @override
  void dispose() {
    _controller.dispose();
    _placement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _IslandScope(
      host: this,
      child: Stack(
        key: _stackKey,
        children: [
          widget.child,
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: _placement,
              builder: (context, _, _) => LayoutBuilder(
                // Runs during layout, after [widget.child] (and the anchor in
                // it) has been laid out this frame, so the anchor's rect is
                // current.
                builder: (context, constraints) => _layer(context, constraints),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layer(BuildContext context, BoxConstraints constraints) {
    final size = constraints.biggest;
    final anchor = _anchorRect();
    final double line;
    final double gap;
    if (anchor != null) {
      line = anchor.top;
      gap = _anchorGap;
    } else {
      final media = MediaQuery.of(context);
      line =
          size.height -
          math.max(media.viewInsets.bottom, media.viewPadding.bottom);
      gap = _edgeGap;
    }
    final maxWidth = size.width >= phoneBreakpoint
        ? _wideMaxWidth
        : math.max(0.0, size.width - 32);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: line.clamp(0.0, size.height),
          // Only the area above the line is drawn, so the island seems to
          // come out from behind whatever is below it.
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: IslandView(controller: _controller, maxWidth: maxWidth),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IslandScope extends InheritedWidget {
  const _IslandScope({required this.host, required super.child});

  final _IslandHostState host;

  @override
  bool updateShouldNotify(_IslandScope old) => host != old.host;
}

/// Marks the widget the island comes out of (the player bar, or the phone's
/// bottom stack). When several are mounted, the newest one on the current
/// route is used.
class IslandAnchor extends StatefulWidget {
  const IslandAnchor({required this.child, super.key});

  final Widget child;

  @override
  State<IslandAnchor> createState() => _IslandAnchorState();
}

class _IslandAnchorState extends State<IslandAnchor> {
  _IslandHostState? _host;
  bool _routeIsCurrent = true;
  Rect? _reported;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context.getInheritedWidgetOfExactType<_IslandScope>()?.host;
    if (host != _host) {
      _host?._unregister(this);
      _host = host;
      host?._register(this);
    }
    // A sheet, menu, dialog or full-screen route above hides the anchor.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current != _routeIsCurrent) {
      _routeIsCurrent = current;
      _host?._bumpLater();
    }
  }

  /// After a frame in which the anchor was laid out or painted, tells the
  /// host if it moved.
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect == _reported) return;
      _reported = rect;
      _host?._bumpLater();
    });
  }

  @override
  void dispose() {
    _host?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AnchorBox(onUpdate: _scheduleCheck, child: widget.child);
}

/// Calls [onUpdate] whenever its child is laid out or painted.
class _AnchorBox extends SingleChildRenderObjectWidget {
  const _AnchorBox({required this.onUpdate, super.child});

  final VoidCallback onUpdate;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchorBox(onUpdate);

  @override
  void updateRenderObject(BuildContext context, _RenderAnchorBox renderObject) {
    renderObject.onUpdate = onUpdate;
  }
}

class _RenderAnchorBox extends RenderProxyBox {
  _RenderAnchorBox(this.onUpdate);

  VoidCallback onUpdate;

  @override
  void performLayout() {
    super.performLayout();
    onUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onUpdate();
  }
}

/// Shows messages on the nearest [IslandHost]'s island. Get one before an
/// `await` to keep using it afterwards: it stays usable after the context it
/// came from is gone.
class Islands {
  Islands._(this._host);

  /// The islands of the [IslandHost] above [context]; throws a
  /// [FlutterError] when there is none.
  static Islands of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_IslandScope>();
    if (scope == null) {
      throw FlutterError(
        'Islands.of() was called with a context that has no IslandHost '
        'above it.\nPut an IslandHost in the app (e.g. in MaterialApp.builder).',
      );
    }
    return Islands._(scope.host);
  }

  final _IslandHostState _host;

  /// Shows [text] on the island, replacing any message on show. With [song]
  /// its cover is shown instead of the [kind]'s icon.
  void show(
    String text, {
    IslandKind kind = IslandKind.info,
    Track? song,
    IslandAction? action,
    Duration duration = IslandMessage.defaultDuration,
  }) {
    if (!_host.mounted) return;
    _host._controller.show(
      IslandMessage(
        text: text,
        kind: kind,
        song: song,
        action: action,
        duration: duration,
      ),
    );
  }

  /// Hides the island.
  void clear() {
    if (_host.mounted) _host._controller.dismiss();
  }
}
