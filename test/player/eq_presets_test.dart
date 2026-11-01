import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/eq_presets.dart';

void main() {
  test('every preset has ten gains; Off is flat', () {
    for (final p in EqPreset.values) {
      expect(p.gains, hasLength(10), reason: p.name);
    }
    expect(EqPreset.off.gains, everyElement(0));
    expect(EqPreset.bassBoost.gains.first, 6);
    expect(kEqBandsHz, [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]);
  });

  test('labels', () {
    expect(EqPreset.values.map((p) => p.label), [
      'Off',
      'Bass boost',
      'Vocal',
      'Rock',
      'Pop',
      'Classical',
      'Electronic',
      'Acoustic',
    ]);
  });

  test('gains map to the nearest reference band', () {
    expect(
      mapGains(
        EqPreset.bassBoost,
        [60, 230, 910, 3600, 14000],
        minDb: -15,
        maxDb: 15,
      ),
      [5, 2, 0, 0, 0],
    );
  });

  test('gains are clamped to the device range', () {
    expect(mapGains(EqPreset.electronic, [31, 16000], minDb: -3, maxDb: 3), [
      3,
      3,
    ]);
  });

  test('preamp is minus half the biggest boost', () {
    expect(eqPreampDb(EqPreset.bassBoost), -3);
    expect(eqPreampDb(EqPreset.classical), 0);
    expect(eqPreampDb(EqPreset.off), 0);
  });

  test('names round-trip; unknown is Off', () {
    expect(eqPresetFromName('rock'), EqPreset.rock);
    expect(eqPresetFromName('nope'), EqPreset.off);
    expect(eqPresetFromName(null), EqPreset.off);
  });
}
