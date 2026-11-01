import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../innertube/ytm_models.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/cover_palette.dart';
import '../downloads/download_ring.dart';
import '../library/add_folder_flow.dart';
import '../library/import_dialog.dart';
import '../motion/equalizer_bars.dart';
import '../motion/fade_slide_in.dart';
import '../motion/motion.dart';
import '../motion/pressable.dart';
import '../motion/shimmer.dart';
import '../shell/adaptive_shell.dart';
import '../stats/listening_card.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../ytm/consent_sheet.dart';
import '../ytm/ytm_result_tiles.dart';
import '../ytm/ytm_shelf_row.dart';
import '../widgets/favorite_star.dart';

/// "Good morning" from 05:00, "Good afternoon" from 12:00, "Good evening" from
/// 18:00 until 05:00.
String greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// At most this many quick tiles.
const int _maxTiles = 6;

/// The playlists for the quick tiles: the most recently played ones first
/// (distinct, still existing), filled up with the rest in alphabetical order.
/// [all] is already alphabetical.
List<PlaylistSummary> quickTilePlaylists(
  List<PlaylistSummary> all,
  List<String> recentIds,
) {
  final byId = {for (final p in all) p.id: p};
  final tiles = <PlaylistSummary>[];
  for (final id in recentIds) {
    final playlist = byId[id];
    if (playlist != null && !tiles.contains(playlist)) tiles.add(playlist);
    if (tiles.length == _maxTiles) return tiles;
  }
  for (final playlist in all) {
    if (tiles.length == _maxTiles) break;
    if (!tiles.contains(playlist)) tiles.add(playlist);
  }
  return tiles;
}

/// Home's header glow: the theme's [glow] tinted towards the vibrant colour
/// of the last played cover ([palette]), at the glow's own strength. Without
/// a palette, or for greyscale art, it is the theme's glow.
Color homeGlowColor(Color glow, CoverPalette? palette) {
  if (palette == null || palette.isFallback) return glow;
  return Color.lerp(glow, palette.vibrant.withValues(alpha: glow.a), 0.6)!;
}

/// Greeting over a glow tinted by the last played cover, quick tiles for the
/// playlists you play most recently, all playlists as cards, and the last
/// tracks played; then the YouTube Music feed rows (pull to refresh reloads
/// them). Asks for YouTube's consent when YouTube does ([ConsentListener]).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const double _maxContentWidth = 960;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final greeting = greetingFor(ref.watch(nowProvider)());
    final playlistsAsync = ref.watch(playlistsProvider);
    // Skeletons only while loading: an error shows the empty state.
    final loading = !playlistsAsync.hasValue && !playlistsAsync.hasError;
    final playlists = playlistsAsync.value ?? const <PlaylistSummary>[];
    final recentIds = ref.watch(recentPlaylistIdsProvider).value ?? const [];
    final recentTracks = ref.watch(recentTracksProvider).value ?? const [];
    final lastPlayed = recentTracks.firstOrNull;
    final palette = ref.watch(artPaletteProvider(lastPlayed?.artworkRef)).value;
    final isPhone = MediaQuery.sizeOf(context).width < phoneBreakpoint;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final tiles = quickTilePlaylists(playlists, recentIds);
    final feed = ref.watch(ytmHomeProvider);

    return ConsentListener(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 220,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: homeGlowColor(colors.glow, palette)),
              duration: Motion.of(context).colour,
              builder: (context, glow, child) => DecoratedBox(
                key: const Key('home.glow'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.5, -1),
                    radius: 1.3,
                    colors: [glow!, glow.withAlpha(0)],
                  ),
                ),
                child: child,
              ),
              // Fades the glow out before the box ends, so it has no edge.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.3, 1],
                    colors: [colors.background.withAlpha(0), colors.background],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: RefreshIndicator(
                  key: const Key('home.refresh'),
                  // Errors show in the feed area; the spinner just ends.
                  onRefresh: () => ref
                      .refresh(ytmHomeProvider.future)
                      .then<void>((_) {}, onError: (Object _) {}),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _Header(
                          greeting: greeting,
                          showSettings: isPhone,
                        ),
                      ),
                      if (loading)
                        const SliverToBoxAdapter(child: _SkeletonTiles())
                      else if (playlists.isEmpty)
                        const SliverToBoxAdapter(child: _EmptyHome())
                      else ...[
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  mainAxisExtent: _QuickTile.height,
                                ),
                            itemCount: tiles.length,
                            itemBuilder: (_, i) => FadeSlideIn(
                              index: i,
                              id: 'tile.${tiles[i].id}',
                              child: _QuickTile(playlist: tiles[i]),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: ListeningCard()),
                        const SliverToBoxAdapter(
                          child: _SectionTitle('Your playlists'),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: _PlaylistCard.height,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: playlists.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) => FadeSlideIn(
                                index: i,
                                id: 'card.${playlists[i].id}',
                                child: _PlaylistCard(playlist: playlists[i]),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!loading && playlists.isEmpty)
                        const SliverToBoxAdapter(child: ListeningCard()),
                      if (recentTracks.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _SectionTitle('Recently played'),
                        ),
                        SliverList.builder(
                          itemCount: recentTracks.length,
                          itemBuilder: (_, i) => FadeSlideIn(
                            index: i,
                            id: 'recent.${recentTracks[i].id}',
                            child: _RecentRow(tracks: recentTracks, index: i),
                          ),
                        ),
                      ],
                      ..._feedSlivers(feed, ref),
                      SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The feed area: skeleton shelves while loading, the shelves, or (when
  /// it failed) an offline note or Couldn't load with Retry.
  static List<Widget> _feedSlivers(AsyncValue<YtmHome> feed, WidgetRef ref) {
    if (feed.hasError && !feed.isLoading) {
      if (feed.error is YtmOffline) {
        return const [SliverToBoxAdapter(child: _FeedOffline())];
      }
      return [
        SliverToBoxAdapter(
          child: YtmLoadProblem(
            offline: false,
            onRetry: () => ref.invalidate(ytmHomeProvider),
          ),
        ),
      ];
    }
    final home = feed.value;
    if (home == null) {
      return const [
        SliverToBoxAdapter(
          child: YtmShelfSkeleton(key: Key('home.feed.skeleton')),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: home.shelves.length,
        itemBuilder: (_, i) =>
            YtmShelfRow(key: Key('home.shelf.$i'), shelf: home.shelves[i]),
      ),
    ];
  }
}

/// Offline: the feed area says so, quietly; the library part stays.
class _FeedOffline extends StatelessWidget {
  const _FeedOffline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      key: const Key('home.feed.offline'),
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 20, color: colors.mutedText),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Connect to see recommendations',
              style: TextStyle(color: colors.mutedText, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholders for the quick tiles until the playlists have loaded.
class _SkeletonTiles extends StatelessWidget {
  const _SkeletonTiles();

  @override
  Widget build(BuildContext context) {
    Widget tile() => const Expanded(
      child: SkeletonBox(width: double.infinity, height: _QuickTile.height),
    );
    return Padding(
      key: const Key('home.skeleton'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Shimmer(
        child: Column(
          children: [
            for (var row = 0; row < _maxTiles ~/ 2; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [tile(), const SizedBox(width: 8), tile()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.showSettings});

  final String greeting;
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              greeting,
              style: TextStyle(
                color: colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showSettings)
            IconButton(
              key: const Key('home.settings'),
              tooltip: 'Settings',
              color: colors.text,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
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

/// No playlists yet: the two ways to get music in.
class _EmptyHome extends ConsumerWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
      child: Column(
        children: [
          Icon(Icons.library_music_rounded, size: 56, color: colors.mutedText),
          const SizedBox(height: 16),
          Text(
            'Your music lives here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => showImportDialog(context),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Import a YouTube playlist'),
              ),
              OutlinedButton.icon(
                onPressed: () => addMusicFolder(context, ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add music folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends ConsumerWidget {
  const _QuickTile({required this.playlist});

  static const double height = 56;

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Whether this playlist is the one playing, and whether it plays.
    final (source, playing) = ref.watch(
      playerStateProvider.select((s) {
        final state = s.value;
        return (
          state?.current == null ? null : state?.sourcePlaylistId,
          state?.playing ?? false,
        );
      }),
    );
    return Material(
      key: Key('home.tile.${playlist.id}'),
      color: colors.text.withAlpha(23),
      borderRadius: BorderRadius.circular(colors.radius),
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        onTap: () => context.push('/home/playlist/${playlist.id}'),
        child: Row(
          children: [
            Artwork(
              playlist.coverRef,
              size: height,
              radius: 0,
              seed: playlist.id,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (source == playlist.id) ...[
              const SizedBox(width: 8),
              EqualizerBars(playing: playing),
            ],
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  static const double art = 140;
  static const double height = art + 52;

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final source = playlist.source == 'yt' ? 'YouTube' : 'Local';
    return Material(
      key: Key('home.card.${playlist.id}'),
      type: MaterialType.transparency,
      child: Pressable(
        borderRadius: BorderRadius.circular(colors.radius),
        onTap: () => context.push('/home/playlist/${playlist.id}'),
        child: SizedBox(
          width: art,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(playlist.coverRef, size: art, seed: playlist.id),
              const SizedBox(height: 8),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '$source · ${playlist.trackCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.mutedText, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  DownloadRing(playlistId: playlist.id),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "Recently played" row; tapping plays from it through the rest of the
/// list, long-press or right-click opens the song menu.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.tracks, required this.index});

  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = tracks[index];
    final menu = songMenuOpeners(context, ref, MenuSong.track(track));
    return Pressable(
      key: Key('home.recent.${track.id}'),
      onTap: () =>
          ref.read(playerServiceProvider).playQueue(tracks, startIndex: index),
      onLongPress: menu.onLongPress,
      onSecondaryTapUp: menu.onSecondaryTapUp,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Artwork(track.artworkRef, size: 44, seed: track.id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
            FavoriteStar(song: MenuSong.track(track)),
          ],
        ),
      ),
    );
  }
}
