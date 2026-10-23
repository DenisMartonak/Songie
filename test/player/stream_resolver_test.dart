import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/stream_resolver.dart';
import 'package:songies/youtube/ytdlp_client.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

import '../helpers/fake_network_status.dart';
import '../helpers/fake_ytdlp_runner.dart';
import '../helpers/test_db.dart';

String streamJson({int? expire, String title = 'T'}) =>
    '{"url":"https://rr.example/audio?expire=${expire ?? 0}",'
    '"http_headers":{"User-Agent":"UA"},"title":"$title","channel":"Ch",'
    '"duration":100}';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeYtDlpRunner runner;
  late FakeNetworkStatus net;
  late DateTime now;
  late StreamResolver resolver;

  StreamResolver make() => StreamResolver(
    YtDlpClient(runner),
    net,
    settings,
    now: () => now,
    wifiOnlyFallback: false,
  );

  int expireOf(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    runner = FakeYtDlpRunner();
    net = FakeNetworkStatus();
    now = DateTime.utc(2026, 10, 22, 12);
    runner.onOk(
      'watch?v=abc',
      streamJson(expire: expireOf(now.add(const Duration(minutes: 60)))),
    );
    resolver = make();
  });
  tearDown(() async {
    resolver.dispose();
    await db.close();
  });

  Future<Result<UrlSource>> go([String id = 'abc']) => resolver.resolve(id);

  test('returns a UrlSource with headers', () async {
    final r = await go() as Ok<UrlSource>;
    expect(r.value.url.host, 'rr.example');
    expect(r.value.headers, {'User-Agent': 'UA'});
  });

  test('second resolve reuses the cache', () async {
    await go();
    await go();
    expect(runner.calls, hasLength(1));
  });

  test('reuses at 49 min, re-resolves at 51 min', () async {
    await go();
    now = now.add(const Duration(minutes: 49));
    await go();
    expect(runner.calls, hasLength(1));
    now = now.add(const Duration(minutes: 2));
    await go();
    expect(runner.calls, hasLength(2));
  });

  test('null expiresAt is reused for 1 h', () async {
    runner = FakeYtDlpRunner()
      ..onOk(
        'watch?v=abc',
        '{"url":"https://rr.example/audio","http_headers":{},"title":"T"}',
      );
    resolver.dispose();
    resolver = make();
    await go();
    now = now.add(const Duration(minutes: 59));
    await go();
    expect(runner.calls, hasLength(1));
    now = now.add(const Duration(minutes: 2));
    await go();
    expect(runner.calls, hasLength(2));
  });

  test('concurrent resolves share one runner call', () async {
    final results = await Future.wait([go(), go()]);
    expect(results.every((r) => r is Ok<UrlSource>), isTrue);
    expect(runner.calls, hasLength(1));
  });

  test('offline is refused without calling yt-dlp', () async {
    net.kind = NetworkKind.offline;
    final r = await go() as Err<UrlSource>;
    expect(r.failure.kind, FailureKind.network);
    expect(r.failure.message, "You're offline");
    expect(runner.calls, isEmpty);
  });

  test('wifi only + mobile is refused with the exact message', () async {
    await settings.setBool('wifi_only', true);
    net.kind = NetworkKind.mobile;
    final r = await go() as Err<UrlSource>;
    expect(r.failure.kind, FailureKind.network);
    expect(r.failure.message, 'Wi-Fi only is on — connect to Wi-Fi to stream');
    expect(runner.calls, isEmpty);
  });

  test('wifi only + wifi is ok; mobile ok when off', () async {
    await settings.setBool('wifi_only', true);
    expect(await go(), isA<Ok<UrlSource>>());
    await settings.setBool('wifi_only', false);
    net.kind = NetworkKind.mobile;
    resolver.invalidate('abc');
    expect(await go(), isA<Ok<UrlSource>>());
  });

  test('fallback applies when the setting is unset', () async {
    resolver.dispose();
    resolver = StreamResolver(
      YtDlpClient(runner),
      net,
      settings,
      now: () => now,
      wifiOnlyFallback: true,
    );
    net.kind = NetworkKind.mobile;
    expect(await go(), isA<Err<UrlSource>>());
  });

  test('unavailable video maps to notFound', () async {
    runner.onFail('watch?v=gone', 'ERROR: [youtube] gone: Private video');
    final r = await go('gone') as Err<UrlSource>;
    expect(r.failure.kind, FailureKind.notFound);
  });

  test('network failure gets the user-ready message', () async {
    runner.onFail('watch?v=net', 'ERROR: Unable to connect to host');
    final r = await go('net') as Err<UrlSource>;
    expect(r.failure.kind, FailureKind.network);
    expect(r.failure.message, "Couldn't reach YouTube — check your connection");
  });

  test('other failures pass through with the ytdlp prefix', () async {
    runner.onFail('watch?v=ext', 'ERROR: something odd');
    final r = await go('ext') as Err<UrlSource>;
    expect(r.failure.message, startsWith('ytdlp:extractor:'));
  });

  test('failures are not cached', () async {
    runner.onFail('watch?v=bad', 'ERROR: something odd');
    await go('bad');
    await go('bad');
    expect(runner.calls.where((c) => c.last.contains('bad')), hasLength(2));
  });

  test('invalidate drops the entry', () async {
    await go();
    resolver.invalidate('abc');
    await go();
    expect(runner.calls, hasLength(2));
  });

  test('a network change clears the whole cache', () async {
    await go();
    net.set(NetworkKind.other);
    await go();
    expect(runner.calls, hasLength(2));
  });

  test('prefetch fills the cache and swallows failures', () async {
    await resolver.prefetch('abc');
    await go();
    expect(runner.calls, hasLength(1));
    await resolver.prefetch('nope');
  });

  test('dispose cancels the network subscription', () {
    resolver.dispose();
    expect((net).hasListeners, isFalse);
  });

  test(
    'invalidating another id does not strand an in-flight resolve',
    () async {
      final gated = _GatedRunner()
        ..onOk(
          'watch?v=abc',
          streamJson(expire: expireOf(now.add(const Duration(minutes: 60)))),
        );
      runner = gated;
      resolver.dispose();
      resolver = make();
      final first = resolver.resolve('abc');
      await pumpEventQueue();
      resolver.invalidate('other');
      gated.gate.complete();
      await first;
      await go();
      expect(runner.calls, hasLength(1));
    },
  );

  test('a failed resolve is not served again', () async {
    runner.onFail('watch?v=flaky', 'ERROR: something odd');
    expect(await go('flaky'), isA<Err<UrlSource>>());
    expect(await go('flaky'), isA<Err<UrlSource>>());
    expect(runner.calls.where((c) => c.last.contains('flaky')), hasLength(2));
  });

  test('invalidate during a fetch discards that result', () async {
    final gated = _GatedRunner()
      ..onOk(
        'watch?v=abc',
        streamJson(expire: expireOf(now.add(const Duration(minutes: 60)))),
      );
    runner = gated;
    resolver.dispose();
    resolver = make();
    final first = resolver.resolve('abc');
    await pumpEventQueue();
    resolver.invalidate('abc');
    gated.gate.complete();
    await first;
    await go();
    expect(runner.calls, hasLength(2));
  });
}

class _GatedRunner extends FakeYtDlpRunner {
  final Completer<void> gate = Completer<void>();
  bool _first = true;

  @override
  Future<YtDlpRun> run(List<String> args, {Duration? timeout}) async {
    final wait = _first;
    _first = false;
    if (wait) await gate.future;
    return super.run(args, timeout: timeout);
  }
}
