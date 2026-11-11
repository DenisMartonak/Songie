import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/motion/visible_ticker.dart';

void main() {
  bool tickerEnabled(WidgetTester tester) =>
      TickerMode.valuesOf(tester.element(find.byKey(const Key('probe'))))
          .enabled;

  Widget probe({bool active = true}) => TickerMode(
    enabled: true,
    child: VisibleTicker(
      active: active,
      child: const SizedBox(key: Key('probe')),
    ),
  );

  testWidgets('enables tickers while active, visible and resumed', (
    tester,
  ) async {
    await tester.pumpWidget(probe());
    expect(tickerEnabled(tester), isTrue);
    await tester.pumpWidget(probe(active: false));
    expect(tickerEnabled(tester), isFalse);
  });

  testWidgets('an ancestor TickerMode (a hidden route) mutes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TickerMode(
        enabled: false,
        child: VisibleTicker(child: SizedBox(key: Key('probe'))),
      ),
    );
    expect(tickerEnabled(tester), isFalse);
  });

  testWidgets('pausing or hiding the app mutes it; resuming unmutes', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(probe());
    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      if (state == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      expect(tickerEnabled(tester), isFalse, reason: '$state');

      if (state == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tickerEnabled(tester), isTrue, reason: 'resumed after $state');
    }
  });

  testWidgets('an unfocused window keeps it running, unless asked not to', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    Widget app({required bool onlyFocused}) => TickerMode(
      enabled: true,
      child: VisibleTicker(
        onlyWhileFocused: onlyFocused,
        child: const SizedBox(key: Key('probe')),
      ),
    );

    await tester.pumpWidget(app(onlyFocused: false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(tickerEnabled(tester), isTrue);

    await tester.pumpWidget(app(onlyFocused: true));
    await tester.pump();
    expect(tickerEnabled(tester), isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tickerEnabled(tester), isTrue);
  });
}
