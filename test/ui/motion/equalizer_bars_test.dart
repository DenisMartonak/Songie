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

  testWidgets('playing: keeps scheduling frames', (tester) async {
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('pausing playback stops it', (tester) async {
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the app being paused stops the ticker', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // A muted ticker unschedules its frame callback.
    expect(tester.binding.transientCallbackCount, 0);
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
