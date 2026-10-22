import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../shell/adaptive_shell.dart';
import '../widgets/artwork.dart';

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

/// Greeting over an accent glow, quick tiles for the playlists you play most
/// recently, all playlists as cards, and the last tracks played.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const double _maxContentWidth = 960;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final greeting = greetingFor(ref.watch(nowProvider)());
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final recentIds = ref.watch(recentPlaylistIdsProvider).value ?? const [];
    final recentTracks = ref.watch(recentTracksProvider).value ?? const [];
    final isPhone = MediaQuery.sizeOf(context).width < phoneBreakpoint;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final tiles = quickTilePlaylists(playlists, recentIds);

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 220,
          child: DecoratedBox(
            key: const Key('home.glow'),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.5, -1),
                radius: 1.3,
                colors: [colors.glow, colors.glow.withAlpha(0)],
              ),
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
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(greeting: greeting, showSettings: isPhone),
                  ),
                  if (playlists.isEmpty)
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
                        itemBuilder: (_, i) => _QuickTile(playlist: tiles[i]),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: _SectionTitle('Your playlists'),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _PlaylistCard.height,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: playlists.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) =>
                              _PlaylistCard(playlist: playlists[i]),
                        ),
                      ),
                    ),
                  ],
                  if (recentTracks.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionTitle('Recently played'),
                    ),
                    SliverList.builder(
                      itemCount: recentTracks.length,
                      itemBuilder: (_, i) =>
                          _RecentRow(tracks: recentTracks, index: i),
                    ),
                  ],
                  SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
                ],
              ),
            ),
          ),
        ),
      ],
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

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Add a music folder from Your Library to get started.',
        style: TextStyle(color: colors.mutedText, fontSize: 14),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.playlist});

  static const double height = 56;

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      key: Key('home.tile.${playlist.id}'),
      color: colors.text.withAlpha(23),
      borderRadius: BorderRadius.circular(colors.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
            const SizedBox(width: 8),
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
    return InkWell(
      key: Key('home.card.${playlist.id}'),
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
            Text(
              '$source · ${playlist.trackCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.mutedText, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "Recently played" row; tapping plays from it through the rest of the
/// list.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.tracks, required this.index});

  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = tracks[index];
    return InkWell(
      key: Key('home.recent.${track.id}'),
      onTap: () =>
          ref.read(playerServiceProvider).playQueue(tracks, startIndex: index),
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
          ],
        ),
      ),
    );
  }
}
