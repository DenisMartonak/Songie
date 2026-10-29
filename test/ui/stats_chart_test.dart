// The stats chart: one bar per bucket, scaled to the largest, with a faint
// baseline for empty buckets and a tooltip of the date range and minutes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/stats/stats_chart.dart';

StatsBucket _day(int month, int day, int minutes) => StatsBucket(
  start: DateTime(2026, month, day),
  end: DateTime(2026, month, day + 1),
  heard: Duration(minutes: minutes),
);

/// The last 7 days to Thursday 29 Oct 2026.
final _week = [
  _day(10, 23, 10),
  _day(10, 24, 0),
  _day(10, 25, 20),
  _day(10, 26, 40),
  _day(10, 27, 5),
  _day(10, 28, 0),
  _day(10, 29, 30),
];

Widget _host(Widget chart, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeData(ThemeSpec.builtInDefault),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 800))
        .copyWith(disableAnimations: disableAnimations),
    child: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 160, child: chart)),
    ),
  ),
);

void main() {
  group('formatMinutes', () {
    test('whole minutes with thousands separators', () {
      expect(formatMinutes(const Duration(minutes: 1234)), '1,234 min');
      expect(formatMinutes(const Duration(minutes: 1234567)), '1,234,567 min');
      expect(formatMinutes(const Duration(seconds: 90)), '1 min');
      expect(formatMinutes(const Duration(minutes: 42)), '42 min');
    });

    test('under a minute is 0 min', () {
      expect(formatMinutes(Duration.zero), '0 min');
      expect(formatMinutes(const Duration(seconds: 59)), '0 min');
    });
  });

  group('bucket labels', () {
    test('a day', () {
      expect(
        statsBucketLabel(_day(11, 3, 0), StatsBucketKind.day),
        'Tue 3 Nov',
      );
    });

    test('a 7-day block, within a month and across two', () {
      final within = StatsBucket(
        start: DateTime(2026, 11, 3),
        end: DateTime(2026, 11, 10),
        heard: Duration.zero,
      );
      final across = StatsBucket(
        start: DateTime(2026, 10, 28),
        end: DateTime(2026, 11, 4),
        heard: Duration.zero,
      );
      expect(statsBucketLabel(within, StatsBucketKind.week), '3–9 Nov');
      expect(statsBucketLabel(across, StatsBucketKind.week), '28 Oct–3 Nov');
    });

    test('a month, named from its start', () {
      final partial = StatsBucket(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 30),
        heard: Duration.zero,
      );
      expect(statsBucketLabel(partial, StatsBucketKind.month), 'Oct 2026');
    });
  });

  testWidgets('draws one bar per bucket, scaled to the largest', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(StatsChart(buckets: _week)));

    final bars = find.bySemanticsLabel(RegExp(r'^\w{3} \d+ \w{3}: \d+ min$'));
    expect(bars, findsNWidgets(7));

    final chart = tester.getRect(find.byType(StatsChart));
    final top = tester.getRect(find.bySemanticsLabel('Mon 26 Oct: 40 min'));
    final half = tester.getRect(find.bySemanticsLabel('Sun 25 Oct: 20 min'));
    final empty = tester.getRect(find.bySemanticsLabel('Sat 24 Oct: 0 min'));

    // The largest bucket fills the height; the others are in proportion.
    expect(top.height, moreOrLessEquals(chart.height));
    expect(half.height, moreOrLessEquals(chart.height / 2));
    expect(half.bottom, moreOrLessEquals(chart.bottom));
    // An empty bucket is a 2 px baseline.
    expect(empty.height, 2);
    expect(empty.bottom, moreOrLessEquals(chart.bottom));
    // Oldest on the left.
    final oldest = tester.getRect(find.bySemanticsLabel('Fri 23 Oct: 10 min'));
    expect(oldest.left, lessThan(top.left));
    semantics.dispose();
  });

  testWidgets('the bars use an accent that meets 3:1 on the background', (
    tester,
  ) async {
    await tester.pumpWidget(_host(StatsChart(buckets: _week)));
    final colors = Theme.of(tester.element(find.byType(StatsChart)))
        .extension<SongiesColors>()!;
    final fills = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(StatsChart),
            matching: find.byKey(const Key('stats.bar')),
          ),
        )
        .map((b) => (b.decoration as BoxDecoration).color!)
        .toSet();
    expect(fills, hasLength(1));
    expect(contrastRatio(fills.single, colors.background), greaterThan(3));
  });

  testWidgets('tapping a bar shows its date and minutes', (tester) async {
    await tester.pumpWidget(_host(StatsChart(buckets: _week)));
    expect(find.text('Mon 26 Oct · 40 min'), findsNothing);

    await tester.tap(find.byKey(const Key('stats.bar.3')));
    await tester.pumpAndSettle();
    expect(find.text('Mon 26 Oct · 40 min'), findsOneWidget);

    // Let the tooltip's own timer run out.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('6-month blocks and 12-month months label their bars', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final blocks = [
      for (var i = 0; i < 26; i++)
        StatsBucket(
          start: DateTime(2026, 5, 1 + 7 * i),
          end: DateTime(2026, 5, 8 + 7 * i),
          heard: Duration(minutes: i),
        ),
    ];
    await tester.pumpWidget(_host(StatsChart(buckets: blocks)));
    expect(find.bySemanticsLabel('1–7 May: 0 min'), findsOneWidget);
    expect(find.bySemanticsLabel('29 May–4 Jun: 4 min'), findsOneWidget);

    final months = [
      StatsBucket(
        start: DateTime(2025, 10, 30),
        end: DateTime(2025, 11, 1),
        heard: const Duration(minutes: 3),
      ),
      for (var m = 11; m <= 21; m++)
        StatsBucket(
          start: DateTime(2025, m, 1),
          end: DateTime(2025, m + 1, 1),
          heard: Duration(minutes: m),
        ),
      StatsBucket(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 30),
        heard: const Duration(minutes: 7),
      ),
    ];
    await tester.pumpWidget(_host(StatsChart(buckets: months)));
    expect(find.bySemanticsLabel('Oct 2025: 3 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Jan 2026: 13 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Oct 2026: 7 min'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('with reduced motion nothing animates after a tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(StatsChart(buckets: _week), disableAnimations: true),
    );
    await tester.tap(find.byKey(const Key('stats.bar.3')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mon 26 Oct · 40 min'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('compact draws the bars without tooltips', (tester) async {
    await tester.pumpWidget(_host(StatsChart(buckets: _week, compact: true)));
    expect(find.byKey(const Key('stats.bar')), findsNWidgets(5));
    await tester.tap(find.byType(StatsChart));
    await tester.pumpAndSettle();
    expect(find.textContaining(' · '), findsNothing);
  });

  testWidgets('without a bounded height it takes a default one', (
    tester,
  ) async {
    for (final (compact, height) in [
      (false, StatsChart.defaultHeight),
      (true, StatsChart.compactHeight),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [StatsChart(buckets: _week, compact: compact)],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StatsChart)).height, height);
    }
  });
}
