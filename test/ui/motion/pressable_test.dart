import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/ui/motion/pressable.dart';

void main() {
  /// The scale currently applied (mid-animation too).
  double scale(WidgetTester tester) => tester
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

  Finder ink() => find.descendant(
    of: find.byType(Pressable),
    matching: find.byType(InkWell),
  );

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTap,
    bool enabled = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(
            onTap: enabled ? onTap ?? () {} : null,
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
    expect(scale(tester), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    // The press shows from pointer down, over Motion.quick.
    await tester.pump();
    await tester.pump(Motion.quick ~/ 2);
    expect(scale(tester), inExclusiveRange(0.97, 1.0));
    await tester.pump(Motion.quick ~/ 2);
    await tester.pump(kPressTimeout);
    expect(scale(tester), closeTo(0.97, 1e-6));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scale(tester), 1.0);
    expect(taps, 1);
  });

  testWidgets('a quick tap still shows the press', (tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);
    // Down and up with no frame in between.
    await tester.tap(find.byType(Pressable));
    var lowest = 1.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = scale(tester);
      if (s < lowest) lowest = s;
    }
    expect(lowest, lessThan(1.0));
    await tester.pumpAndSettle();
    expect(scale(tester), 1.0);
    expect(taps, 1);
  });

  testWidgets('a press that turns into a scroll lets go', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                Pressable(
                  onTap: () {},
                  child: SizedBox(height: 60, child: Text('row $i')),
                ),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 2')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -200));
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('row 2'),
      matching: find.byType(Pressable),
    );
    final transform = tester.widget<Transform>(
      find.descendant(of: row, matching: find.byType(Transform)).first,
    );
    expect(transform.transform.entry(0, 0), 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the ink ripple', (tester) async {
    await pump(tester);
    expect(ink(), findsOneWidget);
  });

  testWidgets('hovering lightens the surface by 4 %', (tester) async {
    await pump(tester);
    expect(
      tester.widget<InkWell>(ink()).hoverColor,
      Colors.white.withValues(alpha: 0.04),
    );
  });

  testWidgets('the hover highlight comes from the theme text (light themes)', (
    tester,
  ) async {
    final light = ThemeSpec.builtInDefault.copyWith(
      base: 'light',
      background: const Color(0xFFF5F5F5),
      surface: const Color(0xFFFFFFFF),
      text: const Color(0xFF121212),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(light),
        home: Scaffold(
          body: Center(
            child: Pressable(onTap: () {}, child: const Text('Press me')),
          ),
        ),
      ),
    );
    expect(
      tester.widget<InkWell>(ink()).hoverColor,
      const Color(0xFF121212).withValues(alpha: 0.04),
    );
  });

  testWidgets('with no callbacks it is inert', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, enabled: false);

    final inkWell = tester.widget<InkWell>(ink());
    expect(inkWell.onTapDown, isNull);
    expect(inkWell.onTapUp, isNull);
    expect(inkWell.onTapCancel, isNull);
    expect(
      tester.getSemantics(find.text('Press me')),
      isNot(isSemantics(isFocusable: true)),
    );
    expect(
      tester.getSemantics(find.text('Press me')),
      isNot(isSemantics(isEnabled: true)),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    await tester.pump(Motion.quick);
    expect(scale(tester), 1.0);
    expect(tester.hasRunningAnimations, isFalse);
    await gesture.up();
    semantics.dispose();
  });

  testWidgets('a right-click reports where it happened, without a tap', (
    tester,
  ) async {
    var taps = 0;
    Offset? at;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () => taps++,
              onSecondaryTapUp: (d) => at = d.globalPosition,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(Pressable));
    final gesture = await tester.startGesture(
      centre,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(Motion.quick ~/ 2);
    // A right-click doesn't dip the row like a press.
    expect(scale(tester), 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(at, centre);
    expect(taps, 0);
  });

  testWidgets('a right-click alone makes it interactive', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onSecondaryTapUp: (_) => clicks++,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(
      tester.getCenter(find.byType(Pressable)),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(clicks, 1);
  });
}
