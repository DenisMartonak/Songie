import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../youtube/yt_import_service.dart';
import '../../youtube/yt_models.dart';
import '../library/import_dialog.dart'
    show importResultMessage, markImportPending;
import '../motion/fade_slide_in.dart';
import '../motion/shimmer.dart';
import '../playlist/hero_backdrop.dart';
import '../playlist/playlist_page.dart' show playlistHeroTop;
import '../widgets/page_snack_bar.dart';
import 'ytm_nav.dart';
import 'ytm_result_tiles.dart';
import 'ytm_song_row.dart';

// Pieces shared by the YouTube Music artist, album and playlist pages.

const double _barHeight = 56;
const double _coverSize = 132;

/// Plays [songs] as a list (radio off), storing them as track rows first:
/// from [from] when given (the shuffle setting is left alone, as when a
/// playlist row is tapped), else from the top with shuffle off, or shuffled
/// from a random song with [shuffle].
Future<void> playYtmList(
  WidgetRef ref,
  List<YtmSong> songs, {
  YtmSong? from,
  bool shuffle = false,
}) async {
  final player = ref.read(playerServiceProvider);
  final tracks = await ref.read(ytTrackStoreProvider).upsertAll(songs);
  if (tracks.isEmpty) return;
  var start = 0;
  if (from != null) {
    start = max(0, tracks.indexWhere((t) => t.ytVideoId == from.videoId));
  } else {
    player.setShuffle(shuffle);
    if (shuffle) start = Random().nextInt(tracks.length);
  }
  await player.playQueue(tracks, startIndex: start);
}

/// The pinned-free top bar of a YouTube Music page: Back when there is a
/// page underneath.
class YtmTopBar extends StatelessWidget {
  const YtmTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return SizedBox(
      height: _barHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Navigator.canPop(context)
            ? Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  tooltip: 'Back',
                  color: colors.text,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
      ),
    );
  }
}

/// A YouTube Music page's hero, in the look of the playlist hero: a gradient
/// from the cover's dominant colour (kept readable by [playlistHeroTop]),
/// the cover (round for an artist), a kind label, the title and a subtitle,
/// then [actions].
class YtmHero extends ConsumerWidget {
  const YtmHero({
    required this.kind,
    required this.title,
    required this.seed,
    this.subtitle,
    this.thumbnailUrl,
    this.circle = false,
    this.actions = const [],
    super.key,
  });

  final String kind;
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;

  /// Placeholder colours for a missing cover.
  final String seed;
  final bool circle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final insets = MediaQuery.paddingOf(context);
    final dominant = ref
        .watch(ytmCoverPaletteProvider(thumbnailUrl))
        .value
        ?.dominant;
    // Without a cover palette, the playlist hero's soft accent wash.
    final heroColor = playlistHeroTop(
      dominant ??
          Color.alphaBlend(
            colors.accent.withValues(alpha: 0.28),
            colors.background,
          ),
      colors,
    );
    final sub = subtitle;
    return Stack(
      children: [
        Positioned.fill(
          child: HeroBackdrop(
            color: heroColor,
            backgroundKey: const Key('ytm.heroBackground'),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            insets.left,
            insets.top,
            insets.right,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YtmTopBar(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: circle ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: circle
                            ? null
                            : BorderRadius.circular(colors.radius + 4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: YtmArtwork(
                        thumbnailUrl,
                        key: const Key('ytm.hero.cover'),
                        seed: seed,
                        size: _coverSize,
                        circle: circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kind,
                            style: TextStyle(
                              color: colors.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          if (sub != null && sub.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The hero's Play button.
class YtmPlayButton extends StatelessWidget {
  const YtmPlayButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const Key('ytm.play'),
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow_rounded),
    label: const Text('Play'),
  );
}

/// A secondary hero action (Shuffle, Radio, Import as playlist), in the
/// theme's text colour so it reads on the hero like its title.
class YtmHeroAction extends StatelessWidget {
  const YtmHeroAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        side: BorderSide(color: colors.text.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Import as playlist: imports [url] with the YouTube import (Plan 2's
/// import and sync), then says how it went, as the import dialog does, and
/// offers to open the playlist.
class YtmImportButton extends ConsumerStatefulWidget {
  const YtmImportButton({required this.url, super.key});

  /// A playlist link `YtImportService.importPlaylist` accepts.
  final String url;

  @override
  ConsumerState<YtmImportButton> createState() => _YtmImportButtonState();
}

class _YtmImportButtonState extends ConsumerState<YtmImportButton> {
  bool _busy = false;

  Future<void> _import() async {
    if (_busy) return;
    final snacks = PageSnackBars.of(context);
    final router = GoRouter.of(context);
    final pending = ref.read(pendingImportsProvider.notifier);
    setState(() => _busy = true);
    Result<ImportResult> result;
    try {
      result = await ref
          .read(ytImportServiceProvider)
          .importPlaylist(widget.url);
    } catch (e, s) {
      AppLog.w('Import failed', e, s);
      result = Err(Failure(FailureKind.unknown, '$e', cause: e));
    }
    if (mounted) setState(() => _busy = false);
    snacks.clear();
    switch (result) {
      case Ok(:final value):
        markImportPending(value, pending);
        snacks.show(
          content: Text(importResultMessage(value)),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => openLibraryPlaylistIn(router, value.playlistId),
          ),
        );
      case Err(:final failure):
        snacks.show(content: Text(ytErrorUserMessage(failure)));
    }
  }

  @override
  Widget build(BuildContext context) => YtmHeroAction(
    key: const Key('ytm.import'),
    icon: Icons.library_add_outlined,
    label: _busy ? 'Importing…' : 'Import as playlist',
    onPressed: _busy ? null : _import,
  );
}

/// A list's songs as rows that enter with [FadeSlideIn]; a tap plays the
/// list from that song ([onTap]). [onBuild] hears each row index as it is
/// built (scrolled into view).
class YtmSongsSliver extends StatelessWidget {
  const YtmSongsSliver({
    required this.songs,
    required this.onTap,
    this.onBuild,
    super.key,
  });

  final List<YtmSong> songs;
  final ValueChanged<YtmSong> onTap;
  final ValueChanged<int>? onBuild;

  @override
  Widget build(BuildContext context) => SliverSafeArea(
    top: false,
    bottom: false,
    sliver: SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) {
        onBuild?.call(i);
        return FadeSlideIn(
          index: i,
          id: 'song.$i.${songs[i].videoId}',
          child: YtmSongRow(song: songs[i], onTap: () => onTap(songs[i])),
        );
      },
    ),
  );
}

/// A section title, in the style of [YtmShelfRow]'s.
class YtmSectionTitle extends StatelessWidget {
  const YtmSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// [value]'s page: [content] once loaded, skeletons while loading, and
/// "Couldn't load" (or "You're offline") with Retry ([onRetry]) on failure.
class YtmAsyncPage<T> extends StatelessWidget {
  const YtmAsyncPage({
    required this.value,
    required this.onRetry,
    required this.content,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T value) content;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v.hasValue && !v.hasError && !v.isLoading) {
      return content(v.requireValue);
    }
    final insets = MediaQuery.paddingOf(context);
    final Widget body = v.hasError && !v.isLoading
        ? YtmLoadProblem(offline: v.error is YtmOffline, onRetry: onRetry)
        : const _Skeleton();
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(insets.left, insets.top, insets.right, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const YtmTopBar(), body],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Shimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SkeletonBox(width: _coverSize, height: _coverSize),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 48, height: 10),
                  SizedBox(height: 8),
                  SkeletonBox(width: 150, height: 24),
                  SizedBox(height: 8),
                  SkeletonBox(width: 96, height: 12),
                ],
              ),
            ],
          ),
        ),
      ),
      YtmSkeletonRows(),
    ],
  );
}

/// `a · b` of the non-empty parts.
String ytmJoin(Iterable<String?> parts) =>
    parts.whereType<String>().where((p) => p.trim().isNotEmpty).join(' · ');
