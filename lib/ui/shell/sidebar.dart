import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../downloads/download_ring.dart';
import '../downloads/downloads_sheet.dart';
import '../motion/equalizer_bars.dart';
import '../motion/motion.dart';
import '../widgets/artwork.dart';
import 'go_tab.dart';

/// The desktop sidebar: Home / Search / Sync devices, the playlist list and a
/// Settings entry. 260 px wide, or a 72 px icon rail when [collapsed]. Rows
/// highlight on hover; the selected row carries an accent bar on its left
/// edge that slides between the rows of its group.
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

  /// Flips the user's collapse preference; null disables the button (the
  /// shell holds the sidebar collapsed to make room for the lyrics panel).
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final path = GoRouterState.of(context).uri.path;
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final current = shell.currentIndex;
    // Settings shares Home's branch but is not Home.
    final onSettings = path == '/settings';
    final homeSelected = current == 0 && !onSettings;
    final playlistSelected = playlists.indexWhere(
      (p) => path.endsWith('/playlist/${p.id}'),
    );
    // On a playlist page only the playlist's row carries the accent bar.
    final onListedPlaylist = playlistSelected >= 0;
    final navSelected = onListedPlaylist
        ? null
        : (homeSelected ? 0 : (current == 1 ? 1 : null));
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
              child: _SelectionTrack(
                name: 'nav',
                selected: navSelected,
                extent: _NavItem.height,
                top: 4,
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
                        onTap: () => goTab(shell, 0),
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
                        onTap: () => goTab(shell, 1),
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
            ),
            const SizedBox(height: 8),
            Expanded(
              child: box(
                child: Column(
                  children: [
                    _SelectionTrack(
                      name: 'library',
                      selected: !collapsed && current == 2 && !onListedPlaylist
                          ? 0
                          : null,
                      extent: _NavItem.height,
                      top: 4,
                      child: Padding(
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
                                  onTap: () => goTab(shell, 2),
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
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DownloadsIndicator(compact: collapsed),
                    ),
                    Expanded(
                      child: _SelectionTrack(
                        name: 'playlists',
                        selected: playlistSelected < 0
                            ? null
                            : playlistSelected,
                        extent: _PlaylistRow.height,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                          itemCount: playlists.length,
                          itemBuilder: (context, i) => _PlaylistRow(
                            playlist: playlists[i],
                            collapsed: collapsed,
                            selected: i == playlistSelected,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            box(
              child: _SelectionTrack(
                name: 'settings',
                selected: onSettings ? 0 : null,
                extent: _NavItem.height,
                top: 4,
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

  static const double height = 40;

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
      height: height,
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
            hoverColor: Colors.transparent,
            onTap: onTap,
            child: _HoverHighlight(enabled: enabled, child: row),
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.collapsed,
    required this.selected,
    required this.colors,
  });

  static const double height = 56;

  final PlaylistSummary playlist;
  final bool collapsed;
  final bool selected;
  final SongiesColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = playlist.source == 'yt' ? 'YouTube' : 'Local';
    final isSource = ref.watch(
      playerStateProvider.select(
        (s) =>
            s.value?.current != null &&
            s.value?.sourcePlaylistId == playlist.id,
      ),
    );
    final playing =
        isSource &&
        ref.watch(playerStateProvider.select((s) => s.value?.playing ?? false));
    Widget art = Artwork(playlist.coverRef, size: 40, seed: playlist.id);
    if (isSource && collapsed) {
      art = Stack(
        children: [
          art,
          Positioned(
            right: 2,
            bottom: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(150),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: EqualizerBars(playing: playing, size: 12),
              ),
            ),
          ),
        ],
      );
    }
    return Tooltip(
      message: collapsed ? playlist.name : '',
      triggerMode: collapsed ? null : TooltipTriggerMode.manual,
      child: InkWell(
        key: Key('sidebar.playlist.${playlist.id}'),
        borderRadius: BorderRadius.circular(colors.radius),
        hoverColor: Colors.transparent,
        onTap: () => context.go('/library/playlist/${playlist.id}'),
        child: _HoverHighlight(
          highlightKey: Key('sidebar.hover.playlist.${playlist.id}'),
          child: Container(
            key: Key('sidebar.fill.playlist.${playlist.id}'),
            height: height,
            decoration: BoxDecoration(
              color: selected ? colors.text.withAlpha(20) : null,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$source · ${playlist.trackCount}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.mutedText,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            DownloadRing(playlistId: playlist.id),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSource) ...[
                    const SizedBox(width: 8),
                    EqualizerBars(playing: playing),
                    const SizedBox(width: 4),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft fill behind [child] while the mouse is over it, fading in and out
/// over [Motion.quick]. Inert when not [enabled].
class _HoverHighlight extends StatefulWidget {
  const _HoverHighlight({
    required this.child,
    this.enabled = true,
    this.highlightKey,
  });

  final Widget child;
  final bool enabled;

  /// The key of the fill (an [AnimatedContainer]).
  final Key? highlightKey;

  @override
  State<_HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<_HoverHighlight> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final lit = _hovered && widget.enabled;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        key: widget.highlightKey,
        duration: Motion.of(context).quick,
        decoration: BoxDecoration(
          color: colors.text.withAlpha(lit ? 13 : 0),
          borderRadius: BorderRadius.circular(colors.radius),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Draws the accent selection bar on the left edge of the [selected] row of
/// a group of equal rows, each [extent] high, the first [top] below the top.
/// When the selection moves within the group the bar slides there over
/// [Motion.standard]; it appears and disappears in place. If the rows
/// scroll, the bar follows them.
class _SelectionTrack extends StatefulWidget {
  const _SelectionTrack({
    required this.name,
    required this.selected,
    required this.extent,
    required this.child,
    this.top = 0,
  });

  static const double _width = 3;

  /// Names the bar's key: `sidebar.selectionBar.<name>`.
  final String name;
  final int? selected;
  final double extent;
  final double top;
  final Widget child;

  @override
  State<_SelectionTrack> createState() => _SelectionTrackState();
}

class _SelectionTrackState extends State<_SelectionTrack>
    with SingleTickerProviderStateMixin {
  /// How far the rows have scrolled.
  final _scroll = ValueNotifier<double>(0);
  late final AnimationController _slide = AnimationController(
    vsync: this,
    value: 1,
  );
  late double _from = (widget.selected ?? 0).toDouble();
  late double _to = _from;

  /// The bar's row position, fractional while sliding.
  double get _position =>
      _from + (_to - _from) * Motion.standardCurve.transform(_slide.value);

  @override
  void didUpdateWidget(_SelectionTrack old) {
    super.didUpdateWidget(old);
    final selected = widget.selected;
    if (selected == null || selected == old.selected) return;
    if (old.selected == null) {
      _from = _to = selected.toDouble();
      _slide.value = 1;
      return;
    }
    _from = _position;
    _to = selected.toDouble();
    _slide
      ..duration = Motion.of(context).standard
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _slide.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) _scroll.value = n.metrics.pixels;
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.depth == 0) _scroll.value = n.metrics.pixels;
          return false;
        },
        child: widget.child,
      ),
    );
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final barHeight = widget.extent / 2;
    // Always a Stack, so the rows (and their scroll position) survive the
    // selection coming and going.
    return Stack(
      children: [
        rows,
        if (widget.selected != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_slide, _scroll]),
                  builder: (context, _) {
                    final offset = _scroll.value;
                    return Stack(
                      children: [
                        Positioned(
                          key: Key('sidebar.selectionBar.${widget.name}'),
                          left: 0,
                          top:
                              widget.top +
                              _position * widget.extent +
                              (widget.extent - barHeight) / 2 -
                              offset,
                          width: _SelectionTrack._width,
                          height: barHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.accent,
                              borderRadius: BorderRadius.circular(
                                _SelectionTrack._width / 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
