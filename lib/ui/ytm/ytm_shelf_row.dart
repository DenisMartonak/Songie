import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/fade_slide_in.dart';
import '../motion/pressable.dart';
import '../motion/shimmer.dart';
import 'ytm_nav.dart';
import 'ytm_result_tiles.dart';
import 'ytm_song_menu.dart';

/// One YouTube Music shelf (Quick picks, Listen again, new releases, ...):
/// its title over a horizontal row of cards in the style of Home's playlist
/// cards. A song card plays the song with its radio (long press: its ⋯
/// menu); album, artist and playlist cards open their pages. Items of an
/// unknown kind are skipped, and a shelf left empty shows nothing.
class YtmShelfRow extends StatelessWidget {
  const YtmShelfRow({required this.shelf, super.key});

  final YtmShelf shelf;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final items = [
      for (final item in shelf.items)
        if (item is YtmSong ||
            item is YtmAlbum ||
            item is YtmArtist ||
            item is YtmPlaylist)
          item,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            shelf.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: YtmCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => FadeSlideIn(
              index: i,
              id: 'ytm.${shelf.title}.$i',
              child: YtmCard(item: items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// A feed card for a [YtmSong], [YtmAlbum], [YtmArtist] or [YtmPlaylist].
class YtmCard extends ConsumerWidget {
  const YtmCard({required this.item, super.key});

  static const double art = 140;
  static const double height = art + 52;

  final Object item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final (
      String kind,
      String id,
      String? thumb,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) = switch (item) {
      final YtmSong s => (
        'song',
        s.videoId,
        s.thumbnailUrl,
        s.title,
        s.artistLine,
        () => ref.read(radioControllerProvider).playWithRadio(s),
      ),
      final YtmAlbum a => (
        'album',
        a.browseId,
        a.thumbnailUrl,
        a.title,
        _join(['Album', a.artist, a.year]),
        () => context.goYtmAlbum(a.browseId),
      ),
      final YtmArtist a => (
        'artist',
        a.browseId,
        a.thumbnailUrl,
        a.name,
        'Artist',
        () => context.goYtmArtist(a.browseId),
      ),
      final YtmPlaylist p => (
        'playlist',
        p.browseId,
        p.thumbnailUrl,
        p.title,
        _join(['Playlist', p.author]),
        () => context.goYtmPlaylist(p.browseId),
      ),
      _ => throw ArgumentError.value(item, 'item', 'not a feed item'),
    };
    final song = item is YtmSong ? item as YtmSong : null;
    return Material(
      type: MaterialType.transparency,
      child: Pressable(
        key: Key('ytm.card.$kind.$id'),
        borderRadius: BorderRadius.circular(colors.radius),
        onTap: onTap,
        onLongPress: song == null
            ? null
            : () => showYtmSongMenu(context, ref, song),
        child: SizedBox(
          width: art,
          child: Column(
            crossAxisAlignment: kind == 'artist'
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              YtmArtwork(thumb, seed: id, size: art, circle: kind == 'artist'),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.mutedText, fontSize: 11.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shelves while the feed loads.
class YtmShelfSkeleton extends StatelessWidget {
  const YtmShelfSkeleton({this.shelves = 2, super.key});

  final int shelves;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var s = 0; s < shelves; s++) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: SkeletonBox(width: 140, height: 18),
          ),
          SizedBox(
            height: YtmCard.art,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) =>
                  const SkeletonBox(width: YtmCard.art, height: YtmCard.art),
            ),
          ),
        ],
      ],
    ),
  );
}

String _join(Iterable<String?> parts) =>
    parts.whereType<String>().where((p) => p.trim().isNotEmpty).join(' · ');
