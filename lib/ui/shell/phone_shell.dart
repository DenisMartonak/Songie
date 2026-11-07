import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../downloads/downloads_banner.dart';
import '../downloads/downloads_sheet.dart';
import '../island/island_host.dart';
import 'bottom_nav.dart';
import 'go_tab.dart';
import 'mini_player.dart';
import 'player_error_islands.dart';

/// Phone layout: the current page with the mini-player and bottom nav floating
/// over its bottom edge. Pages get the overlay's height as bottom padding
/// (through `MediaQuery`) so scrolling lists clear it.
class PhoneShell extends ConsumerWidget {
  const PhoneShell(this.shell, {super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Also while another device is controlled, whatever its queue: the mini
    // player then says which device ("Connecting to …", "Playing on …").
    final hasMini =
        ref.watch(remoteLinkProvider.select((l) => l.value != null)) ||
        ref.watch(playerStateProvider.select((s) => s.value?.current != null));
    final downloading = ref.watch(downloadsActiveProvider);
    final banner = ref.watch(downloadsBannerVisibleProvider);
    final media = MediaQuery.of(context);
    // The keyboard replaces the bars instead of pushing them up.
    final keyboardOpen = media.viewInsets.bottom > 0;
    final bottomInset = media.viewPadding.bottom;

    final overlayHeight = keyboardOpen
        ? 0.0
        : BottomNav.height +
              bottomInset +
              (hasMini ? MiniPlayer.height + MiniPlayer.gapAboveNav : 0) +
              (downloading ? DownloadsIndicator.height : 0) +
              (banner ? DownloadsBanner.height : 0);

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
              child: PlayerErrorIslands(child: shell),
            ),
          ),
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IslandAnchor(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (banner) const DownloadsBanner(),
                    if (downloading)
                      ColoredBox(
                        color: colors.background,
                        child: const DownloadsIndicator(),
                      ),
                    if (hasMini) ...[
                      const MiniPlayer(),
                      const SizedBox(height: MiniPlayer.gapAboveNav),
                    ],
                    BottomNav(shell.currentIndex, (i) => goTab(shell, i)),
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
            ),
        ],
      ),
    );
  }
}
