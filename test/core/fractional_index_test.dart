import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/fractional_index.dart';

void main() {
  // Values from rocicorp/fractional-indexing (src/test.js).
  test('known values', () {
    expect(keyBetween(null, null), 'a0');
    expect(keyBetween(null, 'a0'), 'Zz');
    expect(keyBetween(null, 'Zz'), 'Zy');
    expect(keyBetween('a0', null), 'a1');
    expect(keyBetween('a1', null), 'a2');
    expect(keyBetween('a0', 'a1'), 'a0V');
    expect(keyBetween('a1', 'a2'), 'a1V');
    expect(keyBetween('a0V', 'a1'), 'a0l');
    expect(keyBetween('Zz', 'a0'), 'ZzV');
    expect(keyBetween('Zz', 'a1'), 'a0');
    expect(keyBetween(null, 'Y00'), 'Xzzz');
    expect(keyBetween('bzz', null), 'c000');
    expect(keyBetween('a0', 'a0V'), 'a0G');
    expect(keyBetween('a0', 'a0G'), 'a08');
    expect(keyBetween('b125', 'b129'), 'b127');
    expect(keyBetween('a0', 'a1V'), 'a1');
    expect(keyBetween('Zz', 'a01'), 'a0');
    expect(keyBetween(null, 'a0V'), 'a0');
    expect(keyBetween(null, 'b999'), 'b99');
    expect(
      keyBetween(null, 'A000000000000000000000000001'),
      'A000000000000000000000000000V',
    );
    expect(
      keyBetween('zzzzzzzzzzzzzzzzzzzzzzzzzzy', null),
      'zzzzzzzzzzzzzzzzzzzzzzzzzzz',
    );
    expect(
      keyBetween('zzzzzzzzzzzzzzzzzzzzzzzzzzz', null),
      'zzzzzzzzzzzzzzzzzzzzzzzzzzzV',
    );
  });

  test('throws when a >= b', () {
    expect(() => keyBetween('a1', 'a0'), throwsArgumentError);
    expect(() => keyBetween('a1', 'a1'), throwsArgumentError);
  });

  test('throws on invalid order keys', () {
    expect(() => keyBetween('a00', null), throwsArgumentError);
    expect(() => keyBetween('a00', 'a1'), throwsArgumentError);
    expect(() => keyBetween('0', '1'), throwsArgumentError);
    expect(
      () => keyBetween(null, 'A00000000000000000000000000'),
      throwsArgumentError,
    );
    expect(() => keyBetween('', null), throwsArgumentError);
  });

  test('1000 appends stay ordered and short', () {
    String? last;
    final keys = <String>[];
    for (var i = 0; i < 1000; i++) {
      last = keyBetween(last, null);
      keys.add(last);
    }
    expect([...keys]..sort(), keys);
    expect(keys.last.length, lessThanOrEqualTo(4));
  });

  test('1000 prepends stay ordered', () {
    String? first;
    final keys = <String>[];
    for (var i = 0; i < 1000; i++) {
      first = keyBetween(null, first);
      keys.insert(0, first);
    }
    expect([...keys]..sort(), keys);
    expect(keys.toSet().length, 1000);
  });

  test('random inserts keep order', () {
    final rnd = Random(42);
    final keys = <String>[keyBetween(null, null)];
    for (var i = 0; i < 500; i++) {
      final j = rnd.nextInt(keys.length + 1);
      keys.insert(
        j,
        keyBetween(
          j == 0 ? null : keys[j - 1],
          j == keys.length ? null : keys[j],
        ),
      );
    }
    expect([...keys]..sort(), keys);
    expect(keys.toSet().length, keys.length);
  });

  test('nKeysBetween returns n ordered keys inside the range', () {
    final ks = nKeysBetween('a0', 'a1', 5);
    expect(ks.length, 5);
    expect([...ks]..sort(), ks);
    expect(ks.first.compareTo('a0') > 0 && ks.last.compareTo('a1') < 0, isTrue);
  });

  test('nKeysBetween with open ends and edge counts', () {
    expect(nKeysBetween(null, null, 3), ['a0', 'a1', 'a2']);
    expect(nKeysBetween('a2', null, 2), ['a3', 'a4']);
    expect(nKeysBetween(null, 'a0', 2), ['Zy', 'Zz']);
    expect(nKeysBetween('a0', 'a1', 0), isEmpty);
    expect(nKeysBetween('a0', 'a1', 1), ['a0V']);
    expect(() => nKeysBetween('a0', 'a1', -1), throwsArgumentError);
  });
}
