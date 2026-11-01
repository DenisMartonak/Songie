import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/widgets/scrolling_shelf.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        home: Scaffold(
          body: ScrollingShelf(
            title: 'Mixes',
            height: 100,
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(width: 150, child: Text('card $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  IconButton button(WidgetTester tester, String which) =>
      tester.widget<IconButton>(find.byKey(Key('shelf.Mixes.$which')));

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position
      .pixels;

  testWidgets('wide: arrows scroll the shelf a page at a time', (tester) async {
    await pump(tester, 1000);
    expect(find.text('Mixes'), findsOneWidget);
    expect(button(tester, 'prev').onPressed, isNull);
    expect(button(tester, 'next').onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('shelf.Mixes.next')));
    await tester.pumpAndSettle();
    expect(offset(tester), greaterThan(500));
    expect(button(tester, 'prev').onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('shelf.Mixes.prev')));
    await tester.pumpAndSettle();
    expect(offset(tester), 0);
  });

  testWidgets('at the end, next is off', (tester) async {
    await pump(tester, 1000);
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('shelf.Mixes.next')));
      await tester.pumpAndSettle();
    }
    expect(button(tester, 'next').onPressed, isNull);
  });

  testWidgets('phone: no arrows, swipe instead', (tester) async {
    await pump(tester, 400);
    expect(find.byKey(const Key('shelf.Mixes.next')), findsNothing);
  });
}
