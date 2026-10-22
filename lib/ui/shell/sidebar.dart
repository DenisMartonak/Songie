import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/artwork.dart';

/// The desktop sidebar: Home / Search / Sync devices, the playlist list and a
/// Settings entry. 260 px wide, or a 72 px icon rail when [collapsed].
class Sidebar extends ConsumerWidget {
  const Sidebar({
    required this.shell,
    required this.collapsed,
    required this.onToggle,
    super.key,
  });

  static const double expandedWidth = 260;
  static const double collapsedWidth = 72;

  final StatefulNavigationShell shell;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final path = GoRouterState.of(context).uri.path;
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final current = shell.currentIndex;
    // Settings shares Home's branch but is not Home.
    final onSettings = path == '/settings';
    final homeSelected = current == 0 && !onSettings;
    final boxColor = Color.alphaBlend(
      Colors.white.withAlpha(10),
      Color.alphaBlend(Colors.black.withAlpha(90), colors.background),
    );
    final boxRadius = BorderRadius.circular(colors.radius + 4);

    // A Material (not a plain coloured box) so ink effects show above the fill.
    Widget box({required Widget child}) => Material(
      color: boxColor,
      borderRadius: boxRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    return SizedBox(
      key: const Key('sidebar'),
      width: collapsed ? collapsedWidth : expandedWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          children: [
            box(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    _NavItem(
                      key: const Key('sidebar.home'),
                      label: 'Home',
                      collapsed: collapsed,
                      selected: homeSelected,
                      icon: SvgPicture.asset(
                        homeSelected
                            ? 'assets/icons/home_filled.svg'
                            : 'assets/icons/home_outline.svg',
                        width: 22,
                        height: 22,
                        colorFilter: _tint(colors, homeSelected),
                      ),
                      onTap: () => shell.goBranch(0),
                    ),
                    _NavItem(
                      key: const Key('sidebar.search'),
                      label: 'Search',
                      collapsed: collapsed,
                      selected: current == 1,
                      icon: SvgPicture.asset(
                        current == 1
                            ? 'assets/icons/search_bold.svg'
                            : 'assets/icons/search.svg',
                        width: 22,
                        height: 22,
                        colorFilter: _tint(colors, current == 1),
                      ),
                      onTap: () => shell.goBranch(1),
                    ),
                    _NavItem(
                      key: const Key('sidebar.sync'),
                      label: 'Sync devices',
                      tooltip: 'Coming soon',
                      collapsed: collapsed,
                      selected: false,
                      icon: Icon(
                        Icons.sync_rounded,
                        size: 22,
                        color: colors.mutedText,
                      ),
                      onTap: null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: box(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Row(
                        children: [
                          if (!collapsed)
                            Expanded(
                              child: _NavItem(
                                key: const Key('sidebar.library'),
                                label: 'Library',
                                collapsed: false,
                                selected: current == 2,
                                icon: SvgPicture.asset(
                                  current == 2
                                      ? 'assets/icons/library_bold.svg'
                                      : 'assets/icons/library.svg',
                                  width: 22,
                                  height: 22,
                                  colorFilter: _tint(colors, current == 2),
                                ),
                                onTap: () => shell.goBranch(2),
                              ),
                            ),
                          if (collapsed) const Spacer(),
                          IconButton(
                            key: const Key('sidebar.toggle'),
                            tooltip: collapsed
                                ? 'Expand sidebar'
                                : 'Collapse sidebar',
                            iconSize: 22,
                            color: colors.mutedText,
                            icon: Icon(
                              collapsed
                                  ? Icons.chevron_right
                                  : Icons.chevron_left,
                            ),
                            onPressed: onToggle,
                          ),
                          if (collapsed) const Spacer(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        itemCount: playlists.length,
                        itemBuilder: (context, i) => _PlaylistRow(
                          playlist: playlists[i],
                          collapsed: collapsed,
                          selected: path.endsWith('/playlist/${playlists[i].id}'),
                          colors: colors,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            box(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _NavItem(
                  key: const Key('sidebar.settings'),
                  label: 'Settings',
                  collapsed: collapsed,
                  selected: onSettings,
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 22,
                    color: colors.mutedText,
                  ),
                  onTap: () => context.go('/settings'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ColorFilter _tint(SongiesColors colors, bool selected) =>
      ColorFilter.mode(
        selected ? colors.text : colors.mutedText,
        BlendMode.srcIn,
      );
}

/// One icon + label row; icon only (with the label as tooltip) when collapsed.
/// A null [onTap] renders it disabled.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.collapsed,
    required this.selected,
    required this.onTap,
    this.tooltip,
    super.key,
  });

  final String label;
  final Widget icon;
  final bool collapsed;
  final bool selected;
  final VoidCallback? onTap;

  /// Overrides the label as the tooltip.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final enabled = onTap != null;
    final color = selected ? colors.text : colors.mutedText;
    final row = SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          if (!collapsed) const SizedBox(width: 12),
          icon,
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final message = tooltip ?? (collapsed ? label : null);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: message ?? '',
          triggerMode: message == null ? TooltipTriggerMode.manual : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(colors.radius),
            onTap: onTap,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.collapsed,
    required this.selected,
    required this.colors,
  });

  final PlaylistSummary playlist;
  final bool collapsed;
  final bool selected;
  final SongiesColors colors;

  @override
  Widget build(BuildContext context) {
    final source = playlist.source == 'yt' ? 'YouTube' : 'Local';
    final art = Artwork(playlist.coverRef, size: 40, seed: playlist.id);
    return Tooltip(
      message: collapsed ? playlist.name : '',
      triggerMode: collapsed ? null : TooltipTriggerMode.manual,
      child: InkWell(
        key: Key('sidebar.playlist.${playlist.id}'),
        borderRadius: BorderRadius.circular(colors.radius),
        onTap: () => context.go('/library/playlist/${playlist.id}'),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: selected ? Colors.white.withAlpha(20) : null,
            borderRadius: BorderRadius.circular(colors.radius),
          ),
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 8),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              art,
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$source · ${playlist.trackCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.mutedText, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
