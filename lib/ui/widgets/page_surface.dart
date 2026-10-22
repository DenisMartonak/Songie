import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A routed page's own Material. Ink (tap ripples) paints on the nearest
/// Material above it; without one per page that is the shell's Scaffold, which
/// lives below the page Navigator, so a ripple outlives the page it started on
/// and shows through the next one.
class PageSurface extends StatelessWidget {
  const PageSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).extension<SongiesColors>()!.background,
    child: child,
  );
}
