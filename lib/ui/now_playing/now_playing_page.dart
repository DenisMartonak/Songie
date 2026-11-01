import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../motion/marquee.dart';
import '../lyrics/lyrics_strip.dart';
import '../lyrics/lyrics_view.dart';
import '../motion/motion.dart';
import '../shell/adaptive_shell.dart';
import '../widgets/artwork.dart';
import 'now_playing_controls.dart';
import 'now_playing_header.dart';
import 'now_playing_queue.dart';

/// Builds the `/now-playing` page for the window it opens in: a full-screen
/// page sliding up on a phone, and on desktop a centred panel over the shell
/// (non-opaque, so the title bar, sidebar and player bar stay visible behind
/// it; clicking outside closes it).
Page<void> nowPlayingPage(BuildContext context, GoRouterState state) =>
    _NowPlayingRoutePage(
      key: state.pageKey,
      wide: MediaQuery.sizeOf(context).width >= phoneBreakpoint,
      motion: Motion.of(context),
    );

class _NowPlayingRoutePage extends Page<void> {
  const _NowPlayingRoutePage({
    required this.wide,
    required this.motion,
    super.key,
  });

  final bool wide;
  final MotionDurations motion;

  @override
  Route<void> createRoute(BuildContext context) => NowPlayingRoute._(this);
}

/// The route Now Playing opens in. On a phone, dragging the page down drives
/// this route's own transition (as iOS's back swipe does), so the app shows
/// underneath while the page is dragged; at rest the route is opaque and the
/// app below is neither painted nor ticking.
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute._(_NowPlayingRoutePage page) : super(settings: page);

  _NowPlayingRoutePage get _page => settings as _NowPlayingRoutePage;

  /// The desktop panel (rather than the phone's full-screen page).
  bool get wide => _page.wide;

  @override
  bool get opaque => !wide;

  @override
  bool get barrierDismissible => wide;

  @override
  Color? get barrierColor => wide ? Colors.black54 : null;

  @override
  String? get barrierLabel => wide ? 'Close' : null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      wide ? _page.motion.standard : _page.motion.emphasized;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const NowPlayingPage();

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (wide) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Motion.standardCurve,
        ),
        child: child,
      );
    }
    // While a finger drives it, the page follows the finger exactly.
    final dragged = navigator?.userGestureInProgress ?? false;
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        dragged
            ? animation
            : CurvedAnimation(parent: animation, curve: Motion.emphasizedCurve),
      ),
      child: child,
    );
  }

  /// How far the page has been dragged down, as a fraction of its height.
  double get collapsed => 1 - controller!.value;

  /// The navigator told of the collapse gesture under way; null when none.
  /// Every [NavigatorState.didStartUserGesture] made here is balanced on it
  /// exactly once, whatever happens to the drag (see [_endGesture]).
  NavigatorState? _gesture;

  /// The page is being popped by the gesture itself.
  bool _poppingByGesture = false;

  /// A drag down the page has started. False (and nothing is driven) when
  /// the route is already on its way out.
  bool startCollapse() {
    if (_gesture != null || !isActive) return false;
    _gesture = navigator!..didStartUserGesture();
    return true;
  }

  /// The page was dragged by [fraction] of its height (positive is down).
  /// Ignored once the route has been popped by something else (e.g. system
  /// back), so its exit transition runs undisturbed.
  void dragCollapse(double fraction) {
    if (_gesture == null || !isActive) return;
    controller!.value -= fraction;
  }

  /// The finger lifted: [close] pops the route through [pop] (which carries
  /// the page on down); otherwise it springs back over [springBack].
  void endCollapse({
    required bool close,
    required VoidCallback pop,
    required Duration springBack,
  }) {
    if (_gesture == null) return;
    if (!isActive) {
      // Popped mid-drag: the gesture ends when the exit transition does.
      _endGestureWhenSettled();
      return;
    }
    if (close) {
      _poppingByGesture = true;
      pop();
      _poppingByGesture = false;
    } else {
      controller!.animateTo(
        1,
        duration: springBack,
        curve: Motion.standardCurve,
      );
    }
    _endGestureWhenSettled();
  }

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    // Popped by something else (system back) while a finger drives the
    // page: let the exit transition finish, then end the gesture.
    if (_gesture != null && !_poppingByGesture) _endGestureWhenSettled();
    return popped;
  }

  bool _awaitingSettle = false;

  void _endGestureWhenSettled() {
    final controller = this.controller!;
    if (!controller.isAnimating) {
      _endGesture();
      return;
    }
    if (_awaitingSettle) return;
    _awaitingSettle = true;
    late final AnimationStatusListener done;
    done = (status) {
      if (controller.isAnimating) return;
      controller.removeStatusListener(done);
      _awaitingSettle = false;
      _endGesture();
    };
    controller.addStatusListener(done);
  }

  void _endGesture() {
    final navigator = _gesture;
    _gesture = null;
    if (navigator != null && navigator.mounted) navigator.didStopUserGesture();
  }

  @override
  void dispose() {
    _endGesture();
    super.dispose();
  }
}

/// The [Hero] tag shared by the mini-player / player-bar artwork and the Now
/// Playing artwork, so the cover flies between them.
const String nowPlayingArtHeroTag = 'np-art';

/// What is playing: big art, title, scrubber and transport controls, with the
/// lyrics and the queue on the other tabs. Phone: full screen; desktop: a panel with a close
/// button. On both, dragging the page down moves it, and letting go past a
/// quarter of its height (or flinging it) closes it; otherwise it springs
/// back.
class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  /// Largest side of the cover art.
  static const double maxArt = 360;

  /// Fraction of the page's height, or fling speed (px/s), past which
  /// letting go of a downward drag closes the page.
  static const double closeFraction = 0.25;
  static const double closeVelocity = 700;

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  NowPlayingTab _tab = NowPlayingTab.player;

  /// On a phone the tabs are pages side by side: swiping moves between them.
  final PageController _pages = PageController();

  /// The tab a tap is sliding to; pages passed on the way don't select
  /// themselves.
  NowPlayingTab? _slidingTo;

  Future<void> _selectTab(NowPlayingTab tab) async {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (!_pages.hasClients) return;
    final duration = Motion.of(context).standard;
    if (duration == Duration.zero) {
      _pages.jumpToPage(tab.index);
      return;
    }
    _slidingTo = tab;
    try {
      await _pages.animateToPage(
        tab.index,
        duration: duration,
        curve: Motion.standardCurve,
      );
    } finally {
      if (_slidingTo == tab) _slidingTo = null;
    }
  }

  void _onPageChanged(int index) {
    final tab = NowPlayingTab.values[index];
    if (_slidingTo != null && tab != _slidingTo) return;
    setState(() => _tab = tab);
  }

  /// How far (px) the desktop panel has been dragged down. (On a phone the
  /// drag drives the route's own transition instead.)
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  /// The dragged page or panel, to measure its height.
  final GlobalKey _dragArea = GlobalKey();

  bool _closing = false;

  /// A collapse drag is under way (a tap's cancelled drag never starts).
  bool _dragging = false;

  /// The route the current drag drives (a phone page), captured when the
  /// drag starts so it is the one released, even if the layout changes.
  NowPlayingRoute? _dragRoute;

  /// Whether the current drag started in the desktop layout.
  bool _dragWide = false;

  /// Pops the page; false when there is nothing to pop it to.
  bool _close() {
    if (_closing) return true;
    if (!context.canPop()) return false;
    _closing = true;
    context.pop();
    return true;
  }

  double get _height =>
      _dragArea.currentContext?.size?.height ?? double.infinity;

  void _onDragStart(DragStartDetails _) {
    if (_closing || _dragging) return;
    final route = ModalRoute.of(context);
    _dragWide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;
    if (route is NowPlayingRoute && !route.wide && !_dragWide) {
      if (!route.startCollapse()) return;
      _dragRoute = route;
    }
    _dragging = true;
    _drag.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing || !_dragging) return;
    final route = _dragRoute;
    if (route != null) {
      route.dragCollapse(details.delta.dy / _height);
    } else {
      _drag.value = math.max(0, _drag.value + details.delta.dy);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing || !_dragging) return;
    final route = _dragRoute;
    final dragged = route?.collapsed ?? _drag.value / _height;
    final far = dragged >= NowPlayingPage.closeFraction;
    final fast = (details.primaryVelocity ?? 0) >= NowPlayingPage.closeVelocity;
    _letGo(close: (far || fast) && context.canPop());
  }

  void _onDragCancel() {
    if (_dragging) _letGo(close: false);
  }

  /// Ends a drag: closes the page (its exit transition carries it on from
  /// where it is) or springs it back.
  void _letGo({required bool close}) {
    _dragging = false;
    final springBack = Motion.of(context).standard;
    final route = _dragRoute;
    _dragRoute = null;
    if (route != null) {
      route.endCollapse(
        close: close,
        pop: () => _close(),
        springBack: springBack,
      );
    } else if (!close || !_close()) {
      _drag.animateTo(0, duration: springBack, curve: Motion.standardCurve);
    }
  }

  @override
  void dispose() {
    // A drag cut short by the page going away still ends its gesture.
    _dragRoute?.endCollapse(
      close: false,
      pop: () {},
      springBack: Duration.zero,
    );
    _dragRoute = null;
    _drag.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Starts the collapse drag from [child]. On desktop a trackpad's two-finger
  /// pan scrolls rather than drags.
  Widget _dragHandle(Widget child, {required bool wide}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    supportedDevices: wide
        ? const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
            PointerDeviceKind.unknown,
          }
        : null,
    onVerticalDragStart: _onDragStart,
    onVerticalDragUpdate: _onDragUpdate,
    onVerticalDragEnd: _onDragEnd,
    onVerticalDragCancel: _onDragCancel,
    child: child,
  );

  /// [child] as the page that the drag moves.
  Widget _page(Widget child) => KeyedSubtree(
    key: const Key('nowPlaying.page'),
    child: KeyedSubtree(key: _dragArea, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final wide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;
    if (_dragging && wide != _dragWide) {
      // The layout changed under the finger (e.g. a rotation): the drag's
      // handle is rebuilt away, so end the drag here, springing back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragging) _letGo(close: false);
      });
    }

    if (!wide && !_pages.hasClients && _tab != NowPlayingTab.player) {
      // Back from the desktop layout: show the tab that was open there.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_tab.index);
      });
    }

    // On desktop only the header and the player tab start the drag: the
    // lyrics and the queue keep the mouse for their own scrolling (and the
    // queue's reordering).
    Widget handle(Widget child) =>
        wide ? _dragHandle(child, wide: true) : child;

    final body = Stack(
      children: [
        const Positioned.fill(child: _Background()),
        SafeArea(
          child: Column(
            children: [
              handle(
                Column(
                  children: [
                    NowPlayingHeader(wide: wide, onClose: _close),
                    NowPlayingTabs(selected: _tab, onChanged: _selectTab),
                  ],
                ),
              ),
              Expanded(
                child: wide
                    ? switch (_tab) {
                        NowPlayingTab.player => handle(const _PlayerTab()),
                        NowPlayingTab.lyrics => _LyricsTab(wide: wide),
                        NowPlayingTab.queue => const NowPlayingQueue(),
                      }
                    : PageView(
                        key: const Key('nowPlaying.pages'),
                        controller: _pages,
                        onPageChanged: _onPageChanged,
                        children: [
                          for (final tab in NowPlayingTab.values)
                            _KeepAlive(
                              child: switch (tab) {
                                NowPlayingTab.player => const _PlayerTab(),
                                NowPlayingTab.lyrics => _LyricsTab(wide: wide),
                                NowPlayingTab.queue => const NowPlayingQueue(),
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      final size = MediaQuery.sizeOf(context);
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: math.min(780, size.height - 48),
          ),
          child: AnimatedBuilder(
            animation: _drag,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _drag.value),
              child: child,
            ),
            child: _page(
              Material(
                key: const Key('nowPlaying.panel'),
                color: colors.background,
                clipBehavior: Clip.antiAlias,
                elevation: 12,
                borderRadius: BorderRadius.circular(colors.radius + 8),
                child: body,
              ),
            ),
          ),
        ),
      );
    }

    return _dragHandle(
      _page(Scaffold(backgroundColor: colors.background, body: body)),
      wide: false,
    );
  }
}

/// Keeps a swiped-away tab's page (its scroll position and state) alive.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The theme's `nowPlayingTop → nowPlayingBottom` gradient, over the cover
/// blurred (σ 40) and a readability scrim when the theme asks for it.
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final blur = colors.blurNowPlaying;
    final top = colors.nowPlayingTop;
    final bottom = colors.nowPlayingBottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Const, so colour tweens never rebuild (or re-blur) it.
        if (blur) ...[
          const _BlurredCover(),
          // Keeps the text readable on light covers (see [blurScrim]).
          ColoredBox(
            key: const Key('nowPlaying.scrim'),
            color: blurScrim(colors),
          ),
        ],
        DecoratedBox(
          key: const Key('nowPlaying.glow'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: blur
                  ? [
                      top.withValues(alpha: top.a * _overBlurTop),
                      bottom.withValues(alpha: bottom.a * _overBlurBottom),
                    ]
                  : [top, bottom],
            ),
          ),
        ),
      ],
    );
  }
}

/// The playing cover, small and blurred at σ 40, in a layer of its own: it
/// is built and painted once per track (crossfading on a change), not on
/// position ticks, play/pause or colour tweens.
class _BlurredCover extends ConsumerWidget {
  const _BlurredCover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    return RepaintBoundary(
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: Motion.of(context).emphasized,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: track == null
              ? const SizedBox.expand()
              : ImageFiltered(
                  key: ValueKey(track.id),
                  imageFilter: ImageFilter.blur(
                    sigmaX: 40,
                    sigmaY: 40,
                    tileMode: TileMode.clamp,
                  ),
                  // A small copy scaled up: the blur hides the difference.
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: Artwork(
                      track.artworkRef,
                      size: 96,
                      radius: 0,
                      seed: track.id,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Art, title and artist, scrubber and controls. The art crossfades and
/// grows from 0.92 on a track change, and sits at 0.88 while paused; the
/// title and artist slide 16 px in the skip direction.
class _PlayerTab extends ConsumerStatefulWidget {
  const _PlayerTab();

  @override
  ConsumerState<_PlayerTab> createState() => _PlayerTabState();
}

class _PlayerTabState extends ConsumerState<_PlayerTab> {
  /// How far the title and artist slide on a track change.
  static const double _slide = 16;

  /// Art scale while paused.
  static const double _pausedScale = 0.88;

  /// The art's scale when a new cover starts fading in.
  static const double _enterScale = 0.92;

  String? _trackId;
  int _index = -1;

  /// 1 when the last change went forward (the text moves left), -1 back.
  double _direction = 1;

  /// Notes the skip direction when the track changes.
  void _track(String id, int index, int length) {
    if (id == _trackId) {
      _index = index;
      return;
    }
    if (_trackId != null) {
      // Last to first is a wrap forward; with two songs it's ambiguous, so
      // only the index decides.
      final wrapped = length > 2 && _index == length - 1 && index == 0;
      _direction = index > _index || wrapped ? 1 : -1;
    }
    _trackId = id;
    _index = index;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final motion = Motion.of(context);
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    final index = ref.watch(
      playerStateProvider.select((s) => s.value?.index ?? -1),
    );
    final length = ref.watch(
      playerStateProvider.select((s) => s.value?.queue.length ?? 0),
    );
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
    );
    if (track == null) {
      return Center(
        child: Text(
          'Nothing playing',
          style: TextStyle(color: colors.text.withAlpha(153), fontSize: 16),
        ),
      );
    }
    _track(track.id, index, length);
    final direction = _direction;
    final trackKey = ValueKey(track.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final side = math.max(
                  0.0,
                  math.min(
                    NowPlayingPage.maxArt,
                    math.min(box.maxWidth, box.maxHeight),
                  ),
                );
                return Center(
                  child: AnimatedScale(
                    scale: playing ? 1 : _pausedScale,
                    duration: motion.standard,
                    curve: Motion.standardCurve,
                    child: Hero(
                      tag: nowPlayingArtHeroTag,
                      child: AnimatedSwitcher(
                        duration: motion.emphasized,
                        switchInCurve: Motion.emphasizedCurve,
                        switchOutCurve: Motion.emphasizedCurve,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            key: const Key('nowPlaying.artChange'),
                            scale: Tween(
                              begin: _enterScale,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: DecoratedBox(
                          key: trackKey,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(colors.radius),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x80000000),
                                blurRadius: 30,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Artwork(
                            key: const Key('nowPlaying.art'),
                            track.artworkRef,
                            size: side,
                            seed: track.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              final shift = width > 0 ? _slide / width : 0.0;
              return AnimatedSwitcher(
                duration: motion.emphasized,
                switchInCurve: Motion.emphasizedCurve,
                switchOutCurve: Motion.emphasizedCurve,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) {
                  // The new title comes in from the skip side, the old one
                  // leaves the other way: both move in the skip direction.
                  final incoming = child.key == trackKey;
                  final from = (incoming ? shift : -shift) * direction;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      key: const Key('nowPlaying.titleSlide'),
                      position: Tween(
                        begin: Offset(from, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: SizedBox(
                  key: trackKey,
                  width: width,
                  child: _TitleAndArtist(
                    title: track.title,
                    artist: track.artist,
                    trackId: track.id,
                    playing: playing,
                  ),
                ),
              );
            },
          ),
          // Drawn a little higher than its slot: the top of its touch band
          // overlaps the space under the artist.
          Transform.translate(
            offset: const Offset(0, -10),
            child: const NowPlayingScrubber(),
          ),
          const NowPlayingControls(),
        ],
      ),
    );
  }
}

/// The playing song's lyrics. On a phone a slim strip above keeps the song
/// and play/pause in reach; the desktop panel has the player bar for that,
/// and uses the desktop's quieter text.
class _LyricsTab extends StatelessWidget {
  const _LyricsTab({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (wide) return const LyricsView(density: LyricsDensity.compact);
    return const Column(
      children: [
        LyricsStrip(),
        Expanded(child: LyricsView()),
      ],
    );
  }
}

class _TitleAndArtist extends StatelessWidget {
  const _TitleAndArtist({
    required this.title,
    required this.artist,
    required this.trackId,
    required this.playing,
  });

  final String title;
  final String artist;
  final String trackId;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Marquee(
          title,
          scroll: playing,
          style: TextStyle(
            color: colors.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text.withAlpha(179),
                  fontSize: 14,
                ),
              ),
            ),
            NowPlayingDownloadedIcon(trackId: trackId),
          ],
        ),
      ],
    );
  }
}

/// How much of the gradient covers the blurred cover, top and bottom.
const double _overBlurTop = 0.55;
const double _overBlurBottom = 0.85;

/// The page's text at the top of the blurred background: the full text and
/// the header's 70 % label.
List<Color> _textOn(SongiesColors colors, Color background) => [
  colors.text,
  Color.alphaBlend(colors.text.withAlpha(179), background),
];

/// The cover that makes [colors]' text hardest to read: white under light
/// text, black under dark text.
Color _worstCover(SongiesColors colors) =>
    contrastRatio(colors.text, Colors.white) >
        contrastRatio(colors.text, Colors.black)
    ? Colors.black
    : Colors.white;

/// The background at the top and bottom of the page over [cover], with
/// [scrim] between the cover and the gradient.
List<Color> _blurredBackground(SongiesColors colors, Color cover, Color scrim) {
  final under = Color.alphaBlend(scrim, cover);
  final top = colors.nowPlayingTop;
  final bottom = colors.nowPlayingBottom;
  return [
    Color.alphaBlend(top.withValues(alpha: top.a * _overBlurTop), under),
    Color.alphaBlend(
      bottom.withValues(alpha: bottom.a * _overBlurBottom),
      under,
    ),
  ];
}

/// The scrim laid over the blurred cover: the least that keeps the text (and
/// the header's label) at 4.5:1 over the worst-case cover (white under light
/// text, black under dark), in the colour opposite to that cover.
Color blurScrim(SongiesColors colors) {
  final cover = _worstCover(colors);
  final shade = cover == Colors.white ? Colors.black : Colors.white;
  for (var step = 0; step <= 20; step++) {
    final scrim = shade.withValues(alpha: step / 20);
    final readable = _blurredBackground(colors, cover, scrim).every(
      (bg) => _textOn(colors, bg).every((t) => contrastRatio(t, bg) >= 4.5),
    );
    if (readable) return scrim;
  }
  return shade;
}

/// The top of the blurred background over the worst-case cover, scrim
/// included.
Color blurWorstCaseTop(SongiesColors colors) =>
    _blurredBackground(colors, _worstCover(colors), blurScrim(colors)).first;

/// The bottom of the blurred background over the worst-case cover, scrim
/// included.
Color blurWorstCaseBottom(SongiesColors colors) =>
    _blurredBackground(colors, _worstCover(colors), blurScrim(colors)).last;
