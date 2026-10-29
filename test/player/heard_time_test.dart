import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/heard_time.dart';

void main() {
  late HeardTime h;
  setUp(() => h = HeardTime());

  void at(int ms, {bool playing = true}) => h.onState(
    playing: playing,
    position: Duration(milliseconds: ms),
  );

  /// [from]..[to] seconds in 1 s steps.
  void play(int from, int to) {
    for (var s = from; s <= to; s++) {
      at(s * 1000);
    }
  }

  test('1 s steps while playing add up', () {
    play(0, 31);
    expect(h.heard, const Duration(seconds: 31));
  });

  test('a seek forward or back adds nothing', () {
    play(0, 10);
    play(100, 110);
    expect(h.heard, const Duration(seconds: 20));
    play(3, 5);
    expect(h.heard, const Duration(seconds: 22));
  });

  test('a step of exactly 5 s counts, a longer one does not', () {
    play(0, 0);
    at(5000);
    expect(h.heard, const Duration(seconds: 5));
    at(10001);
    expect(h.heard, const Duration(seconds: 5));
  });

  test('paused ticks add nothing', () {
    play(0, 29);
    for (var i = 0; i < 5; i++) {
      at(29000, playing: false);
    }
    expect(h.heard, const Duration(seconds: 29));
    play(29, 30);
    expect(h.heard, const Duration(seconds: 30));
  });

  test('positions moving while paused add nothing after the first', () {
    play(0, 10);
    at(11000, playing: false); // the step into the stop counts
    at(12000, playing: false);
    at(13000, playing: false);
    expect(h.heard, const Duration(seconds: 11));
  });

  test('the step into a stopping state counts', () {
    for (var ms = 500; ms < 19500; ms += 1000) {
      at(ms);
    }
    at(19500, playing: false);
    at(19500, playing: false);
    expect(h.heard, const Duration(milliseconds: 19500));
  });

  test('a first tick within 2 s of the start is credited', () {
    at(400);
    expect(h.heard, const Duration(milliseconds: 400));
    h.reset();
    at(2000);
    expect(h.heard, const Duration(seconds: 2));
  });

  test('a first tick past 2 s, or while paused, is not credited', () {
    at(2001);
    expect(h.heard, Duration.zero);
    h.reset();
    at(1000, playing: false);
    expect(h.heard, Duration.zero);
  });

  test('reset clears the heard time and the last position', () {
    play(0, 40);
    h.reset();
    expect(h.heard, Duration.zero);
    at(41000); // not a step from 40 s: a first tick past the start credit
    expect(h.heard, Duration.zero);
  });
}
