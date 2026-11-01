import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/player/eq_presets.dart';
import 'package:songies/player/equalizer.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/settings/playback_settings.dart';

import '../../helpers/ui_harness.dart';

class FakeEqualizer implements Equalizer {
  FakeEqualizer({this.known});

  final bool? known;
  final applied = <EqPreset>[];

  @override
  Future<bool> get available async => known ?? true;

  @override
  bool? get knownAvailable => known;

  @override
  Future<void> apply(EqPreset preset) async => applied.add(preset);
}

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester,
    FakeEqualizer eq, {
    bool windows = false,
  }) async {
    h.isWindows = windows;
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: [
          equalizerProvider.overrideWithValue(eq),
        ],
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [PlaybackSettingsSection()]),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  final row = find.byKey(const Key('settings.equalizer'));

  uiTest('Playback shows the equalizer, Off by default', (tester) async {
    await pump(tester, FakeEqualizer());
    expect(find.text('Playback'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Off')),
      findsOneWidget,
    );
  });

  uiTest('picking Rock stores it and applies it', (tester) async {
    final eq = FakeEqualizer();
    await pump(tester, eq);
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.text('Rock'));
    await settle(tester);
    expect(
      find.descendant(of: row, matching: find.text('Rock')),
      findsOneWidget,
    );
    expect(eq.applied.last, EqPreset.rock);
    final stored = await real(
      tester,
      () => SettingsRepository(h.db).getString(kEqPreset),
    );
    expect(stored, 'rock');
  });

  uiTest('Windows without the filter says so and is disabled', (tester) async {
    await pump(tester, FakeEqualizer(known: false), windows: true);
    expect(find.text('Not available on Windows yet'), findsOneWidget);
    expect(tester.widget<ListTile>(row).enabled, isFalse);
  });
}
