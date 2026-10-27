import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/player/stream_source.dart';
import 'package:songies/youtube/yt_models.dart';

class _FakeSource implements StreamSource {
  _FakeSource(this.name, this.result);

  @override
  final String name;
  final Result<YtStream> result;
  final calls = <String>[];

  @override
  Future<Result<YtStream>> resolveStream(String videoId) async {
    calls.add(videoId);
    return result;
  }
}

class _ThrowingSource implements StreamSource {
  @override
  String get name => 'innertube';

  @override
  Future<Result<YtStream>> resolveStream(String videoId) =>
      throw RangeError('boom');
}

final _ok = Ok<YtStream>(YtStream(url: Uri.parse('https://yt.example/a')));

void main() {
  test('innertube network Err falls through to yt-dlp Ok', () async {
    final it = _FakeSource(
      'innertube',
      Err(ytFailure(YtErrorKind.network, 'innertube: HTTP 403')),
    );
    final yt = _FakeSource('yt-dlp', _ok);
    final r = await FallbackStreamSource([it, yt]).resolveStream('v');
    expect((r as Ok<YtStream>).value.url.host, 'yt.example');
    expect(it.calls, ['v']);
    expect(yt.calls, ['v']);
  });

  test('a source that throws falls through to yt-dlp Ok', () async {
    final yt = _FakeSource('yt-dlp', _ok);
    final r = await FallbackStreamSource([_ThrowingSource(), yt])
        .resolveStream('v');
    expect(r, isA<Ok<YtStream>>());
    expect(yt.calls, ['v']);
  });

  test('a throwing last source is a non-notFound Err', () async {
    final r = await FallbackStreamSource([_ThrowingSource()])
        .resolveStream('v');
    expect(ytErrorKindOf((r as Err<YtStream>).failure), YtErrorKind.extractor);
  });

  test('a plain (non-yt) Err also falls through', () async {
    final it = _FakeSource(
      'innertube',
      const Err(Failure(FailureKind.unknown, 'odd')),
    );
    final yt = _FakeSource('yt-dlp', _ok);
    expect(
      await FallbackStreamSource([it, yt]).resolveStream('v'),
      isA<Ok<YtStream>>(),
    );
  });

  test('notFound is returned without calling yt-dlp', () async {
    final it = _FakeSource(
      'innertube',
      Err(ytFailure(YtErrorKind.notFound, 'innertube: Video unavailable')),
    );
    final yt = _FakeSource('yt-dlp', _ok);
    final r = await FallbackStreamSource([it, yt]).resolveStream('v');
    expect(ytErrorKindOf((r as Err<YtStream>).failure), YtErrorKind.notFound);
    expect(yt.calls, isEmpty);
  });

  test('a first Ok stops there', () async {
    final it = _FakeSource('innertube', _ok);
    final yt = _FakeSource('yt-dlp', _ok);
    await FallbackStreamSource([it, yt]).resolveStream('v');
    expect(yt.calls, isEmpty);
  });

  test('when every source fails the last Err is returned', () async {
    final it = _FakeSource(
      'innertube',
      Err(ytFailure(YtErrorKind.extractor, 'innertube: all failed')),
    );
    final yt = _FakeSource(
      'yt-dlp',
      Err(ytFailure(YtErrorKind.network, 'Unable to connect')),
    );
    final r = await FallbackStreamSource([it, yt]).resolveStream('v');
    expect(ytErrorKindOf((r as Err<YtStream>).failure), YtErrorKind.network);
  });

  group('playbackSources', () {
    final it = _FakeSource('innertube', _ok);
    final yt = _FakeSource('yt-dlp', _ok);

    test('Innertube first, then yt-dlp', () {
      expect(playbackSources(innertube: it, ytDlp: yt), [it, yt]);
    });

    test('forceYtDlp leaves Innertube out', () async {
      final sources = playbackSources(
        innertube: it,
        ytDlp: yt,
        forceYtDlp: true,
      );
      expect(sources, [yt]);
      await FallbackStreamSource(sources).resolveStream('v');
      expect(it.calls, isEmpty);
      expect(yt.calls, ['v']);
    });
  });
}
