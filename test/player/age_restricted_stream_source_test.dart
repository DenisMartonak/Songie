import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/player/age_restricted_stream_source.dart';
import 'package:songies/player/stream_source.dart';
import 'package:songies/youtube/js_runtime.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';

import '../helpers/fake_ytdlp_runner.dart';

class _FakeSource implements StreamSource {
  _FakeSource(this.result);

  final Result<YtStream> result;

  @override
  String get name => 'inner';

  @override
  Future<Result<YtStream>> resolveStream(String videoId) async => result;
}

class _FakeFinder implements JsRuntimeFinder {
  _FakeFinder(this.runtime);

  final JsRuntime? runtime;

  @override
  Future<JsRuntime?> find() async => runtime;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _ok = Ok<YtStream>(YtStream(url: Uri.parse('https://yt.example/a')));
Err<YtStream> _err(YtErrorKind k) => Err(ytFailure(k, 'x'));
const _node = JsRuntime(JsRuntimeKind.systemNode, ['--js-runtimes', 'node']);
final _stream = File('test/fixtures/ytdlp/stream_opus.json').readAsStringSync();

void main() {
  late FakeYtDlpRunner runner;
  late int sessionLoads;
  YtSession? session;

  setUp(() {
    runner = FakeYtDlpRunner();
    sessionLoads = 0;
    session = YtSession({'SID': 'sid-value'});
  });

  AgeRestrictedStreamSource source(
    Result<YtStream> inner, {
    JsRuntime? runtime = _node,
  }) => AgeRestrictedStreamSource(
    _FakeSource(inner),
    YtDlpClient(runner, cookiesDir: Directory.systemTemp),
    AgeRestrictedAuth(() async {
      sessionLoads++;
      return session;
    }, _FakeFinder(runtime)),
  );

  YtErrorKind? kindOf(Result<YtStream> r) =>
      r is Err<YtStream> ? ytErrorKindOf(r.failure) : null;

  test('an Ok answer is returned without loading the session', () async {
    expect(await source(_ok).resolveStream('v'), same(_ok));
    expect(sessionLoads, 0);
    expect(runner.calls, isEmpty);
  });

  test('other failures are returned unchanged, no retry', () async {
    for (final k in [YtErrorKind.notFound, YtErrorKind.network]) {
      final r = await source(_err(k)).resolveStream('v');
      expect(kindOf(r), k);
    }
    expect(runner.calls, isEmpty);
  });

  test('signed out stays ageRestricted', () async {
    session = null;
    final r = await source(_err(YtErrorKind.ageRestricted)).resolveStream('v');
    expect(kindOf(r), YtErrorKind.ageRestricted);
    expect(runner.calls, isEmpty);
  });

  test('signed in without a runtime is needsRuntime', () async {
    final r = await source(
      _err(YtErrorKind.ageRestricted),
      runtime: null,
    ).resolveStream('v');
    expect(kindOf(r), YtErrorKind.needsRuntime);
    expect(runner.calls, isEmpty);
  });

  test('signed in with a runtime retries once with cookies', () async {
    runner.onOk('watch?v=', _stream);
    final r = await source(_err(YtErrorKind.ageRestricted)).resolveStream('v');
    expect(r, isA<Ok<YtStream>>());
    final args = runner.calls.single;
    expect(args, contains('--cookies'));
    expect(args, containsAllInOrder(['--js-runtimes', 'node']));
  });

  test('the signed-in refusal is ageRestrictedAccount', () async {
    runner.onFail(
      'watch?v=',
      'ERROR: [youtube] v: Sign in to confirm your age',
    );
    final r = await source(_err(YtErrorKind.ageRestricted)).resolveStream('v');
    expect(kindOf(r), YtErrorKind.ageRestrictedAccount);
  });
}
