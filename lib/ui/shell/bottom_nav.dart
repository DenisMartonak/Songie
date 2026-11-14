import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../motion/motion.dart';

class _Tab {
  const _Tab(this.label, this.inactiveIcon, this.activeIcon);
  final String label;
  final String inactiveIcon;
  final String activeIcon;
}

const _tabs = [
  _Tab('Home', 'assets/icons/home_outline.svg', 'assets/icons/home_filled.svg'),
  _Tab('Search', 'assets/icons/search.svg', 'assets/icons/search_bold.svg'),
  _Tab('Library', 'assets/icons/library.svg', 'assets/icons/library_bold.svg'),
];

/// The phone's tab bar: icon above label. The active tab is white and bold
/// (filled house / 3 px stroke); the others are muted outlines (2 px stroke).
/// A newly active icon bounces once and the label colours animate. The bar
/// fades into the background above it.
class BottomNav extends StatelessWidget {
  const BottomNav(this.index, this.onTap, {super.key});

  static const double height = 64;
  static const double _topPadding = 8;
  static const double _iconSize = 24;
  static const double _labelSize = 10.5;
  static const double _gap = 4;
  static const double _tabWidth = 70;

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Container(
      height: height,
      padding: const EdgeInsets.only(top: _topPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.55, 1],
          colors: [colors.background, colors.background.withAlpha(0)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _TabButton(
              tab: _tabs[i],
              position: i,
              active: i == index,
              colors: colors,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.tab,
    required this.position,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  final _Tab tab;
  final int position;
  final bool active;
  final SongiesColors colors;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton>
    with SingleTickerProviderStateMixin {
  /// One bounce when the tab becomes active: 1.0 -> 1.12 -> 1.0.
  late final AnimationController _bounce = AnimationController(vsync: this);
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 1,
    ),
  ]).animate(_bounce);

  @override
  void didUpdateWidget(_TabButton old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _bounce
        ..duration = Motion.of(context).standard
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final colors = widget.colors;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: BottomNav._tabWidth,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: active ? colors.text : colors.mutedText),
              duration: Motion.of(context).standard,
              builder: (context, color, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    key: Key('nav.bounce.${widget.position}'),
                    scale: _scale,
                    child: SvgPicture.asset(
                      active ? tab.activeIcon : tab.inactiveIcon,
                      key: Key('nav.icon.${widget.position}'),
                      width: BottomNav._iconSize,
                      height: BottomNav._iconSize,
                      colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(height: BottomNav._gap),
                  Text(
                    tab.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: BottomNav._labelSize,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
