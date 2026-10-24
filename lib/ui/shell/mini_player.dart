import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../motion/motion.dart';
import '../now_playing/now_playing_page.dart' show nowPlayingArtHeroTag;
import '../widgets/artwork.dart';

/// The phone's mini-player: 48 high with an 8 px side margin, filled with the
/// theme's mini-player tint and a 2 px accent progress line along the bottom.
/// Renders nothing while the queue is empty. Tapping it opens Now Playing;
/// swiping it left or right skips to the next or previous track, the content
/// following the finger. A track change crossfades the art and slides the
/// titles in from the side the swipe came from.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  static const double height = 48;
  static const double sideMargin = 8;

  /// Space the shell leaves between the mini-player and the nav.
  static const double gapAboveNav = 8;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  /// How far the content must be dragged, or how fast flung, to skip.
  static const double _skipDistance = 64;
  static const double _skipVelocity = 400;

  /// Springs the content back after a drag.
  late final AnimationController _settle = AnimationController(vsync: this)
    ..addListener(_onSettle);

  /// Horizontal offset of the content: follows the finger, then settles.
  double _offset = 0;
  double _settleFrom = 0;

  /// Where the next track's titles enter from: 1 from the right (next),
  /// -1 from the left (previous), 0 for a plain crossfade.
  int _pendingDirection = 0;
  int _direction = 0;
  String? _shownTrackId;

  void _onSettle() => setState(
    () => _offset =
        _settleFrom * (1 - Motion.standardCurve.transform(_settle.value)),
  );

  void _onDragUpdate(DragUpdateDetails details) {
    _settle.stop();
    setState(() => _offset += details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final skip =
        _offset.abs() >= _skipDistance || velocity.abs() >= _skipVelocity;
    if (skip) {
      final next = (velocity.abs() >= _skipVelocity ? velocity : _offset) < 0;
      _pendingDirection = next ? 1 : -1;
      final player = ref.read(playerServiceProvider);
      final before = player.state.current?.id;
      (next ? player.next() : player.previous()).whenComplete(() {
        // No track change (a restart, or the end of the queue): forget the
        // direction so a later, unrelated change doesn't slide from it.
        if (player.state.current?.id == before) _pendingDirection = 0;
      });
    }
    _springBack();
  }

  void _springBack() {
    final duration = Motion.of(context).standard;
    if (duration == Duration.zero) {
      setState(() => _offset = 0);
      return;
    }
    _settleFrom = _offset;
    _settle
      ..duration = duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(
      playerStateProvider.select((s) => s.value?.current),
    );
    if (track == null) return const SizedBox.shrink();
    if (track.id != _shownTrackId) {
      // A swipe's direction applies to the change it caused, once.
      _direction = _shownTrackId == null ? 0 : _pendingDirection;
      _pendingDirection = 0;
      _shownTrackId = track.id;
    }
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final motion = Motion.of(context);
    final playing = ref.watch(
      playerStateProvider.select((s) => s.value?.playing ?? false),
    );
    final trackKey = ValueKey(track.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MiniPlayer.sideMargin),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openNowPlaying(GoRouter.of(context)),
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _springBack,
        child: Container(
          key: const Key('miniPlayer.pill'),
          height: MiniPlayer.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.miniPlayer,
            borderRadius: BorderRadius.circular(colors.radius),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Transform.translate(
                        offset: Offset(_offset, 0),
                        child: Row(
                          children: [
                            Hero(
                              tag: nowPlayingArtHeroTag,
                              // Stays visible while Now Playing is dragged
                              // down.
                              placeholderBuilder: (_, _, child) => child,
                              child: AnimatedSwitcher(
                                duration: motion.emphasized,
                                child: Artwork(
                                  track.artworkRef,
                                  key: trackKey,
                                  size: 34,
                                  radius: 8,
                                  seed: track.id,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: motion.emphasized,
                                switchInCurve: Motion.emphasizedCurve,
                                switchOutCurve: Motion.emphasizedCurve,
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [...previous, ?current],
                                ),
                                transitionBuilder: (child, animation) {
                                  final incoming = child.key == trackKey;
                                  final side =
                                      (incoming ? _direction : -_direction) *
                                      0.3;
                                  return SlideTransition(
                                    position: Tween(
                                      begin: Offset(side, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  );
                                },
                                child: _Titles(
                                  key: trackKey,
                                  title: track.title,
                                  artist: track.artist,
                                  colors: colors,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('miniPlayer.playPause'),
                      tooltip: playing ? 'Pause' : 'Play',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      iconSize: 26,
                      color: colors.text,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: () =>
                          ref.read(playerServiceProvider).togglePlay(),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 0,
                height: 2,
                child: Container(
                  key: const Key('miniPlayer.track'),
                  color: Colors.white.withAlpha(51),
                  alignment: Alignment.centerLeft,
                  child: const _Progress(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The track's title over its artist.
class _Titles extends StatelessWidget {
  const _Titles({
    required this.title,
    required this.artist,
    required this.colors,
    super.key,
  });

  final String title;
  final String artist;
  final SongiesColors colors;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
      Text(
        artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.text.withAlpha(153),
          fontSize: 10,
          height: 1.25,
        ),
      ),
    ],
  );
}

/// The accent fill of the progress line; rebuilds on position changes only.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final fraction = ref.watch(
      playerStateProvider.select((s) {
        final state = s.value;
        final total = state?.duration?.inMilliseconds ?? 0;
        if (state == null || total <= 0) return 0.0;
        return (state.position.inMilliseconds / total).clamp(0.0, 1.0);
      }),
    );
    return FractionallySizedBox(
      widthFactor: fraction,
      child: Container(
        key: const Key('miniPlayer.progress'),
        color: colors.accent,
      ),
    );
  }
}
