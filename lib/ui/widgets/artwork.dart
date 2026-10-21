import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// Cover art from the art cache. Without a [ref] (or when its file cannot be
/// read) it shows a gradient placeholder whose hues come from
/// `(ref ?? seed).hashCode`, so the same item always gets the same colours.
class Artwork extends ConsumerWidget {
  const Artwork(this.ref, {this.size = 48, this.radius, this.seed, super.key});

  /// Art cache file name, or null for a placeholder.
  final String? ref;
  final double size;

  /// Corner radius; defaults to the theme's.
  final double? radius;

  /// Gives a ref-less item its own placeholder colours (e.g. a track id).
  final String? seed;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final corner =
        radius ?? Theme.of(context).extension<SongiesColors>()!.radius;
    final cover = ref;
    final placeholder = _Placeholder((cover ?? seed).hashCode);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: cover == null
            ? placeholder
            : Image.file(
                widgetRef.watch(artCacheProvider).fileFor(cover),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.hash);

  final int hash;

  @override
  Widget build(BuildContext context) {
    final hue = (hash & 0x7fffffff) % 360;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.65, 0.55).toColor(),
            HSLColor.fromAHSL(
              1,
              ((hue + 55) % 360).toDouble(),
              0.6,
              0.32,
            ).toColor(),
          ],
        ),
      ),
    );
  }
}
