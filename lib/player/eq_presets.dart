import 'dart:math' as math;

/// The reference bands (Hz) every preset's gains are given for.
const kEqBandsHz = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// The equalizer presets, in the order Settings lists them.
enum EqPreset {
  off('Off', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  bassBoost('Bass boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  vocal('Vocal', [-2, -2, -1, 1, 3, 3, 2, 1, 0, -1]),
  rock('Rock', [4, 3, 2, 0, -1, 0, 2, 3, 4, 4]),
  pop('Pop', [-1, 0, 2, 3, 3, 2, 0, -1, -1, -1]),
  classical('Classical', [0, 0, 0, 0, 0, 0, -2, -2, -2, -3]),
  electronic('Electronic', [5, 4, 1, 0, -2, 1, 0, 2, 4, 5]),
  acoustic('Acoustic', [3, 3, 2, 1, 1, 1, 2, 2, 2, 1]);

  const EqPreset(this.label, this.gains);

  final String label;

  /// Gain (dB) per band of [kEqBandsHz].
  final List<double> gains;
}

/// The preset stored as [name]; Off for anything unknown.
EqPreset eqPresetFromName(String? name) => EqPreset.values.firstWhere(
  (p) => p.name == name,
  orElse: () => EqPreset.off,
);

/// A level cut (dB) that keeps [p]'s boosts from clipping: minus half the
/// biggest boost, 0 when nothing is boosted.
double eqPreampDb(EqPreset p) {
  final top = p.gains.fold<double>(0, math.max);
  return top > 0 ? -top / 2 : 0;
}

/// [p]'s gains for a device's own bands: each takes the gain of the nearest
/// reference band (by octaves), clamped to [minDb]..[maxDb].
List<double> mapGains(
  EqPreset p,
  List<double> bandCentersHz, {
  required double minDb,
  required double maxDb,
}) => [
  for (final hz in bandCentersHz) p.gains[_nearestBand(hz)].clamp(minDb, maxDb),
];

int _nearestBand(double hz) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < kEqBandsHz.length; i++) {
    final d = (math.log(hz / kEqBandsHz[i]) / math.ln2).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}
