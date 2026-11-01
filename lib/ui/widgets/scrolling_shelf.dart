import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;

/// A titled, horizontally scrolling row of cards. On wide layouts the title
/// has ‹ › arrows that scroll it a page at a time (a mouse can't swipe);
/// phones swipe and show none.
class ScrollingShelf extends StatefulWidget {
  const ScrollingShelf({
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
    super.key,
  });

  final String title;

  /// The row's height (the cards').
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;

  @override
  State<ScrollingShelf> createState() => _ScrollingShelfState();
}

class _ScrollingShelfState extends State<ScrollingShelf> {
  final _scroll = ScrollController();
  bool _atStart = true;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final atStart = p.pixels <= p.minScrollExtent + 1;
    final atEnd = p.pixels >= p.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.85).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final wide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;
    Widget arrow(String which, IconData icon, int direction, bool off) =>
        IconButton(
          key: Key('shelf.${widget.title}.$which'),
          tooltip: which == 'prev' ? 'Scroll back' : 'Scroll on',
          color: colors.text,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
          onPressed: off ? null : () => _page(direction),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, wide ? 16 : 24, wide ? 8 : 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (wide) ...[
                arrow('prev', Icons.chevron_left_rounded, -1, _atStart),
                arrow('next', Icons.chevron_right_rounded, 1, _atEnd),
              ],
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ],
    );
  }
}
