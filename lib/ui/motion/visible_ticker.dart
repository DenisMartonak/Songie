import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lets the tickers below it (looping animations such as [EqualizerBars] and
/// [Shimmer]) run only while [active], while visible (an ancestor
/// [TickerMode], as hidden routes and offstage tabs set, still applies) and
/// while the app is on screen. When the app is paused or hidden the tickers
/// are muted, so no frames are scheduled in the background.
class VisibleTicker extends StatefulWidget {
  const VisibleTicker({
    required this.child,
    this.active = true,
    this.onlyWhileFocused = false,
    super.key,
  });

  final Widget child;

  /// False mutes the tickers regardless (e.g. playback is paused).
  final bool active;

  /// Also mute them while the window is visible but not focused (another
  /// app in front). For decoration that would otherwise run all the time,
  /// such as the playing song's equalizer bars; not for things people watch
  /// from another window, such as synced lyrics.
  final bool onlyWhileFocused;

  @override
  State<VisibleTicker> createState() => _VisibleTickerState();
}

class _VisibleTickerState extends State<VisibleTicker>
    with WidgetsBindingObserver {
  late bool _appOnScreen = _onScreen(WidgetsBinding.instance.lifecycleState);
  late bool _focused = _isFocused(WidgetsBinding.instance.lifecycleState);

  /// Resumed is focused; null (before the first event) counts as focused.
  static bool _isFocused(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  static bool _onScreen(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.paused ||
    AppLifecycleState.hidden ||
    AppLifecycleState.detached => false,
    // Inactive is still visible (an unfocused desktop window); null is
    // before the first lifecycle event.
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final onScreen = _onScreen(state);
    final focused = _isFocused(state);
    if (onScreen == _appOnScreen && focused == _focused) return;
    setState(() {
      _appOnScreen = onScreen;
      _focused = focused;
    });
    // Frames stop once the app is hidden, so force one to rebuild and mute
    // the tickers (they unschedule their frame callbacks).
    if (!onScreen) SchedulerBinding.instance.scheduleForcedFrame();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled:
        widget.active && _appOnScreen && (_focused || !widget.onlyWhileFocused),
    child: widget.child,
  );
}
