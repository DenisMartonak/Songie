import 'dart:async';
import 'dart:io';

import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/library/yt_tracks.dart';
import 'package:songies/player/radio_controller.dart';
import 'package:songies/youtube/thumbnail_fetcher.dart';

/// A YouTube Music search the test answers: [answers] by (query, kind), else
/// an empty page. A (query, kind) with a [gates] entry waits for it first.
class FakeYtmService implements YtmService {
  final calls = <(String, YtmSearchKind)>[];
  final answers = <(String, YtmSearchKind), Result<YtmSearchPage>>{};
  final gates = <(String, YtmSearchKind), Completer<void>>{};

  /// Answers (query, kind) with [items].
  void answer(String query, YtmSearchKind kind, List<Object> items) =>
      answers[(query, kind)] = Ok(YtmSearchPage(items, null));

  @override
  Future<Result<YtmSearchPage>> search(
    String query,
    YtmSearchKind kind, {
    String? continuation,
  }) async {
    calls.add((query, kind));
    final gate = gates[(query, kind)];
    if (gate != null) await gate.future;
    return answers[(query, kind)] ?? const Ok(YtmSearchPage([], null));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records the songs played with radio (and radios started from tracks).
class RecordingRadioController implements RadioController {
  final played = <YtmSong>[];
  final started = <Track>[];

  @override
  Future<void> playWithRadio(YtmSong seed) async => played.add(seed);

  @override
  Future<void> startRadio(Track t) async => started.add(t);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The real store on the test db, recording upserts. Songs without a
/// thumbnail never fetch one, so nothing touches the network.
class RecordingYtTrackStore extends YtTrackStore {
  RecordingYtTrackStore(AppDatabase db, SyncStamp stamp)
    : super(
        db,
        stamp,
        ThumbnailFetcher(
          ArtCache(Directory.systemTemp),
          (_) async => throw StateError('tests never touch the network'),
        ),
      );

  final upserted = <String>[];

  @override
  Future<Result<Track>> upsert(YtmSong s) {
    upserted.add(s.videoId);
    return super.upsert(s);
  }
}
