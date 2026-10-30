import 'dart:math';

/// The 6-digit code a device shows while it accepts pairing. It is usable for
/// [lifetime] and until [maxFailures] failed confirmations. It is never
/// advertised, logged or sent in clear.
class PairingCode {
  PairingCode({Random? random, DateTime Function() now = DateTime.now})
    : _now = now, // ignore: prefer_initializing_formals
      _created = now(),
      code = (random ?? Random.secure())
          .nextInt(1000000)
          .toString()
          .padLeft(6, '0');

  static const lifetime = Duration(minutes: 5);
  static const maxFailures = 5;

  final DateTime Function() _now;
  final DateTime _created;
  int _failures = 0;

  final String code;

  bool get usable =>
      _failures < maxFailures && _now().difference(_created) < lifetime;

  /// Records a failed confirmation against this code.
  void fail() => _failures++;
}
