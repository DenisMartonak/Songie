import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../motion/motion.dart';

/// A page hero's background: a vertical gradient from [color] (see
/// `playlistHeroTop`, which keeps the hero text readable on it) to the
/// theme's background, easing to a new colour over [Motion.colour]. Shared by
/// the playlist hero and the YouTube Music album, artist and playlist heroes.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({required this.color, this.backgroundKey, super.key});

  final Color color;

  /// The gradient's own key, for tests.
  final Key? backgroundKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: Motion.of(context).colour,
      builder: (context, color, _) => DecoratedBox(
        key: backgroundKey,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color!, colors.background],
          ),
        ),
      ),
    );
  }
}
