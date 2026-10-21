import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/hlc.dart';

void main() {
  test('pack is zero padded and round-trips', () {
    final h = Hlc(wallMs: 1792607152000, counter: 7, deviceId: 'dev-a');
    expect(h.pack(), '1792607152000-00007-dev-a');
    expect(Hlc.parse(h.pack()), h);
    expect(Hlc.parse(h.pack()).hashCode, h.hashCode);
  });

  test('pack zero pads a small wall clock to 13 digits', () {
    expect(
      Hlc(wallMs: 0, counter: 0, deviceId: 'd').pack(),
      '0000000000000-00000-d',
    );
  });

  test('string order equals clock order', () {
    final a = Hlc(wallMs: 999, counter: 99999, deviceId: 'z');
    final b = Hlc(wallMs: 1000, counter: 0, deviceId: 'a');
    expect(a.compareTo(b) < 0, isTrue);
    expect(a.pack().compareTo(b.pack()) < 0, isTrue);
  });

  test('compareTo falls back to counter then device id', () {
    final base = Hlc(wallMs: 5, counter: 1, deviceId: 'a');
    expect(
      base.compareTo(Hlc(wallMs: 5, counter: 2, deviceId: 'a')) < 0,
      isTrue,
    );
    expect(
      base.compareTo(Hlc(wallMs: 5, counter: 1, deviceId: 'b')) < 0,
      isTrue,
    );
    expect(base.compareTo(Hlc(wallMs: 5, counter: 1, deviceId: 'a')), 0);
  });

  test('parse keeps dashes inside the device id', () {
    final h = Hlc.parse('0000000000010-00002-my-phone-1');
    expect(h.wallMs, 10);
    expect(h.counter, 2);
    expect(h.deviceId, 'my-phone-1');
  });

  test('parse throws FormatException on malformed input', () {
    for (final bad in [
      '',
      'nope',
      '12-34',
      'abc-00001-d',
      '123-xyz-d',
      '123-00001-',
    ]) {
      expect(() => Hlc.parse(bad), throwsFormatException, reason: bad);
    }
  });

  test('tick is monotonic when the wall clock goes backwards', () {
    var now = 5000;
    final c = HlcClock('d', nowMs: () => now);
    final t1 = c.tick();
    now = 4000;
    final t2 = c.tick();
    expect(t2.compareTo(t1) > 0, isTrue);
    expect(t2.wallMs, 5000);
    expect(t2.counter, 1);
  });

  test('tick resets the counter when the wall clock advances', () {
    var now = 5000;
    final c = HlcClock('d', nowMs: () => now);
    c.tick();
    now = 6000;
    final t = c.tick();
    expect(t.wallMs, 6000);
    expect(t.counter, 0);
    expect(c.last, t);
  });

  test('clock resumes from a supplied last value', () {
    final last = Hlc(wallMs: 9000, counter: 4, deviceId: 'd');
    final c = HlcClock('d', last: last, nowMs: () => 1000);
    expect(c.last, last);
    final t = c.tick();
    expect(t.wallMs, 9000);
    expect(t.counter, 5);
  });

  test('tick throws StateError instead of overflowing the counter', () {
    final c = HlcClock(
      'd',
      last: Hlc(wallMs: 9000, counter: 99999, deviceId: 'd'),
      nowMs: () => 1000,
    );
    expect(c.tick, throwsStateError);
  });

  test('receive advances past a remote clock from the future', () {
    final c = HlcClock('d', nowMs: () => 1000);
    final r = c.receive(Hlc(wallMs: 9000, counter: 3, deviceId: 'x'));
    expect(r.wallMs, 9000);
    expect(r.counter, 4);
    expect(r.deviceId, 'd');
    expect(c.last, r);
  });

  test('receive counter rules', () {
    // local last wall wins -> last.c + 1
    var c = HlcClock(
      'd',
      last: Hlc(wallMs: 9000, counter: 5, deviceId: 'd'),
      nowMs: () => 1000,
    );
    expect(c.receive(Hlc(wallMs: 8000, counter: 50, deviceId: 'x')).counter, 6);
    // last and remote equal -> max + 1
    c = HlcClock(
      'd',
      last: Hlc(wallMs: 9000, counter: 5, deviceId: 'd'),
      nowMs: () => 1000,
    );
    expect(c.receive(Hlc(wallMs: 9000, counter: 8, deviceId: 'x')).counter, 9);
    // local now wins -> 0
    c = HlcClock(
      'd',
      last: Hlc(wallMs: 100, counter: 5, deviceId: 'd'),
      nowMs: () => 9000,
    );
    expect(c.receive(Hlc(wallMs: 200, counter: 8, deviceId: 'x')).counter, 0);
  });
}
