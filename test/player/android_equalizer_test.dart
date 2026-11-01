import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/eq_presets.dart';
import 'package:songies/player/equalizer.dart';

class FakePort implements AndroidEqualizerPort {
  bool? enabled;
  final gains = <int, double>{};

  @override
  Future<({List<double> centersHz, double minDb, double maxDb})>
  bands() async => (
    centersHz: [60.0, 230.0, 910.0, 3600.0, 14000.0],
    minDb: -15.0,
    maxDb: 15.0,
  );

  @override
  Future<void> setEnabled(bool on) async => enabled = on;

  @override
  Future<void> setBandGain(int i, double db) async => gains[i] = db;
}

void main() {
  test('a preset enables the system equalizer with mapped gains', () async {
    final port = FakePort();
    final eq = AndroidEqualizerControl(port);
    await eq.apply(EqPreset.bassBoost);
    expect(port.enabled, isTrue);
    // mapGains [5, 2, 0, 0, 0] plus the preamp (-3 dB) folded in.
    expect(port.gains, {0: 2.0, 1: -1.0, 2: -3.0, 3: -3.0, 4: -3.0});
    expect(await eq.available, isTrue);
  });

  test('Off disables it', () async {
    final port = FakePort();
    final eq = AndroidEqualizerControl(port);
    await eq.apply(EqPreset.rock);
    await eq.apply(EqPreset.off);
    expect(port.enabled, isFalse);
  });

  test('the stored preset is applied at start', () async {
    final applied = <EqPreset>[];
    await applyStoredEqPreset(
      read: () async => 'vocal',
      apply: (p) async => applied.add(p),
    );
    expect(applied, [EqPreset.vocal]);
  });
}
