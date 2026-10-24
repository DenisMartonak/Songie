import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/downloads/android_download_notifier.dart';
import 'package:songies/downloads/download_notifier.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('songies/download_notifier');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final base = DateTime(2026, 1, 1, 12);

  Map<String, Object?> args(int i) =>
      Map<String, Object?>.from(calls[i].arguments as Map);

  DownloadSnapshot snap({
    int done = 0,
    int total = 5,
    int active = 1,
    int queued = 3,
    String? title = 'Song',
    DownloadPause? pause,
  }) => DownloadSnapshot(
    completedThisRun: done,
    totalThisRun: total,
    active: active,
    queued: queued,
    currentTitle: title,
    pause: pause,
  );

  test('a running snapshot shows the count, title and a progress bar', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.update(snap(done: 2));
      async.flushMicrotasks();
      expect(calls.single.method, 'update');
      expect(args(0), {
        'title': 'Downloading songs',
        'text': '2 of 5 · Song',
        'progress': 2,
        'max': 5,
      });
    });
  });

  test('a running snapshot without a title shows just the count', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.update(snap(done: 1, title: null));
      async.flushMicrotasks();
      expect(args(0)['text'], '1 of 5');
    });
  });

  test('paused texts', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      final cases = <DownloadPause, String>{
        const DownloadPause(DownloadPauseReason.wifiOnly):
            'Paused — waiting for Wi-Fi',
        const DownloadPause(DownloadPauseReason.offline): 'Paused — offline',
        const DownloadPause(DownloadPauseReason.diskFull):
            'Paused — storage is full',
        DownloadPause(
          DownloadPauseReason.throttled,
          resumesAt: base.add(const Duration(seconds: 30)),
        ): 'Paused — YouTube is limiting downloads, retrying in 1 min',
        DownloadPause(
          DownloadPauseReason.throttled,
          resumesAt: base.add(const Duration(minutes: 4, seconds: 1)),
        ): 'Paused — YouTube is limiting downloads, retrying in 5 min',
        DownloadPause(
          DownloadPauseReason.retrying,
          resumesAt: base.add(const Duration(minutes: 2)),
        ): 'Paused — connection problem, retrying in 2 min',
        DownloadPause(
          DownloadPauseReason.retrying,
          resumesAt: base.subtract(const Duration(seconds: 5)),
        ): 'Paused — connection problem, retrying in 1 min',
        const DownloadPause(DownloadPauseReason.user): 'Downloads paused',
      };
      var i = 0;
      for (final e in cases.entries) {
        n.update(snap(pause: e.key));
        async.elapse(const Duration(seconds: 1));
        expect(args(i)['text'], e.value);
        expect(args(i)['title'], 'Downloading songs');
        i++;
      }
      expect(calls, hasLength(cases.length));
    });
  });

  test('updates go out at most once a second, the latest one last', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.update(snap(done: 0));
      n.update(snap(done: 1));
      n.update(snap(done: 2));
      async.flushMicrotasks();
      expect(calls, hasLength(1));
      expect(args(0)['progress'], 0);

      async.elapse(const Duration(milliseconds: 999));
      expect(calls, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, hasLength(2));
      expect(args(1)['progress'], 2);

      // Quiet afterwards: the gate runs out, then no timer and no call.
      async.elapse(const Duration(seconds: 1));
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(2));

      n.update(snap(done: 3));
      async.flushMicrotasks();
      expect(calls, hasLength(3));
      expect(args(2)['progress'], 3);
    });
  });

  test('a snapshot with no work is not sent', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.update(snap(done: 5, active: 0, queued: 0));
      async.flushMicrotasks();
      expect(calls, isEmpty);
    });
  });

  test('the run ending sends one finished call and drops a pending update', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.update(snap(done: 4));
      n.update(snap(done: 5));
      n.finished(5, 1);
      async.elapse(const Duration(seconds: 5));
      expect(calls.map((c) => c.method), ['update', 'finished']);
      expect(args(1), {'text': 'Downloaded 5 songs · 1 failed'});
    });
  });

  test('finished texts', () {
    fakeAsync((async) {
      final n = AndroidDownloadNotifier(now: () => base);
      n.finished(1, 0);
      n.finished(3, 0);
      async.flushMicrotasks();
      expect(args(0)['text'], 'Downloaded 1 song');
      expect(args(1)['text'], 'Downloaded 3 songs');
    });
  });

  test('a channel failure is swallowed', () {
    fakeAsync((async) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'x');
          });
      final n = AndroidDownloadNotifier(now: () => base);
      Object? error;
      n.update(snap()).catchError((Object e) => error = e);
      async.flushMicrotasks();
      expect(error, isNull);
    });
  });

  test('desktop gets the no-op notifier, Android the real one', () {
    final desktop = ProviderContainer(
      overrides: [isAndroidProvider.overrideWithValue(false)],
    );
    addTearDown(desktop.dispose);
    expect(desktop.read(downloadNotifierProvider), isA<NoopDownloadNotifier>());

    final android = ProviderContainer(
      overrides: [isAndroidProvider.overrideWithValue(true)],
    );
    addTearDown(android.dispose);
    expect(
      android.read(downloadNotifierProvider),
      isA<AndroidDownloadNotifier>(),
    );
  });

  group('ensureNotificationPermission', () {
    const perms = MethodChannel('flutter.baseflow.com/permissions/methods');
    late int requests;
    late int api;

    setUp(() {
      requests = 0;
      api = 33;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'apiLevel' ? api : null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(perms, (call) async {
            if (call.method == 'requestPermissions') {
              requests++;
              return {17: 0}; // denied
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(perms, null);
    });

    test('asks once per run on API 33+, even when refused', () async {
      final asker = NotificationPermissionAsker(isAndroid: () => true);
      await Future.wait([asker.ensure(), asker.ensure()]);
      await asker.ensure();
      expect(requests, 1);
    });

    test('does not ask below API 33', () async {
      api = 32;
      final asker = NotificationPermissionAsker(isAndroid: () => true);
      await asker.ensure();
      expect(requests, 0);
    });

    test('is a no-op on desktop', () async {
      final asker = NotificationPermissionAsker(isAndroid: () => false);
      await asker.ensure();
      expect(requests, 0);
      expect(calls, isEmpty);
    });

    test('never throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(perms, (call) async {
            throw PlatformException(code: 'boom');
          });
      final asker = NotificationPermissionAsker(isAndroid: () => true);
      await asker.ensure();
    });
  });
}
