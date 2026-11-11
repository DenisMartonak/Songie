import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/equalizer_bars.dart';

void main() {
  Widget app(bool playing, {bool disableAnimations = false}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: Center(child: EqualizerBars(playing: playing)),
    ),
  );

  testWidgets('paused: static bars, no frames scheduled once settled', (
    tester,
  ) async {
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getSize(find.byType(EqualizerBars)), const Size(14, 14));
  });

  /// How often the bars were painted during [seconds] of playing.
  Future<int> paintsOver(WidgetTester tester, num seconds) async {
    final before = EqualizerBars.debugPaintCount;
    for (var t = 0; t < seconds * 1000; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return EqualizerBars.debugPaintCount - before;
  }

  testWidgets('playing: the bars step about 10 times a second, not every '
      'frame', (tester) async {
    await tester.pumpWidget(app(true));
    await tester.pump();
    final paints = await paintsOver(tester, 1);
    expect(paints, inInclusiveRange(8, 12));
    // No ticker asking for a frame every vsync.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('an unfocused window freezes the bars', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(await paintsOver(tester, 1), lessThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await paintsOver(tester, 1), inInclusiveRange(8, 12));
  });

  testWidgets('pausing playback stops it', (tester) async {
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the app being paused stops the bars', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(await paintsOver(tester, 1), 0);
    final bars = find.descendant(
      of: find.byType(EqualizerBars),
      matching: find.byType(CustomPaint),
    );
    expect(TickerMode.valuesOf(tester.element(bars)).enabled, isFalse);
  });

  testWidgets('with reduced motion the bars stay still', (tester) async {
    await tester.pumpWidget(app(true, disableAnimations: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
