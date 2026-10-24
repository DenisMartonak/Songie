import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_service.dart';
import '../../../theme/theme_spec.dart';

/// A scaled-down Home tile row, playlist row and mini player drawn with
/// [spec] through a local [Theme], so the app's own theme stays as it is.
/// [fontFamily] is the family [spec] resolves to on this device.
class ThemePreview extends ConsumerWidget {
  const ThemePreview({required this.spec, required this.fontFamily, super.key});

  final ThemeSpec spec;
  final String fontFamily;

  /// The width the preview is laid out at before it is scaled to fit.
  static const double designWidth = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SongiesColors.fromSpec(spec, fontFamily: fontFamily);
    // The app already scales text by the active theme's fontScale; swap it
    // for the edited one.
    final appScale = ref.watch(themeSpecProvider.select((s) => s.fontScale));
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: scaleText(media.textScaler, spec.fontScale / appScale),
      ),
      child: Theme(
        data: buildThemeData(spec, colors: colors),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: designWidth,
            child: _PreviewBody(colors: colors),
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.colors});

  final SongiesColors colors;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(colors.radius);
    final artRadius = BorderRadius.circular(colors.radius / 2);
    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [colors.glow, colors.glow.withValues(alpha: 0)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Good evening',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (i, title) in const [
                    'Liked songs',
                    'Road trip',
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: DecoratedBox(
                        key: const Key('themePreview.tile'),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: radius,
                        ),
                        child: Row(
                          children: [
                            _Art(colors: colors, size: 40, radius: radius),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                key: const Key('themePreview.playlistRow'),
                children: [
                  _Art(colors: colors, size: 40, radius: artRadius),
                  const SizedBox(width: 10),
                  Expanded(child: _TitleArtist(colors: colors)),
                  Icon(Icons.more_horiz_rounded, color: colors.mutedText),
                ],
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                key: const Key('themePreview.miniPlayer'),
                decoration: BoxDecoration(
                  color: colors.miniPlayer,
                  borderRadius: radius,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            _Art(colors: colors, size: 36, radius: artRadius),
                            const SizedBox(width: 10),
                            Expanded(child: _TitleArtist(colors: colors)),
                            Icon(Icons.pause_rounded, color: colors.text),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.4,
                          child: Container(height: 2, color: colors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.colors, required this.size, required this.radius});

  final SongiesColors colors;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.accent, darken(colors.accent)],
      ),
    ),
    child: Icon(
      Icons.music_note_rounded,
      size: size / 2,
      color: colors.background.withValues(alpha: 0.7),
    ),
  );
}

class _TitleArtist extends StatelessWidget {
  const _TitleArtist({required this.colors});

  final SongiesColors colors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Song title',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        'Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.mutedText, fontSize: 12),
      ),
    ],
  );
}
