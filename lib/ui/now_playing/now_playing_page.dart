import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
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
  if (wide) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'Close',
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      child: const NowPlayingPage(),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: const NowPlayingPage(),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// What is playing: big art, title, scrubber and transport controls, with the
/// queue on a second tab. Phone: full screen, swipe down to close. Desktop: a
/// panel with a close button.
class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  /// Largest side of the cover art.
  static const double maxArt = 360;

  /// Drag distance, or fling speed, past which swiping down closes the page.
  static const double _closeDistance = 120;
  static const double _closeVelocity = 700;

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  bool _showQueue = false;
  double _dragged = 0;

  void _close() => context.pop();

  void _onDragEnd(DragEndDetails details) {
    final far = _dragged >= NowPlayingPage._closeDistance;
    final fast =
        (details.primaryVelocity ?? 0) >= NowPlayingPage._closeVelocity;
    _dragged = 0;
    if (far || fast) _close();
  }

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
          child: Material(
            key: const Key('nowPlaying.panel'),
            color: colors.background,
            clipBehavior: Clip.antiAlias,
            elevation: 12,
            borderRadius: BorderRadius.circular(colors.radius + 8),
            child: body,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _dragged = 0,
        onVerticalDragUpdate: (d) => _dragged += d.delta.dy,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => _dragged = 0,
        child: body,
      ),
    );
  }
}

/// The artwork blurred (σ 40) when the theme asks for it, else a glow
/// gradient fading into the background.
class _Background extends ConsumerWidget {
  const _Background();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    if (colors.blurNowPlaying && track != null) {
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
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
            // Keeps the text readable on light covers.
            ColoredBox(color: Colors.black.withAlpha(115)),
          ],
        ),
      );
    }
    return DecoratedBox(
      key: const Key('nowPlaying.glow'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.glow, colors.background],
        ),
      ),
    );
  }
}

/// Art, title and artist, scrubber and controls.
class _PlayerTab extends ConsumerWidget {
  const _PlayerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    if (track == null) {
      return Center(
        child: Text(
          'Nothing playing',
          style: TextStyle(color: colors.text.withAlpha(153), fontSize: 16),
        ),
      );
    }
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
                  child: DecoratedBox(
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
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text.withAlpha(179),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    NowPlayingDownloadedIcon(trackId: track.id),
                  ],
                ),
              ],
            ),
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
