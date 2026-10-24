import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/motion.dart';

void main() {
  Future<MotionDurations> motionIn(
    WidgetTester tester, {
    bool setting = false,
    bool disableAnimations = false,
  }) async {
    late MotionDurations motion;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reduceMotionProvider.overrideWithValue(setting)],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: MotionScope(
            child: Builder(
              builder: (context) {
                motion = Motion.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return motion;
  }

  testWidgets('Motion.of gives the tokens by default', (tester) async {
    final m = await motionIn(tester);
    expect(m.reduced, isFalse);
    expect(m.quick, Motion.quick);
    expect(m.standard, Motion.standard);
    expect(m.emphasized, Motion.emphasized);
    expect(m.colour, Motion.colour);
  });

  for (final (name, setting, disable) in [
    ('the setting', true, false),
    ('the system "remove animations"', false, true),
  ]) {
    testWidgets('$name makes every token zero', (tester) async {
      final m = await motionIn(
        tester,
        setting: setting,
        disableAnimations: disable,
      );
      expect(m.reduced, isTrue);
      expect([
        m.quick,
        m.standard,
        m.emphasized,
        m.colour,
      ], everyElement(Duration.zero));
    });
  }

  testWidgets('without a MotionScope the system setting still counts', (
    tester,
  ) async {
    late MotionDurations motion;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            motion = Motion.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(motion.reduced, isTrue);
  });
}
