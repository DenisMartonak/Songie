import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

import '../helpers/fake_ytdlp_runner.dart';

String fixture(String n) => File('test/fixtures/ytdlp/$n').readAsStringSync();

const url = 'https://music.youtube.com/playlist?list=PLx';
const jsWarning =
    'WARNING: [youtube] No supported JavaScript runtime could be found.';

YtErrorKind kindOf<T>(Result<T> r) {
  expect(r, isA<Err<T>>());
  return ytErrorKindOf((r as Err<T>).failure)!;
}

void main() {
  late FakeYtDlpRunner runner;
  late YtDlpClient client;
  setUp(() {
    runner = FakeYtDlpRunner();
    client = YtDlpClient(runner);
  });

  test('fetchPlaylist parses stdout, ignores warnings, uses 10 min', () async {
    runner.onOk(
      '--flat-playlist',
      fixture('playlist_flat.json'),
      stderr:
          'WARNING: [youtube:tab] YouTube Music is not directly '
          'supported. Redirecting\n$jsWarning',
    );
    final r = await client.fetchPlaylist(url);
    expect(r, isA<Ok<YtPlaylist>>());
    expect((r as Ok<YtPlaylist>).value.entries, hasLength(5));
    expect(runner.calls.single, ['--flat-playlist', '-J', url]);
    expect(runner.timeouts.single, const Duration(minutes: 10));
  });

  test('fetchPlaylist: exit 0 without entries is notAPlaylist', () async {
    runner.onOk('--flat-playlist', '{"id":"v","title":"t","formats":[]}');
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.notAPlaylist);
  });

  test('fetchPlaylist: garbage stdout is extractor', () async {
    runner.onOk('--flat-playlist', 'not json');
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.extractor);
  });

  test('resolveStream builds args, parses, uses 60 s', () async {
    runner.onOk('watch?v=', fixture('stream_opus.json'), stderr: jsWarning);
    final r = await client.resolveStream('fOT0BUpITw8');
    expect(r, isA<Ok<YtStream>>());
    expect(runner.calls.single, [
      '-J',
      '--no-playlist',
      '-f',
      'bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio',
      'https://music.youtube.com/watch?v=fOT0BUpITw8',
    ]);
    expect(runner.timeouts.single, const Duration(seconds: 60));
  });

  test('stdout is not decoded when the exit code is non-zero', () async {
    runner.on(
      '--flat-playlist',
      YtDlpRun(1, fixture('playlist_flat.json'), 'ERROR: [youtube] x: boom'),
    );
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.extractor);
  });

  group('stderr mapping', () {
    final cases = <String, YtErrorKind>{
      'ERROR: [youtube:tab] PLx: YouTube said: The playlist does not exist.':
          YtErrorKind.notFound,
      'ERROR: [youtube] abc: This video is unavailable': YtErrorKind.notFound,
      'ERROR: [youtube] abc: Private video. If the owner of this video has '
              'granted you access, please sign in.':
          YtErrorKind.notFound,
      "ERROR: [youtube] abc: This video has been removed for violating "
              "YouTube's Terms of Service":
          YtErrorKind.notFound,
      'WARNING: HTTP Error 404\nERROR: [youtube:tab] x: Unable to download '
              'API page: HTTP Error 400: Bad Request':
          YtErrorKind.notFound,
      'ERROR: [generic] foo: Unable to download webpage: HTTP Error 404: '
              'Not Found':
          YtErrorKind.notFound,
      "WARNING: Unable to connect to proxy\nERROR: [youtube:tab] x: Unable "
              "to download API page: ('Unable to connect to proxy', "
              "NewConnectionError())":
          YtErrorKind.network,
      'ERROR: [youtube:tab] x: Unable to download webpage: '
              '<urlopen error [Errno -3] Temporary failure>':
          YtErrorKind.network,
      'ERROR: [youtube] x: Sign in to confirm you are not a bot':
          YtErrorKind.extractor,
      'something odd with no marker': YtErrorKind.unknown,
      'ERROR: [youtube] abc: The uploader has not made this video available '
              'in your country':
          YtErrorKind.notFound,
      'ERROR: [youtube] abc: This video is not available in your country':
          YtErrorKind.notFound,
      'ERROR: [youtube] abc: Sign in to confirm your age. This video may be '
              'inappropriate for some users.':
          YtErrorKind.notFound,
      'ERROR: [youtube] abc: This video is age-restricted':
          YtErrorKind.notFound,
      'ERROR: [youtube] abc: Unable to download API page: HTTP Error 400: '
              'Bad Request':
          YtErrorKind.extractor,
    };
    cases.forEach((stderr, kind) {
      test('$kind <- ${stderr.split('\n').last}', () async {
        runner.onFail('--flat-playlist', stderr);
        expect(kindOf(await client.fetchPlaylist(url)), kind);
      });
    });

    test('same mapping for resolveStream', () async {
      runner.onFail(
        'watch?v=',
        'ERROR: [youtube] a: This video is unavailable',
      );
      expect(kindOf(await client.resolveStream('a')), YtErrorKind.notFound);
    });

    test('FailureKind mapping on a real Err', () async {
      runner.onFail('--flat-playlist', 'ERROR: x: Unable to connect');
      final r = await client.fetchPlaylist(url) as Err;
      expect(r.failure.kind, FailureKind.network);
      expect(r.failure.message, startsWith('ytdlp:network:'));
    });
  });

  test('YtDlpMissing maps to missingBinary', () async {
    runner.throwOnRun = const YtDlpMissing();
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.missingBinary);
    expect(kindOf(await client.resolveStream('a')), YtErrorKind.missingBinary);
  });

  test('other throws map to unknown, timeouts to network', () async {
    runner.throwOnRun = StateError('x');
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.unknown);
    runner.throwOnRun = TimeoutException('slow');
    expect(kindOf(await client.fetchPlaylist(url)), YtErrorKind.network);
    expect(kindOf(await client.resolveStream('a')), YtErrorKind.network);
  });
}
