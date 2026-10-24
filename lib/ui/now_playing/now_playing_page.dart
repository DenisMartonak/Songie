import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/marquee.dart';
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
Page<void> nowPlayingPage(BuildContext context, GoRouterState state) {
  final wide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;
  final motion = Motion.of(context);
  if (wide) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'Close',
      transitionDuration: motion.standard,
      reverseTransitionDuration: motion.standard,
      child: const NowPlayingPage(),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Motion.standardCurve,
        ),
        child: child,
      ),
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: motion.emphasized,
    reverseTransitionDuration: motion.emphasized,
    child: const NowPlayingPage(),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Motion.emphasizedCurve),
      ),
      child: child,
    ),
  );
}

/// The [Hero] tag shared by the mini-player / player-bar artwork and the Now
/// Playing artwork, so the cover flies between them.
const String nowPlayingArtHeroTag = 'np-art';

/// What is playing: big art, title, scrubber and transport controls, with the
/// queue on a second tab. Phone: full screen; desktop: a panel with a close
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
  bool _showQueue = false;

  /// How far (px) the page has been dragged down.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  /// The dragged area (the page, or the desktop panel), to measure its height.
  final GlobalKey _dragArea = GlobalKey();

  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    context.pop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    _drag.value = math.max(0, _drag.value + details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing) return;
    final height = _dragArea.currentContext?.size?.height ?? double.infinity;
    final far = _drag.value >= height * NowPlayingPage.closeFraction;
    final fast = (details.primaryVelocity ?? 0) >= NowPlayingPage.closeVelocity;
    if (far || fast) {
      // The route's exit transition carries the page on from where it is.
      _close();
    } else {
      _springBack();
    }
  }

  void _springBack() => _drag.animateTo(
    0,
    duration: Motion.of(context).standard,
    curve: Motion.standardCurve,
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  /// [child] moved by the drag, with the drag gestures on it.
  Widget _draggable(Widget child) => GestureDetector(
    key: _dragArea,
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) => _drag.stop(),
    onVerticalDragUpdate: _onDragUpdate,
    onVerticalDragEnd: _onDragEnd,
    onVerticalDragCancel: () {
      if (!_closing) _springBack();
    },
    child: AnimatedBuilder(
      animation: _drag,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _drag.value), child: child),
      child: KeyedSubtree(key: const Key('nowPlaying.page'), child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final wide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;

    final body = Stack(
      children: [
        const Positioned.fill(child: _Background()),
        SafeArea(
          child: Column(
            children: [
              NowPlayingHeader(wide: wide, onClose: _close),
              NowPlayingTabs(
                showQueue: _showQueue,
                onChanged: (queue) => setState(() => _showQueue = queue),
              ),
              Expanded(
                child: _showQueue
                    ? const NowPlayingQueue()
                    : const _PlayerTab(),
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
          child: _draggable(
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
      );
    }

    return _draggable(Scaffold(backgroundColor: colors.background, body: body));
  }
}

/// The theme's `nowPlayingTop → nowPlayingBottom` gradient, over the cover
/// blurred (σ 40) when the theme asks for it.
class _Background extends StatelessWidget {
  const _Background();

  /// How much of the gradient covers the blurred cover, top and bottom.
  static const double _overBlurTop = 0.55;
  static const double _overBlurBottom = 0.85;

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
        if (blur) const _BlurredCover(),
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
      final wrapped = _index == length - 1 && index == 0;
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
          const SizedBox(height: 8),
          const NowPlayingScrubber(),
          const SizedBox(height: 8),
          const NowPlayingControls(),
        ],
      ),
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
