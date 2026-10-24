import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/fade_slide_in.dart';
import 'package:songies/ui/motion/motion.dart';

void main() {
  double opacity(WidgetTester tester, String text) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  double dy(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  Widget app(List<Widget> children, {bool disableAnimations = false}) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(body: Column(children: children)),
      );

  testWidgets('index 3 starts after 90 ms and ends 12 px higher', (
    tester,
  ) async {
    await tester.pumpWidget(
      app([const FadeSlideIn(index: 3, child: Text('three'))]),
    );
    expect(opacity(tester, 'three'), 0);
    final start = dy(tester, 'three');

    await tester.pump(const Duration(milliseconds: 85));
    expect(opacity(tester, 'three'), 0);

    await tester.pump(const Duration(milliseconds: 30));
    expect(opacity(tester, 'three'), greaterThan(0));

    await tester.pumpAndSettle();
    expect(opacity(tester, 'three'), 1);
    expect(start - dy(tester, 'three'), closeTo(12, 1e-6));
  });

  testWidgets('the stagger is capped at index 8', (tester) async {
    await tester.pumpWidget(
      app([const FadeSlideIn(index: 20, child: Text('late'))]),
    );
    await tester.pump(const Duration(milliseconds: 8 * 30 + 10));
    expect(opacity(tester, 'late'), greaterThan(0));
    await tester.pump(Motion.standard);
    expect(opacity(tester, 'late'), 1);
  });

  testWidgets('with reduced motion it is visible at once', (tester) async {
    await tester.pumpWidget(
      app([
        const FadeSlideIn(index: 3, child: Text('three')),
      ], disableAnimations: true),
    );
    expect(opacity(tester, 'three'), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('scrolling back to an item does not play it again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemExtent: 100,
            itemCount: 60,
            itemBuilder: (_, i) =>
                FadeSlideIn(index: i, child: Text('item $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(opacity(tester, 'item 0'), 1);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('item 0'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump();
    expect(opacity(tester, 'item 0'), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('items that arrive after the page built still enter, once', (
    tester,
  ) async {
    final items = ValueNotifier<int>(0);
    addTearDown(items.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: items,
            builder: (_, count, _) => ListView.builder(
              itemExtent: 100,
              itemCount: count,
              itemBuilder: (_, i) =>
                  FadeSlideIn(index: i, child: Text('item $i')),
            ),
          ),
        ),
      ),
    );
    // The page sits empty (skeletons, a slow query) for a while.
    await tester.pump(const Duration(seconds: 2));

    items.value = 60;
    await tester.pump();
    expect(opacity(tester, 'item 0'), 0);
    expect(opacity(tester, 'item 3'), 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacity(tester, 'item 0'), greaterThan(0));
    await tester.pumpAndSettle();
    expect(opacity(tester, 'item 3'), 1);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('item 0'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump();
    expect(opacity(tester, 'item 0'), 1);
    expect(opacity(tester, 'item 3'), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('two lists in one scroll view keep apart by id', (tester) async {
    final second = ValueNotifier<bool>(false);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: second,
            builder: (_, show, _) => ListView(
              children: [
                const FadeSlideIn(index: 0, id: 'a0', child: Text('a0')),
                if (show)
                  const FadeSlideIn(index: 0, id: 'b0', child: Text('b0')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    second.value = true;
    await tester.pump();
    expect(opacity(tester, 'b0'), 0);
    await tester.pumpAndSettle();
    expect(opacity(tester, 'b0'), 1);
  });
}
