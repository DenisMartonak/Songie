import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';
import 'package:songies/library/yt_tracks.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/radio_controller.dart';
import 'package:songies/player/track_resolver.dart';

import '../helpers/fake_audio_backend.dart';

Track ytTrack(String videoId, {String? title}) => Track(
  id: 'id-$videoId',
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'yt',
  ytVideoId: videoId,
  title: title ?? 'Title $videoId',
  artist: 'Artist',
  durationMs: 200000,
  unavailable: false,
  searchText: 'title $videoId artist',
);

Track localTrack(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 200000,
  unavailable: false,
  searchText: 'title $id artist',
);

YtmSong song(String id) => YtmSong(videoId: id, title: 'Song $id');

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

/// Records radio calls; each answer waits for [gate] when set.
class FakeYtm implements YtmService {
  final calls = <String>[];
  final answers = <String, Result<YtmRadio>>{};
  Completer<void>? gate;

  /// The radio playlist each first-page request asked for (null: the seed's).
  final playlists = <String?>[];

  @override
  Future<Result<YtmRadio>> radio(
    String videoId, {
    String? continuation,
    String? playlistId,
  }) async {
    final key = continuation == null ? videoId : 'cont:$continuation';
    calls.add(key);
    if (continuation == null) playlists.add(playlistId);
    final g = gate;
    if (g != null) await g.future;
    return answers[key] ??
        Err(Failure(FailureKind.network, 'no answer for $key'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeStore implements YtTrackStore {
  final upgrades = <String>[];
  bool failUpsert = false;

  @override
  Future<Result<Track>> upsert(YtmSong s) async => failUpsert
      ? Err(Failure(FailureKind.unknown, 'db'))
      : Ok(ytTrack(s.videoId, title: s.title));

  @override
  Future<List<Track>> upsertAll(List<YtmSong> s) async => [
    for (final x in s) ytTrack(x.videoId, title: x.title),
  ];

  @override
  Future<void> upgradeFrom(Track t, YtmSong rich) async =>
      upgrades.add('${t.id}<-${rich.videoId}');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<String> ids(List<Track> q) => [for (final t in q) t.id];

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  late FakeYtm ytm;
  late FakeStore store;
  late RadioController radio;

  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
    backend = FakeAudioBackend();
    player = PlayerService(backend, _Resolver(), random: Random(1));
    ytm = FakeYtm();
    store = FakeStore();
    radio = RadioController(player, ytm, store);
  });

  tearDown(() async {
    await radio.dispose();
    await player.dispose();
  });

  YtmRadio page(List<String> songIds, {String? cont, YtmSong? current}) =>
      YtmRadio([for (final i in songIds) song(i)], cont, current: current);

  /// Plays [index] in the queue and lets the engine report progress.
  Future<void> reach(int index) async {
    await player.playAt(index);
    backend.setPosition(const Duration(seconds: 1));
    await pumpEventQueue();
  }

  group('playWithRadio', () {
    test(
      'starts the seed before the radio answers, then fills the queue',
      () async {
        ytm.gate = Completer<void>();
        ytm.answers['s'] = Ok(page(['r1', 'r2', 'r3'], cont: 'c1'));

        final done = radio.playWithRadio(song('s'));
        await pumpEventQueue();

        expect(ytm.calls, ['s']);
        expect(ids(player.state.queue), ['id-s']);
        expect(player.state.playing, isTrue);
        expect(backend.sources, ['/music/id-s.mp3']);

        ytm.gate!.complete();
        await done;
        expect(player.state.queue, hasLength(1 + 3));
        expect(ids(player.state.queue), ['id-s', 'id-r1', 'id-r2', 'id-r3']);
        expect(player.state.index, 0);
      },
    );

    test('upgrades the seed from the radio\'s current song', () async {
      final rich = song('s');
      ytm.answers['s'] = Ok(page(['r1'], current: rich));
      await radio.playWithRadio(song('s'));
      expect(store.upgrades, ['id-s<-s']);
    });

    test(
      'a radio error leaves the seed playing alone, with no notice',
      () async {
        await radio.playWithRadio(song('s'));
        expect(ids(player.state.queue), ['id-s']);
        expect(player.state.playing, isTrue);
        expect(player.state.notice, isNull);
        expect(player.state.error, isNull);
      },
    );

    test(
      'a seed that cannot be stored plays nothing and asks nothing',
      () async {
        store.failUpsert = true;
        await radio.playWithRadio(song('s'));
        expect(player.state.queue, isEmpty);
        expect(ytm.calls, isEmpty);
      },
    );

    test('a radio that answers after the user played something else is '
        'dropped', () async {
      ytm.gate = Completer<void>();
      ytm.answers['s'] = Ok(page(['r1', 'r2']));
      final done = radio.playWithRadio(song('s'));
      await pumpEventQueue();
      await player.playQueue([localTrack('a'), localTrack('b')]);
      ytm.gate!.complete();
      await done;
      expect(ids(player.state.queue), ['a', 'b']);
    });
  });

  group('continuation', () {
    test('reaching the second-to-last song fetches it exactly once', () async {
      ytm.answers['s'] = Ok(page(['r1', 'r2', 'r3'], cont: 'c1'));
      ytm.answers['cont:c1'] = Ok(page(['r4', 'r5']));
      await radio.playWithRadio(song('s'));

      await reach(1);
      expect(ytm.calls, ['s']);

      await reach(2); // second-to-last of 4
      backend.setPosition(const Duration(seconds: 2));
      backend.setPosition(const Duration(seconds: 3));
      await pumpEventQueue();

      expect(ytm.calls, ['s', 'cont:c1']);
      expect(ids(player.state.queue), [
        'id-s', 'id-r1', 'id-r2', 'id-r3', 'id-r4', 'id-r5', //
      ]);

      await reach(4);
      expect(ytm.calls, ['s', 'cont:c1']); // the last page had no token
    });

    test('is not fetched while paused, only once playing again', () async {
      ytm.gate = Completer<void>();
      ytm.answers['s'] = Ok(page(['r1'], cont: 'c1'));
      ytm.answers['cont:c1'] = Ok(page(['r2']));
      final done = radio.playWithRadio(song('s'));
      await pumpEventQueue();
      await player.pause();
      ytm.gate!.complete();
      ytm.gate = null;
      await done;
      // The seed is now second-to-last of 2, but nothing plays.
      expect(player.state.queue, hasLength(2));
      backend.setPosition(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(ytm.calls, ['s']);

      await player.play();
      await pumpEventQueue();
      expect(ytm.calls, ['s', 'cont:c1']);
      expect(ids(player.state.queue), ['id-s', 'id-r1', 'id-r2']);
    });

    test('a normal playlist never fetches a continuation', () async {
      ytm.answers['s'] = Ok(page(['r1', 'r2', 'r3'], cont: 'c1'));
      await radio.playWithRadio(song('s'));
      final list = [
        for (final i in ['a', 'b', 'c', 'd']) localTrack(i),
      ];
      await player.playQueue(list);
      for (var i = 0; i < list.length; i++) {
        await reach(i);
      }
      expect(ytm.calls, ['s']);
    });

    test('drops songs already in the radio queue', () async {
      ytm.answers['s'] = Ok(page(['r1', 'r2'], cont: 'c1'));
      ytm.answers['cont:c1'] = Ok(page(['r2', 's', 'r3']));
      await radio.playWithRadio(song('s'));
      await reach(1);
      expect(ids(player.state.queue), ['id-s', 'id-r1', 'id-r2', 'id-r3']);
    });
  });

  group('startRadio', () {
    test('plays an existing YouTube track and queues its radio', () async {
      final t = ytTrack('v9');
      ytm.answers['v9'] = Ok(page(['r1', 'r2'], current: song('v9')));
      await radio.startRadio(t);
      expect(ids(player.state.queue), ['id-v9', 'id-r1', 'id-r2']);
      expect(store.upgrades, ['id-v9<-v9']);
    });

    test('from an artist\'s radio playlist: asks for that playlist, seed '
        'first', () async {
      final t = ytTrack('v9');
      ytm.answers['v9'] = Ok(page(['r1', 'r2'], current: song('v9')));
      await radio.startRadio(t, playlistId: 'RDEMartist');
      expect(ytm.playlists, ['RDEMartist']);
      expect(ids(player.state.queue), ['id-v9', 'id-r1', 'id-r2']);
    });

    test('a local track has no radio: nothing changes', () async {
      await player.playQueue([localTrack('a'), localTrack('b')]);
      await radio.startRadio(localTrack('z'));
      expect(ids(player.state.queue), ['a', 'b']);
      expect(ytm.calls, isEmpty);
    });
  });
}
