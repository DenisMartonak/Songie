import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/sync/pairing_code.dart';

void main() {
  test('code is six zero-padded digits', () {
    for (var seed = 0; seed < 50; seed++) {
      final code = PairingCode(random: Random(seed)).code;
      expect(code, matches(RegExp(r'^\d{6}$')));
    }
  });

  test(
    'PairingCode expires after 5 minutes and is exhausted by 5 attempts',
    () {
      var now = DateTime(2026, 10, 30, 12);
      final timed = PairingCode(now: () => now);
      expect(timed.usable, isTrue);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(timed.usable, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(timed.usable, isFalse);

      final charged = PairingCode(now: () => DateTime(2026, 10, 30, 12));
      for (var i = 0; i < 4; i++) {
        charged.chargeAttempt();
        expect(charged.usable, isTrue);
      }
      charged.chargeAttempt();
      expect(charged.usable, isFalse);
    },
  );
}
