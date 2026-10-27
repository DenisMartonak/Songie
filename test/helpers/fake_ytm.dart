import 'dart:async';
import 'dart:io';

import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/innertube/innertube_client.dart';
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

  /// Home feed requests (their continuation), answered with [homeAnswer]
  /// after [homeGate] (when set) completes.
  final homeCalls = <String?>[];
  Result<YtmHome> homeAnswer = const Ok(YtmHome([], null));
  Completer<void>? homeGate;

  @override
  Future<Result<YtmHome>> home({String? continuation}) async {
    homeCalls.add(continuation);
    final gate = homeGate;
    if (gate != null) await gate.future;
    return homeAnswer;
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

/// An Innertube client the test drives: [askForConsent] emits on
/// [consentRequired]; consent and visitor resets are recorded. [given]
/// stands for the device-local flag, so it outlives one app (ProviderScope).
class FakeInnertubeClient implements InnertubeClient {
  final _consent = StreamController<bool>.broadcast();
  bool given = false;
  int accepts = 0;
  int resets = 0;

  void askForConsent() => _consent.add(true);

  @override
  Stream<bool> get consentRequired => _consent.stream;

  @override
  Future<bool> consentGiven() async => given;

  @override
  Future<void> acceptConsent() async {
    accepts++;
    given = true;
  }

  @override
  Future<void> resetVisitor() async => resets++;

  @override
  void dispose() => _consent.close();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
