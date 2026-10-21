import 'dart:math' as math;

const int _maxCounter = 99999;

/// Hybrid logical clock value. The packed form
/// `<wall_ms 13 digits>-<counter 5 digits>-<device_id>` sorts as a string in
/// the same order as [compareTo] (for wall clocks below 10^13 ms).
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.wallMs,
    required this.counter,
    required this.deviceId,
  });

  final int wallMs;
  final int counter;
  final String deviceId;

  String pack() =>
      '${wallMs.toString().padLeft(13, '0')}-'
      '${counter.toString().padLeft(5, '0')}-$deviceId';

  /// Parses the output of [pack]. Device ids may contain `-`.
  /// Throws [FormatException] on malformed input.
  static Hlc parse(String s) {
    final first = s.indexOf('-');
    final second = first < 0 ? -1 : s.indexOf('-', first + 1);
    if (first < 0 || second < 0) {
      throw FormatException('Malformed HLC', s);
    }
    final wallStr = s.substring(0, first);
    final counterStr = s.substring(first + 1, second);
    final deviceId = s.substring(second + 1);
    final digits = RegExp(r'^[0-9]+$');
    if (!digits.hasMatch(wallStr) ||
        !digits.hasMatch(counterStr) ||
        deviceId.isEmpty) {
      throw FormatException('Malformed HLC', s);
    }
    return Hlc(
      wallMs: int.parse(wallStr),
      counter: int.parse(counterStr),
      deviceId: deviceId,
    );
  }

  @override
  int compareTo(Hlc other) {
    final w = wallMs.compareTo(other.wallMs);
    if (w != 0) return w;
    final c = counter.compareTo(other.counter);
    if (c != 0) return c;
    return deviceId.compareTo(other.deviceId);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMs == wallMs &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(wallMs, counter, deviceId);

  @override
  String toString() => pack();
}

/// Issues monotonically increasing [Hlc] values for one device.
class HlcClock {
  HlcClock(this.deviceId, {Hlc? last, int Function()? nowMs})
    : _last = last ?? Hlc(wallMs: 0, counter: 0, deviceId: deviceId),
      _nowMs = nowMs ?? _systemNowMs;

  final String deviceId;
  final int Function() _nowMs;
  Hlc _last;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  Hlc get last => _last;

  /// Local event: returns a value strictly greater than every previous one.
  Hlc tick() {
    final wall = math.max(_nowMs(), _last.wallMs);
    final counter = wall == _last.wallMs ? _last.counter + 1 : 0;
    return _last = _make(wall, counter);
  }

  /// Merges a clock received from another device.
  Hlc receive(Hlc remote) {
    final wall = math.max(_nowMs(), math.max(_last.wallMs, remote.wallMs));
    final int counter;
    if (wall == _last.wallMs && wall == remote.wallMs) {
      counter = math.max(_last.counter, remote.counter) + 1;
    } else if (wall == _last.wallMs) {
      counter = _last.counter + 1;
    } else if (wall == remote.wallMs) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    return _last = _make(wall, counter);
  }

  Hlc _make(int wall, int counter) {
    if (counter > _maxCounter) {
      throw StateError('HLC counter overflow at wall=$wall');
    }
    return Hlc(wallMs: wall, counter: counter, deviceId: deviceId);
  }
}
