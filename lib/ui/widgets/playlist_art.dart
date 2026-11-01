import 'package:flutter/material.dart';

import '../../library/favorites.dart';
import '../../theme/app_theme.dart';
import 'artwork.dart';

/// A playlist's cover: a star on the accent colour for the built-in
/// Favorites, its artwork for any other playlist.
class PlaylistArt extends StatelessWidget {
  const PlaylistArt({
    required this.playlistId,
    required this.coverRef,
    required this.size,
    this.radius,
    super.key,
  });

  final String playlistId;
  final String? coverRef;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    if (playlistId != kFavoritesPlaylistId) {
      return Artwork(coverRef, size: size, radius: radius, seed: playlistId);
    }
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? 6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent,
            Color.lerp(colors.accent, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Icon(Icons.star_rounded, size: size * 0.5, color: Colors.white),
    );
  }
}
