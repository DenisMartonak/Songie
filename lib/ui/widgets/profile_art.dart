import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'artwork.dart';

/// A picture from [url] (a photo or YouTube cover), else the local cover
/// [artworkRef], else the seeded placeholder; the placeholder also shows
/// while the image loads and when it fails.
class ProfileArt extends StatelessWidget {
  const ProfileArt({
    this.url,
    this.artworkRef,
    required this.seed,
    required this.size,
    this.radius,
    super.key,
  });

  final String? url;
  final String? artworkRef;
  final String seed;
  final double size;

  /// Corner radius; defaults to the theme's.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final link = url;
    final local = Artwork(artworkRef, size: size, radius: radius, seed: seed);
    if (link == null) return local;
    final placeholder = Artwork(null, size: size, radius: radius, seed: seed);
    final corner =
        radius ?? Theme.of(context).extension<SongiesColors>()!.radius;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: Image.network(
          link,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (_, child, frame, sync) =>
              frame == null && !sync ? placeholder : child,
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}
