import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/composite_track_resolver.dart';
import 'package:songies/player/stream_resolver.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';

import '../helpers/fake_network_status.dart';
import '../helpers/fake_ytdlp_runner.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late FakeYtDlpRunner runner;
  late StreamResolver streams;
  late Directory tmp;
  late List<(Track, YtStream)> metadata;
  late CompositeTrackResolver resolver;

  setUp(() async {
    db = testDb();
    runner = FakeYtDlpRunner()
      ..onOk(
        'watch?v=vid1',
        '{"url":"https://rr.example/a","http_headers":{"X":"y"},'
            '"title":"New","channel":"Ch","duration":10}',
      );
    streams = StreamResolver(
      YtDlpClient(runner),
      FakeNetworkStatus(),
      SettingsRepository(db),
      wifiOnlyFallback: false,
    );
    tmp = await Directory.systemTemp.createTemp('composite_test');
    metadata = [];
    resolver = CompositeTrackResolver(
      LocalTrackResolver(db),
      streams,
      onStreamMetadata: (t, s) async => metadata.add((t, s)),
    );
  });
  tearDown(() async {
    streams.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<Track> insert({
    required String id,
    String source = 'yt',
    String? videoId,
    bool unavailable = false,
  }) async {
    await db
        .into(db.tracks)
        .insert(
          trackRow(
            id: id,
            source: source,
            ytVideoId: videoId,
          ).copyWith(unavailable: Value(unavailable)),
        );
    return (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingle();
  }

  test('a local file wins over the stream', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    final f = File('${tmp.path}/a.mp3')..writeAsStringSync('x');
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: t.id,
            path: f.path,
            state: 'done',
            bytes: 1,
            mtimeMs: 1,
          ),
        );
    final r = await resolver.resolve(t) as Ok<AudioSourceRef>;
    expect(r.value, FileSource(f.path));
    expect(runner.calls, isEmpty);
  });

  test('yt without a file resolves to a UrlSource with headers', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    final r = await resolver.resolve(t) as Ok<AudioSourceRef>;
    final src = r.value as UrlSource;
    expect(src.url.toString(), 'https://rr.example/a');
    expect(src.headers, {'X': 'y'});
    expect(metadata, hasLength(1));
    expect(metadata.single.$2.title, 'New');
  });

  test('unavailable is notFound with no runner call', () async {
    final t = await insert(id: 't1', videoId: 'vid1', unavailable: true);
    final r = await resolver.resolve(t) as Err<AudioSourceRef>;
    expect(r.failure.kind, FailureKind.notFound);
    expect(runner.calls, isEmpty);
  });

  test('a local track without a file returns the local Err', () async {
    final t = await insert(id: 't2', source: 'local');
    final r = await resolver.resolve(t) as Err<AudioSourceRef>;
    expect(r.failure.kind, FailureKind.notFound);
    expect(runner.calls, isEmpty);
  });

  test('a stream failure is returned and no metadata is reported', () async {
    final t = await insert(id: 't3', videoId: 'zzz');
    final r = await resolver.resolve(t);
    expect(r, isA<Err<AudioSourceRef>>());
    expect(metadata, isEmpty);
  });

  test('a throwing onStreamMetadata does not fail the resolve', () async {
    resolver = CompositeTrackResolver(
      LocalTrackResolver(db),
      streams,
      onStreamMetadata: (t, s) async => throw StateError('boom'),
    );
    final t = await insert(id: 't1', videoId: 'vid1');
    expect(await resolver.resolve(t), isA<Ok<AudioSourceRef>>());
  });

  test('prefetch warms the cache for yt tracks only', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    final l = await insert(id: 't2', source: 'local');
    await resolver.prefetch(l);
    expect(runner.calls, isEmpty);
    await resolver.prefetch(t);
    await resolver.resolve(t);
    expect(runner.calls, hasLength(1));
  });

  test('prefetch skips tracks with a local file', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    final f = File('${tmp.path}/a.mp3')..writeAsStringSync('x');
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            trackId: t.id,
            path: f.path,
            state: 'done',
            bytes: 1,
            mtimeMs: 1,
          ),
        );
    await resolver.prefetch(t);
    expect(runner.calls, isEmpty);
  });

  test('invalidate forces a re-resolve', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    await resolver.resolve(t);
    resolver.invalidate(t);
    await resolver.resolve(t);
    expect(runner.calls, hasLength(2));
  });

  Future<void> ytRow(String trackId, String path, String state) => db
      .into(db.localFiles)
      .insert(
        LocalFilesCompanion.insert(
          trackId: trackId,
          path: path,
          state: state,
          bytes: 0,
          mtimeMs: 0,
        ),
      );

  test('a downloading yt row (path empty) streams', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    await ytRow(t.id, '', 'downloading');
    final r = await resolver.resolve(t) as Ok<AudioSourceRef>;
    expect(r.value, isA<UrlSource>());
  });

  test('a done yt row with an existing file plays the file', () async {
    final t = await insert(id: 't1', videoId: 'vid1');
    final f = File('${tmp.path}/vid1.opus')..writeAsStringSync('x');
    await ytRow(t.id, f.path, 'done');
    final r = await resolver.resolve(t) as Ok<AudioSourceRef>;
    expect(r.value, FileSource(f.path));
    expect(runner.calls, isEmpty);
  });

  test(
    'an unfinished yt row is never promoted to done by the resolver',
    () async {
      final t = await insert(id: 't1', videoId: 'vid1');
      final f = File('${tmp.path}/vid1.part')..writeAsStringSync('x');
      await ytRow(t.id, f.path, 'queued');
      final r = await resolver.resolve(t) as Ok<AudioSourceRef>;
      expect(r.value, isA<UrlSource>());
      final row = await db.select(db.localFiles).getSingle();
      expect(row.state, 'queued');
    },
  );
}
