import 'package:flutter/material.dart';

import '../../innertube/ytm_models.dart';
import '../../theme/app_theme.dart';
import '../motion/pressable.dart';
import '../motion/shimmer.dart';
import '../widgets/artwork.dart';
import 'ytm_nav.dart';

/// Cover art from a YouTube Music thumbnail URL, with [Artwork]'s gradient
/// placeholder (seeded by [seed]) while it loads, without a URL, or when it
/// fails. [circle] for artists.
class YtmArtwork extends StatelessWidget {
  const YtmArtwork(
    this.url, {
    required this.seed,
    this.size = 48,
    this.circle = false,
    super.key,
  });

  final String? url;
  final String seed;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final radius = circle ? size / 2 : null;
    final placeholder = Artwork(null, size: size, seed: seed, radius: radius);
    final src = url;
    if (src == null) return placeholder;
    final corner =
        radius ?? Theme.of(context).extension<SongiesColors>()!.radius;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: Image.network(
          src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (_, child, frame, _) =>
              frame == null ? placeholder : child,
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}

/// A result row: art, a title and a muted subtitle, then [trailing].
class YtmTile extends StatelessWidget {
  const YtmTile({
    required this.rowKey,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    super.key,
  });

  /// The [Pressable]'s key, for tests.
  final Key rowKey;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Pressable(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, trailing == null ? 16 : 4, 6),
        child: Row(
          children: [
            art,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.mutedText, fontSize: 12),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

String _join(Iterable<String?> parts) =>
    parts.whereType<String>().where((p) => p.trim().isNotEmpty).join(' · ');

/// An album result; opens the album page.
class YtmAlbumTile extends StatelessWidget {
  const YtmAlbumTile({required this.album, super.key});

  final YtmAlbum album;

  @override
  Widget build(BuildContext context) => YtmTile(
    rowKey: Key('ytm.album.${album.browseId}'),
    art: YtmArtwork(album.thumbnailUrl, seed: album.browseId),
    title: album.title,
    subtitle: _join(['Album', album.artist, album.year]),
    onTap: () => context.goYtmAlbum(album.browseId),
  );
}

/// An artist result; opens the artist page.
class YtmArtistTile extends StatelessWidget {
  const YtmArtistTile({required this.artist, super.key});

  final YtmArtist artist;

  @override
  Widget build(BuildContext context) => YtmTile(
    rowKey: Key('ytm.artist.${artist.browseId}'),
    art: YtmArtwork(artist.thumbnailUrl, seed: artist.browseId, circle: true),
    title: artist.name,
    subtitle: 'Artist',
    onTap: () => context.goYtmArtist(artist.browseId),
  );
}

/// A YouTube Music playlist result; opens the playlist page.
class YtmPlaylistTile extends StatelessWidget {
  const YtmPlaylistTile({required this.playlist, super.key});

  final YtmPlaylist playlist;

  @override
  Widget build(BuildContext context) => YtmTile(
    rowKey: Key('ytm.playlist.${playlist.browseId}'),
    art: YtmArtwork(playlist.thumbnailUrl, seed: playlist.browseId),
    title: playlist.title,
    subtitle: _join(['Playlist', playlist.author]),
    onTap: () => context.goYtmPlaylist(playlist.browseId),
  );
}

/// Placeholder rows while YouTube Music answers.
class YtmSkeletonRows extends StatelessWidget {
  const YtmSkeletonRows({this.count = 6, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const SkeletonBox(width: 48, height: 48),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: (width * 0.45).clamp(80, 260),
                        height: 12,
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        width: (width * 0.3).clamp(60, 180),
                        height: 10,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A YouTube Music part of a page that could not load: "You're offline" or
/// "Couldn't load", each with Retry.
class YtmLoadProblem extends StatelessWidget {
  const YtmLoadProblem({
    required this.offline,
    required this.onRetry,
    super.key,
  });

  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
            size: 40,
            color: colors.mutedText,
          ),
          const SizedBox(height: 8),
          Text(
            offline ? "You're offline" : "Couldn't load",
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.text, fontSize: 15),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('ytm.retry'),
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: colors.text),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
