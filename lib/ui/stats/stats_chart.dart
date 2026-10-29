import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../stats/stats_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../motion/motion.dart';

/// Whole minutes with thousands separators: "1,234 min"; under a minute,
/// "0 min".
String formatMinutes(Duration d) {
  final digits = '${d.inMinutes}';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out min';
}

/// What one bar of a chart covers.
enum StatsBucketKind {
  /// A day (7 days, 1 month).
  day,

  /// A 7-day block (6 months).
  week,

  /// A calendar month, the oldest possibly partial (12 months).
  month;

  /// The kind of every bar in [buckets]: days when each covers one day,
  /// blocks when each covers seven, otherwise months.
  static StatsBucketKind of(List<StatsBucket> buckets) {
    final spans = buckets.map(_days).toSet();
    if (spans.length == 1 && spans.single == 1) return day;
    if (spans.length == 1 && spans.single == 7) return week;
    return month;
  }
}

/// Calendar days from [b]'s start to its end (DST-proof).
int _days(StatsBucket b) => _date(b.end).difference(_date(b.start)).inDays;

DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A bar's date range: "Tue 3 Nov" for a day, "3–9 Nov" (or
/// "28 Oct–3 Nov") for a 7-day block, "Nov 2026" for a month (named from its
/// start: the newest month ends today).
String statsBucketLabel(StatsBucket b, StatsBucketKind kind) {
  final s = b.start;
  switch (kind) {
    case StatsBucketKind.day:
      return '${_weekdays[s.weekday - 1]} ${s.day} ${_months[s.month - 1]}';
    case StatsBucketKind.week:
      final last = _date(b.end).subtract(const Duration(days: 1));
      final first = s.month == last.month
          ? '${s.day}'
          : '${s.day} ${_months[s.month - 1]}';
      return '$first–${last.day} ${_months[last.month - 1]}';
    case StatsBucketKind.month:
      return '${_months[s.month - 1]} ${s.year}';
  }
}

/// A bar chart of minutes, one bar per bucket (oldest on the left), each as
/// tall as its share of the largest. Empty buckets are a faint 2 px baseline.
/// Bars use the theme's accent, kept at 3:1 on the background.
///
/// Hovering or tapping a bar shows its date range and minutes; [compact]
/// (the Home card) draws the bars only. Given no bounded height it is
/// [defaultHeight] tall ([compactHeight] when compact). Each bar is one semantics node
/// labelled "`range`: N min" whose rect is the bar's.
class StatsChart extends StatelessWidget {
  const StatsChart({required this.buckets, this.compact = false, super.key});

  final List<StatsBucket> buckets;
  final bool compact;

  /// The widest a bar gets.
  static const double _maxBarWidth = 40;

  static const double _baseline = 2;

  /// The height without a bounded one from the parent.
  static const double defaultHeight = 160;
  static const double compactHeight = 32;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final accent = ensureAccentContrast(colors.accent, colors.background);
    final faint = colors.mutedText.withValues(alpha: 0.35);
    final kind = StatsBucketKind.of(buckets);
    final largest = buckets.fold(0, (m, b) => math.max(m, b.heard.inSeconds));
    final gap = compact ? 2.0 : 4.0;
    final motion = Motion.of(context);

    return LayoutBuilder(
      builder: (context, box) {
        // In a scroll view or an unsized column it takes a default height.
        final chartHeight = box.hasBoundedHeight
            ? box.maxHeight
            : (compact ? compactHeight : defaultHeight);
        return SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: _bar(
                    context,
                    index: i,
                    bucket: buckets[i],
                    label: statsBucketLabel(buckets[i], kind),
                    height: largest == 0 || buckets[i].heard.inSeconds == 0
                        ? _baseline
                        : math.max(
                            _baseline,
                            chartHeight * buckets[i].heard.inSeconds / largest,
                          ),
                    gap: gap,
                    fill: buckets[i].heard.inSeconds == 0 ? faint : accent,
                    filled: buckets[i].heard.inSeconds > 0,
                    tooltipStyle: AnimationStyle(
                      curve: Motion.standardCurve,
                      duration: motion.quick,
                      reverseDuration: motion.quick,
                    ),
                    colors: colors,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(
    BuildContext context, {
    required int index,
    required StatsBucket bucket,
    required String label,
    required double height,
    required double gap,
    required Color fill,
    required bool filled,
    required AnimationStyle tooltipStyle,
    required SongiesColors colors,
  }) {
    final minutes = formatMinutes(bucket.heard);
    final radius = Radius.circular(compact ? 2 : 4);
    final bar = Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap / 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxBarWidth),
          child: Semantics(
            container: true,
            label: '$label: $minutes',
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: DecoratedBox(
                key: filled ? const Key('stats.bar') : null,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: filled
                      ? BorderRadius.vertical(top: radius)
                      : BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (compact) return bar;
    return RawTooltip(
      key: ValueKey('stats.bar.$index'),
      // The bar's own semantics label says the same.
      semanticsTooltip: null,
      triggerMode: TooltipTriggerMode.tap,
      animationStyle: tooltipStyle,
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: c.targetSize.height / 2 + 4,
        preferBelow: false,
      ),
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.mutedText.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              '$label · $minutes',
              style: TextStyle(color: colors.text, fontSize: 12),
            ),
          ),
        ),
      ),
      // The whole column takes the tap or hover, not just the bar.
      child: ColoredBox(color: Colors.transparent, child: bar),
    );
  }
}
