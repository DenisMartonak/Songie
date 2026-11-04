import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/crash_reporting/crash_reporter.dart';

/// A fake SDK: counts starts and closes, and lets a test hold a start open.
class _FakeSdk {
  int starts = 0;
  int closes = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  Completer<void>? gate;

  Future<void> start() async {
    starts++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final g = gate;
    if (g != null) await g.future;
    inFlight--;
  }

  Future<void> close() async {
    closes++;
  }

  CrashReporter reporter({bool built = true}) =>
      CrashReporter(built: built, start: start, close: close);
}

void main() {
  test('not built: applySetting(true) never starts', () async {
    final sdk = _FakeSdk();
    final r = sdk.reporter(built: false);
    await r.applySetting(true);
    final setting = StreamController<bool>.broadcast();
    r.follow(setting.stream);
    setting
      ..add(true)
      ..add(false)
      ..add(true);
    await pumpEventQueue();
    expect(sdk.starts, 0);
    expect(r.running, isFalse);
    await r.dispose();
    expect(sdk.closes, 0);
    await setting.close();
  });

  test('setting on starts once; off closes; on again starts again', () async {
    final sdk = _FakeSdk();
    final r = sdk.reporter();
    await r.applySetting(true);
    expect(sdk.starts, 1);
    expect(r.running, isTrue);
    await r.applySetting(true);
    expect(sdk.starts, 1, reason: 'already running');
    await r.applySetting(false);
    expect(sdk.closes, 1);
    expect(r.running, isFalse);
    await r.applySetting(false);
    expect(sdk.closes, 1, reason: 'already stopped');
    await r.applySetting(true);
    expect(sdk.starts, 2);
    expect(r.running, isTrue);
  });

  test('follow applies each setting change', () async {
    final sdk = _FakeSdk();
    final r = sdk.reporter();
    final setting = StreamController<bool>();
    r.follow(setting.stream);
    setting.add(true);
    await pumpEventQueue();
    expect(r.running, isTrue);
    setting.add(false);
    await pumpEventQueue();
    expect(r.running, isFalse);
    expect((sdk.starts, sdk.closes), (1, 1));
    await r.dispose();
    await setting.close();
  });

  test('rapid on/off/on while a start is pending ends running with one start '
      'in flight at a time', () async {
    final sdk = _FakeSdk()..gate = Completer<void>();
    final r = sdk.reporter();
    final first = r.applySetting(true);
    await pumpEventQueue();
    expect(sdk.inFlight, 1);
    final off = r.applySetting(false);
    final on = r.applySetting(true);
    final off2 = r.applySetting(false);
    final on2 = r.applySetting(true);
    await pumpEventQueue();
    expect(sdk.starts, 1, reason: 'no second start while one is pending');
    sdk.gate!.complete();
    await Future.wait([first, off, on, off2, on2]);
    expect(sdk.maxInFlight, 1);
    expect(r.running, isTrue);
    // The last wish was on, and the pending start already gave that.
    expect(sdk.starts, 1);
    expect(sdk.closes, 0);
  });

  test('a toggle off during a pending start closes after it', () async {
    final sdk = _FakeSdk()..gate = Completer<void>();
    final r = sdk.reporter();
    final first = r.applySetting(true);
    await pumpEventQueue();
    final off = r.applySetting(false);
    sdk.gate!.complete();
    await Future.wait([first, off]);
    expect((sdk.starts, sdk.closes), (1, 1));
    expect(r.running, isFalse);
  });

  test('off at launch never starts', () async {
    final sdk = _FakeSdk();
    final r = sdk.reporter();
    await r.applySetting(false);
    expect(sdk.starts, 0);
    expect(sdk.closes, 0);
    expect(r.running, isFalse);
  });

  test('a failing start leaves it stopped and a later on retries', () async {
    var fail = true;
    var starts = 0;
    final r = CrashReporter(
      built: true,
      start: () async {
        starts++;
        if (fail) throw StateError('no');
      },
      close: () async {},
    );
    await r.applySetting(true);
    expect(r.running, isFalse);
    fail = false;
    await r.applySetting(false);
    await r.applySetting(true);
    expect(r.running, isTrue);
    expect(starts, 2);
  });

  test('dispose closes a running reporter', () async {
    final sdk = _FakeSdk();
    final r = sdk.reporter();
    await r.applySetting(true);
    await r.dispose();
    expect(sdk.closes, 1);
    expect(r.running, isFalse);
  });
}
