import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

import '../helpers/fake_ytdlp_runner.dart';

String fixture(String n) => File('test/fixtures/ytdlp/$n').readAsStringSync();

const id = '4D7u5KF7SP8';
const jsWarning =
    'WARNING: [youtube] No supported JavaScript runtime could be found.';

YtErrorKind kindOf<T>(Result<T> r) {
  expect(r, isA<Err<T>>());
  return ytErrorKindOf((r as Err<T>).failure)!;
}

void main() {
  late FakeYtDlpRunner runner;
  late YtDlpClient client;
  late Directory dir;

  setUp(() {
    runner = FakeYtDlpRunner();
    client = YtDlpClient(runner);
    dir = Directory.systemTemp.createTempSync('ytdl');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The probe's stdout with its output dir pointed at [dir].
  String stdout() =>
      fixture('download_stdout.txt')
          .replaceAll('@OUTDIR@', dir.path.replaceAll(r'\', r'\\'));

  test('downloads: args, ordered progress, parsed result', () async {
    File('${dir.path}/$id.webm').writeAsBytesSync(List.filled(1234, 7));
    runner.onOk('watch?v=', stdout(), stderr: jsWarning);
    final progress = <(int, int?)>[];
    final r = await client.download(
      id,
      dir,
      processId: 'dl-1',
      onProgress: (d, t) => progress.add((d, t)),
    );

    expect(runner.calls.single, [
      '-f',
      'bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio',
      '--no-playlist',
      '--continue',
      '--no-mtime',
      '--newline',
      '--progress',
      '--progress-template',
      'download:songies-progress %(progress.downloaded_bytes)s '
          '%(progress.total_bytes)s %(progress.total_bytes_estimate)s',
      '-o',
      '${dir.path}${Platform.pathSeparator}%(id)s.%(ext)s',
      '--print',
      'after_move:songies-done '
          '%(.{filepath,title,artist,track,album,duration})j',
      'https://music.youtube.com/watch?v=$id',
    ]);
    expect(runner.processIds.single, 'dl-1');

    expect(progress, isNotEmpty);
    expect(progress.first, (1024, 6214234));
    expect(progress.last, (6214234, 6214234));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i].$1, greaterThan(progress[i - 1].$1));
    }

    final d = (r as Ok<YtDownload>).value;
    expect(d.path, '${dir.path}/$id.webm');
    expect(d.bytes, 1234);
    expect(d.title, 'Get Lucky (feat. Pharrell Williams and Nile Rodgers)');
    expect(d.artist, 'Daft Punk, Pharrell Williams, Nile Rodgers');
    expect(d.album, 'Random Access Memories');
    expect(d.durationMs, 370000);
  });

  test('track wins over title; Topic suffix and NA are cleaned', () async {
    final f = File('${dir.path}/x.m4a')..writeAsBytesSync([1, 2, 3]);
    final path = f.path.replaceAll(r'\', r'\\');
    runner.onOk(
      'watch?v=',
      'songies-progress NA NA 99.5\n'
          'songies-progress 3 NA 99.5\n'
          'songies-done {"filepath": "$path", "title": "Video title", '
          '"track": "Song", "artist": "Band - Topic", "album": "NA", '
          '"duration": 12.4}\n',
    );
    final progress = <(int, int?)>[];
    final r = await client.download(
      'x',
      dir,
      processId: 'p',
      onProgress: (d, t) => progress.add((d, t)),
    );
    expect(progress, [(3, 100)]);
    final d = (r as Ok<YtDownload>).value;
    expect(d.title, 'Song');
    expect(d.artist, 'Band');
    expect(d.album, isNull);
    expect(d.durationMs, 12400);
    expect(d.bytes, 3);
  });

  test('done line missing from onLine is read from stdout', () async {
    File('${dir.path}/$id.webm').writeAsBytesSync(List.filled(55, 1));
    runner
      ..replayLines = false
      ..onOk('watch?v=', stdout());
    final r = await client.download(id, dir, processId: 'p');
    final d = (r as Ok<YtDownload>).value;
    expect(d.path, '${dir.path}/$id.webm');
    expect(d.bytes, 55);
    expect(d.album, 'Random Access Memories');
  });

  test('429 fixture is throttled', () async {
    runner.on('watch?v=', YtDlpRun(1, '', fixture('download_stderr_429.txt')));
    final r = await client.download(id, dir, processId: 'p');
    expect(kindOf(r), YtErrorKind.throttled);
    expect((r as Err).failure.kind, FailureKind.network);
  });

  test('no-space fixture is diskFull', () async {
    runner.on(
      'watch?v=',
      YtDlpRun(1, '', fixture('download_stderr_nospace.txt')),
    );
    final r = await client.download(id, dir, processId: 'p');
    expect(kindOf(r), YtErrorKind.diskFull);
    expect((r as Err).failure.kind, FailureKind.io);
  });

  test('a bare OSError Errno 28 is diskFull too', () {
    expect(
      classifyYtDlpStderr(
        'OSError: [Errno 28] No space left on device: \'/x/y.webm.part\'',
      ),
      YtErrorKind.diskFull,
    );
  });

  test('exit 0 without a done line is unknown', () async {
    runner.onOk('watch?v=', 'songies-progress 1 2 NA\n');
    expect(
      kindOf(await client.download(id, dir, processId: 'p')),
      YtErrorKind.unknown,
    );
  });

  test('done line pointing at a missing file is unknown', () async {
    runner.onOk(
      'watch?v=',
      'songies-done {"filepath": "${dir.path}/gone.webm"}\n',
    );
    expect(
      kindOf(await client.download(id, dir, processId: 'p')),
      YtErrorKind.unknown,
    );
  });

  test('stall: no output for 2 min cancels the process -> network', () {
    fakeAsync((async) {
      runner.onHang('watch?v=');
      Result<YtDownload>? r;
      client.download(id, dir, processId: 'dl-9').then((v) => r = v);
      async.elapse(const Duration(minutes: 1, seconds: 59));
      expect(runner.cancelled, isEmpty);
      expect(r, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(runner.cancelled, ['dl-9']);
      expect(r, isNotNull);
      expect(kindOf(r!), YtErrorKind.network);
    });
  });

  test('YtDlpMissing maps to missingBinary', () async {
    runner.throwOnRun = const YtDlpMissing();
    expect(
      kindOf(await client.download(id, dir, processId: 'p')),
      YtErrorKind.missingBinary,
    );
  });
}
