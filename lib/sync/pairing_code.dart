import 'dart:math';

/// The 6-digit code a device shows while it accepts pairing. It is usable for
/// [lifetime] and for at most [maxAttempts] pairing attempts. It is never
/// advertised, logged or sent in clear.
///
/// The responder confirms first, so a guesser learns whether a guess was right
/// from every /pair/start, even one that never reaches /pair/finish. Every
/// /pair/start that reaches `Spake2.finish` therefore charges one attempt,
/// whether it succeeds or not.
class PairingCode {
  PairingCode({Random? random, DateTime Function() now = DateTime.now})
    : _now = now, // ignore: prefer_initializing_formals
      _created = now(),
      code = (random ?? Random.secure())
          .nextInt(1000000)
          .toString()
          .padLeft(6, '0');

  static const lifetime = Duration(minutes: 5);
  static const maxAttempts = 5;

  final DateTime Function() _now;
  final DateTime _created;
  int _attempts = 0;

  final String code;

  bool get usable =>
      _attempts < maxAttempts && _now().difference(_created) < lifetime;

  /// Charges one pairing attempt against this code.
  void chargeAttempt() => _attempts++;
}
