import 'dart:async';
import 'dart:io';

import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_session_store.dart';
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

  /// Home feed requests (their continuation, and the session each went
  /// out with), answered with [homeAnswer] (or [signedInHomeAnswer] for a
  /// signed-in request, when set) after [homeGate] (when set) completes.
  final homeCalls = <String?>[];
  final homeSessions = <YtSession?>[];
  Result<YtmHome> homeAnswer = const Ok(YtmHome([], null));
  Result<YtmHome>? signedInHomeAnswer;
  Completer<void>? homeGate;

  @override
  Future<Result<YtmHome>> home({
    String? continuation,
    YtSession? session,
  }) async {
    homeCalls.add(continuation);
    homeSessions.add(session);
    final gate = homeGate;
    if (gate != null) await gate.future;
    if (session != null) return signedInHomeAnswer ?? homeAnswer;
    return homeAnswer;
  }

  /// Artist, album and playlist requests (`artist:ID`, `album:ID`,
  /// `playlist:ID` and `playlist:ID@CONTINUATION`), answered from the
  /// maps (keyed the same way, without the kind) after [browseGate] (when
  /// set) completes, else with an error.
  final browseCalls = <String>[];
  final artistAnswers = <String, Result<YtmArtistPage>>{};
  final albumAnswers = <String, Result<YtmAlbumPage>>{};
  final playlistAnswers = <String, Result<YtmPlaylistPage>>{};
  Completer<void>? browseGate;

  Future<Result<T>> _browse<T>(
    String kind,
    String key,
    Map<String, Result<T>> answers,
  ) async {
    browseCalls.add('$kind:$key');
    final gate = browseGate;
    if (gate != null) await gate.future;
    return answers[key] ??
        Err(Failure(FailureKind.unknown, 'no $kind answer for $key'));
  }

  @override
  Future<Result<YtmArtistPage>> artist(String browseId) =>
      _browse('artist', browseId, artistAnswers);

  @override
  Future<Result<YtmAlbumPage>> album(String browseId) =>
      _browse('album', browseId, albumAnswers);

  @override
  Future<Result<YtmPlaylistPage>> playlist(
    String browseId, {
    String? continuation,
  }) => _browse(
    'playlist',
    continuation == null ? browseId : '$browseId@$continuation',
    playlistAnswers,
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records the songs played with radio (and radios started from tracks,
/// with the radio playlist each asked for in [startedPlaylists]).
class RecordingRadioController implements RadioController {
  final played = <YtmSong>[];
  final started = <Track>[];
  final startedPlaylists = <String?>[];

  @override
  Future<void> playWithRadio(YtmSong seed) async => played.add(seed);

  @override
  Future<void> startRadio(Track t, {String? playlistId}) async {
    started.add(t);
    startedPlaylists.add(playlistId);
  }

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

/// An in-memory secure store (always available).
class FakeYtSessionStore implements YtSessionStore {
  YtSession? stored;
  int reads = 0;

  /// Whether the keyring answers; false stands in for a missing or locked one.
  bool isAvailable = true;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<YtSession?> read() async {
    reads++;
    return stored;
  }

  /// Make the keyring fail to write or to clear.
  bool writeThrows = false;
  bool clearThrows = false;

  @override
  Future<void> write(YtSession s) async {
    if (writeThrows) throw StateError('keyring write failed');
    stored = s;
  }

  @override
  Future<void> clear() async {
    if (clearThrows) throw StateError('keyring clear failed');
    stored = null;
  }
}
