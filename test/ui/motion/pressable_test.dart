import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/motion/pressable.dart';

void main() {
  double scale(WidgetTester tester) => tester
      .widget<AnimatedScale>(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;

  /// The scale currently applied (mid-animation too).
  double renderedScale(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(Pressable),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .entry(0, 0);

  Future<void> pump(WidgetTester tester, {VoidCallback? onTap}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: onTap ?? () {},
                child: const SizedBox(
                  width: 100,
                  height: 40,
                  child: Text('Press me'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('scales to 0.97 while pressed and back to 1.0 on release', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);
    expect(renderedScale(tester), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    // Past the tap-down deadline, then the press animation.
    await tester.pump(kPressTimeout);
    await tester.pump();
    await tester.pump(Motion.quick ~/ 2);
    expect(renderedScale(tester), inExclusiveRange(0.97, 1.0));
    await tester.pump(Motion.quick);
    expect(scale(tester), 0.97);
    expect(renderedScale(tester), closeTo(0.97, 1e-6));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scale(tester), 1.0);
    expect(renderedScale(tester), 1.0);
    expect(taps, 1);
  });

  testWidgets('keeps the ink ripple', (tester) async {
    await pump(tester);
    expect(
      find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hovering lightens the surface by 4 %', (tester) async {
    await pump(tester);
    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(InkWell),
      ),
    );
    expect(ink.hoverColor, Colors.white.withValues(alpha: 0.04));
  });
}
