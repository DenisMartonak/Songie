import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'bottom_nav.dart';
import 'mini_player.dart';
import 'player_error_snacks.dart';

/// Phone layout: the current page with the mini-player and bottom nav floating
/// over its bottom edge. Pages get the overlay's height as bottom padding
/// (through `MediaQuery`) so scrolling lists clear it.
class PhoneShell extends ConsumerWidget {
  const PhoneShell(this.shell, {super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final hasMini = ref.watch(
      playerStateProvider.select((s) => s.value?.current != null),
    );
    final media = MediaQuery.of(context);
    // The keyboard replaces the bars instead of pushing them up.
    final keyboardOpen = media.viewInsets.bottom > 0;
    final bottomInset = media.viewPadding.bottom;

    final overlayHeight = keyboardOpen
        ? 0.0
        : BottomNav.height +
              bottomInset +
              (hasMini ? MiniPlayer.height + MiniPlayer.gapAboveNav : 0);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(
                  bottom: media.padding.bottom + overlayHeight,
                ),
              ),
              child: PlayerErrorSnacks(child: shell),
            ),
          ),
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasMini) ...[
                    const MiniPlayer(),
                    const SizedBox(height: MiniPlayer.gapAboveNav),
                  ],
                  BottomNav(
                    shell.currentIndex,
                    (i) => shell.goBranch(
                      i,
                      initialLocation: i == shell.currentIndex,
                    ),
                  ),
                  ColoredBox(
                    color: colors.background,
                    child: SizedBox(
                      height: bottomInset,
                      width: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
