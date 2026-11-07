import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../lyrics/lrc.dart';
import '../../lyrics/lyrics.dart';
import '../../lyrics/lyrics_service.dart';
import '../../player/player_service.dart';
import '../../providers.dart';
import '../../remote/remote_controller.dart' show kRemoteUnknownSource;
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../motion/motion.dart';
import '../motion/shimmer.dart';
import '../motion/visible_ticker.dart';
import '../now_playing/now_playing_page.dart'
    show blurWorstCaseBottom, blurWorstCaseTop;

/// How big the lyrics are: [large] fills the phone's Lyrics tab, [compact]
/// suits the desktop side panel.
enum LyricsDensity { large, compact }

/// The playing song's lyrics. Timed lyrics follow playback and seek on tap;
/// plain ones are shown in full. While mounted it also asks the lyrics
/// service to prefetch the song up next, and retries an offline answer once
/// the connection is back. Shows nothing when no song is loaded.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({this.density = LyricsDensity.large, super.key});

  final LyricsDensity density;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  StreamSubscription<NetworkKind>? _network;

  @override
  void initState() {
    super.initState();
    // Lookups happen only while a lyrics view is open: this is the one place
    // that prefetches.
    ref.listenManual<String?>(
      playerViewStateProvider.select((s) => s.value?.upNext?.id),
      (_, next) {
        if (next == null) return;
        final upNext = ref.read(playerViewStateProvider).value?.upNext;
        if (upNext?.source == kRemoteUnknownSource) return;
        ref.read(lyricsServiceProvider).prefetch(upNext);
      },
      fireImmediately: true,
    );
    _network = ref.read(networkStatusProvider).changes.listen(_onNetwork);
  }

  void _onNetwork(NetworkKind kind) {
    if (kind == NetworkKind.offline || !mounted) return;
    final current = ref.read(playerViewStateProvider).value?.current;
    final id = current?.id;
    if (id == null || current?.source == kRemoteUnknownSource) return;
    if (ref.read(lyricsProvider(id)).value is LyricsOffline) {
      ref.invalidate(lyricsProvider(id));
    }
  }

  @override
  void dispose() {
    _network?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Everything is keyed by the current track: a lookup still running for
    // the previous song never reaches the screen.
    final id = ref.watch(
      playerViewStateProvider.select((s) => s.value?.current?.id),
    );
    if (id == null) return const SizedBox.shrink();
    final style = _LyricsStyle.of(context, widget.density);
    // A song this device doesn't have has no lyrics to look up.
    final unknown = ref.watch(
      playerViewStateProvider.select(
        (s) => s.value?.current?.source == kRemoteUnknownSource,
      ),
    );
    if (unknown) {
      return _Message(style: style, text: 'No lyrics found for this song');
    }
    final async = ref.watch(lyricsProvider(id));
    final LyricsState state = async.isLoading
        ? const LyricsLoading()
        : async.value ?? const LyricsNone();
    return switch (state) {
      LyricsLoading() => _Loading(style: style),
      LyricsOffline() => _Message(
        style: style,
        text: 'Lyrics need a connection',
      ),
      LyricsShown(:final lyrics) when lyrics.kind == LyricsKind.synced =>
        _SyncedLyrics(
          key: ValueKey((id, lyrics)),
          lyrics: lyrics,
          style: style,
        ),
      LyricsShown(:final lyrics) when lyrics.kind == LyricsKind.plain =>
        _PlainLyrics(key: ValueKey(id), lyrics: lyrics, style: style),
      _ => _Message(
        style: style,
        text: 'No lyrics found for this song',
        action: TextButton(
          onPressed: () =>
              ref.read(lyricsRetryProvider(id).notifier).searchAgain(),
          child: const Text('Search again'),
        ),
      ),
    };
  }
}

/// The text styles and spacing of one density, from the theme.
class _LyricsStyle {
  const _LyricsStyle({
    required this.colors,
    required this.line,
    required this.current,
    required this.dimmed,
    required this.credit,
    required this.padding,
    required this.lineGap,
  });

  factory _LyricsStyle.of(BuildContext context, LyricsDensity density) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final large = density == LyricsDensity.large;
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return _LyricsStyle(
      colors: colors,
      // Big enough that only a few lines show at once.
      line: base.copyWith(
        fontSize: large ? 34 : 24,
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
      current: colors.text,
      // Both sizes are large text (3:1).
      dimmed: _dimmed(colors, minRatio: 3),
      credit: base.copyWith(
        fontSize: large ? 13 : 12,
        color: colors.mutedText,
        height: 1.4,
      ),
      padding: large ? 24 : 20,
      lineGap: large ? 20 : 14,
    );
  }

  final SongiesColors colors;
  final TextStyle line;
  final Color current;
  final Color dimmed;
  final TextStyle credit;
  final double padding;
  final double lineGap;

  /// [SongiesColors.text] at about 45 %, raised until it reaches [minRatio]
  /// on every background the view can sit on: the panel's, and Now Playing's
  /// (over the blurred cover at its worst when the theme blurs).
  static Color _dimmed(SongiesColors c, {required double minRatio}) {
    final backgrounds = [
      c.background,
      c.surface,
      c.nowPlayingTop,
      c.nowPlayingBottom,
      if (c.blurNowPlaying) ...[blurWorstCaseTop(c), blurWorstCaseBottom(c)],
    ];
    for (var alpha = 0.45; alpha < 1; alpha += 0.05) {
      final dim = c.text.withValues(alpha: alpha);
      if (backgrounds.every(
        (bg) => contrastRatio(Color.alphaBlend(dim, bg), bg) >= minRatio,
      )) {
        return dim;
      }
    }
    return c.text;
  }
}

/// Where the current line sits, as a fraction of the viewport from the top.
const double _anchor = 0.35;

/// How long following stays paused after the user's last scroll.
const Duration _resumeAfter = Duration(seconds: 5);

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lyrics, required this.style, super.key});

  final TrackLyrics lyrics;
  final _LyricsStyle style;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final _scroll = ScrollController();
  // Every line is laid out (a Column, not a lazy list), so each key has a
  // measured rect for any line, wrapped over several rows or not.
  late final List<GlobalKey> _keys = [
    for (final _ in widget.lyrics.lines) GlobalKey(),
  ];
  Timer? _resume;
  bool _following = true;
  bool _placed = false;
  // True while the view's own follow scroll runs, so it is never taken for
  // the user's; [_ownScrollRun] is the latest animated one.
  bool _ownScroll = false;
  Future<void>? _ownScrollRun;
  MotionDurations _motion = MotionDurations.full;

  int _indexAt(PlayerState? s) =>
      currentLineIndex(widget.lyrics.lines, s?.position ?? Duration.zero);

  bool get _playing =>
      ref.read(playerViewStateProvider).value?.playing ?? false;

  int get _current => _indexAt(ref.read(playerViewStateProvider).value);

  @override
  void initState() {
    super.initState();
    ref.listenManual<int>(
      playerViewStateProvider.select((s) => _indexAt(s.value)),
      (_, next) {
        if (_following && _playing) _afterLayout(animate: true);
      },
    );
    ref.listenManual<bool>(
      playerViewStateProvider.select((s) => s.value?.playing ?? false),
      (_, playing) {
        if (playing && _following) _afterLayout(animate: true);
      },
    );
  }

  @override
  void dispose() {
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _afterLayout({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrent(animate: animate);
    });
  }

  /// Puts the current line about [_anchor] from the top; before the first
  /// timed line, back to the start.
  void _scrollToCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final index = _current;
    double target;
    if (index < 0) {
      target = pos.minScrollExtent;
    } else {
      final box = _keys[index].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      target = viewport.getOffsetToReveal(box, _anchor).offset;
    }
    target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((pos.pixels - target).abs() < 0.5) return;
    final duration = _motion.emphasized;
    _ownScroll = true;
    if (!animate || duration == Duration.zero) {
      _scroll.jumpTo(target);
      _ownScroll = false;
    } else {
      final done = _scroll.animateTo(
        target,
        duration: duration,
        curve: Motion.emphasizedCurve,
      );
      // A later follow scroll may have started meanwhile; only it clears.
      void clear() {
        if (identical(_ownScrollRun, done)) _ownScroll = false;
      }

      _ownScrollRun = done;
      done.then((_) => clear(), onError: (_) => clear());
    }
  }

  /// The user scrolled: stop following until [_resumeAfter] has passed
  /// since their last scroll, then glide back (unless playback is paused;
  /// following then resumes when it plays).
  void _userScrolled() {
    _following = false;
    _resume?.cancel();
    _resume = Timer(_resumeAfter, () {
      if (!mounted) return;
      _following = true;
      if (_playing) _scrollToCurrent(animate: true);
    });
  }

  bool _onScroll(ScrollNotification n) {
    // A touch or scrollbar drag carries drag details; a keyboard scroll (or
    // any other scroll the view didn't start) only shows as a start.
    final byUser = switch (n) {
      ScrollStartNotification(:final dragDetails) =>
        dragDetails != null || !_ownScroll,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (byUser) _userScrolled();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _motion = Motion.of(context);
    final style = widget.style;
    final lines = widget.lyrics.lines;
    final current = ref.watch(
      playerViewStateProvider.select((s) => _indexAt(s.value)),
    );
    final playing = ref.watch(
      playerViewStateProvider.select((s) => s.value?.playing ?? false),
    );
    if (!_placed) {
      _placed = true;
      _afterLayout(animate: false);
    }
    // The highlight fades with the standard token, at once under reduced
    // motion or while paused.
    final fade = playing ? _motion.standard : Duration.zero;
    final player = ref.read(playerViewProvider);
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _userScrolled();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            key: const Key('lyrics.synced'),
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              style.padding,
              style.padding,
              style.padding,
              // Room for the last lines to reach the anchor.
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight * (1 - _anchor)
                  : style.padding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < lines.length; i++)
                  KeyedSubtree(
                    key: _keys[i],
                    child: MouseRegion(
                      key: ValueKey('lyrics.line.$i'),
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => player.seek(lines[i].time),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: style.lineGap / 2,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: fade,
                            curve: Motion.standardCurve,
                            style: style.line.copyWith(
                              color: i == current
                                  ? style.current
                                  : style.dimmed,
                            ),
                            child: Text(lines[i].text),
                          ),
                        ),
                      ),
                    ),
                  ),
                _Credit(lyrics: widget.lyrics, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.lyrics, required this.style, super.key});

  final TrackLyrics lyrics;
  final _LyricsStyle style;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('lyrics.plain'),
    padding: EdgeInsets.all(style.padding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(lyrics.text, style: style.line.copyWith(color: style.current)),
        _Credit(lyrics: lyrics, style: style),
      ],
    ),
  );
}

/// "Lyrics from …", then YouTube's own credit line when it gave one.
class _Credit extends StatelessWidget {
  const _Credit({required this.lyrics, required this.style});

  final TrackLyrics lyrics;
  final _LyricsStyle style;

  @override
  Widget build(BuildContext context) {
    final from = switch (lyrics.source) {
      LyricsSource.lrclib => 'Lyrics from LRCLIB',
      LyricsSource.youtube => 'Lyrics from YouTube Music',
      LyricsSource.file => 'Lyrics from the file',
      null => null,
    };
    final credit = lyrics.source == LyricsSource.youtube ? lyrics.credit : null;
    if (from == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: style.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(from, style: style.credit),
          if (credit != null && credit.isNotEmpty)
            Text(credit, style: style.credit),
        ],
      ),
    );
  }
}

/// A few Shimmer bars where the lines will be. The sweep stops while
/// playback is paused, and Shimmer drops it under reduced motion.
class _Loading extends ConsumerWidget {
  const _Loading({required this.style});

  final _LyricsStyle style;

  static const _widths = [0.8, 0.62, 0.9, 0.55, 0.72];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playerViewStateProvider.select((s) => s.value?.playing ?? false),
    );
    final bar = (style.line.fontSize ?? 16) * 0.9;
    return Padding(
      key: const Key('lyrics.loading'),
      padding: EdgeInsets.all(style.padding),
      child: LayoutBuilder(
        builder: (context, constraints) => VisibleTicker(
          active: playing,
          child: Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in _widths)
                  Padding(
                    padding: EdgeInsets.only(bottom: style.lineGap + bar / 2),
                    child: SkeletonBox(
                      width: constraints.maxWidth * w,
                      height: bar,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.style, required this.text, this.action});

  final _LyricsStyle style;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(style.padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: style.credit.copyWith(
              fontSize: (style.line.fontSize ?? 16) * 0.7,
            ),
          ),
          if (action case final action?) ...[const SizedBox(height: 8), action],
        ],
      ),
    ),
  );
}
