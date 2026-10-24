import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/shimmer.dart';

void main() {
  Widget app({bool tickers = true}) => MaterialApp(
    home: Scaffold(
      body: TickerMode(
        enabled: tickers,
        child: const Shimmer(child: SkeletonBox(width: 120, height: 16)),
      ),
    ),
  );

  testWidgets('sweeps while visible', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.getSize(find.byType(SkeletonBox)), const Size(120, 16));
  });

  testWidgets('a hidden one does not tick', (tester) async {
    await tester.pumpWidget(app(tickers: false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('stops in the background', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
