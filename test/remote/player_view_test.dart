import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/remote/player_view.dart';
import 'package:songies/remote/remote_controller.dart';
import 'package:songies/remote/remote_protocol.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_remote_hub.dart';

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

RemotePresence presenceOf(String id) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: false,
);

List<String> ids(List<Track> q) => [for (final t in q) t.id];

void main() {
  group('LocalPlayerView', () {
    late FakeAudioBackend backend;
    late PlayerService player;
    late LocalPlayerView view;

    setUp(() {
      backend = FakeAudioBackend();
      player = PlayerService(backend, _Resolver());
      view = LocalPlayerView(player);
    });
    tearDown(() => player.dispose());

    test('is not remote and shows the player state', () {
      expect(view.isRemote, isFalse);
      expect(view.state, same(player.state));
    });

    test('passes each call through', () async {
      await view.playTracks([track('a'), track('b'), track('c')]);
      expect(ids(player.state.queue), ['a', 'b', 'c']);
      expect(player.state.playing, isTrue);

      await view.pause();
      expect(player.state.playing, isFalse);
      await view.play();
      expect(player.state.playing, isTrue);
      await view.togglePlay();
      expect(player.state.playing, isFalse);

      await view.next();
      expect(player.state.index, 1);
      await view.previous();
      expect(player.state.index, 0);
      await view.playAt(2);
      expect(player.state.index, 2);

      await view.seek(const Duration(seconds: 3));
      expect(backend.calls, contains('seek:3000'));
      await view.setVolume(0.5);
      expect(player.state.volume, 0.5);
      await view.setShuffle(true);
      expect(player.state.shuffle, isTrue);
      await view.setShuffle(false);

      await view.move(0, 1);
      expect(ids(player.state.queue), ['b', 'a', 'c']);
      await view.removeAt(0);
      expect(ids(player.state.queue), ['a', 'c']);

      await view.addNext([track('n')]);
      expect(ids(player.state.queue), ['a', 'c', 'n']);
      await view.addToEnd([track('e')]);
      expect(ids(player.state.queue).last, 'e');
    });

    test(
      'addNext queues after the current song, addToEnd at the end',
      () async {
        await view.playTracks([track('a'), track('b')]);
        await view.addNext([track('n')]);
        await view.addToEnd([track('e')]);
        expect(ids(player.state.queue), ['a', 'n', 'b', 'e']);
      },
    );

    test('playTracks starts at startIndex', () async {
      await view.playTracks([track('a'), track('b')], startIndex: 1);
      expect(player.state.current?.id, 'b');
    });

    test('setRepeat cycles until the mode matches', () async {
      expect(player.state.repeat, RepeatMode.off);
      await view.setRepeat(RepeatMode.all);
      expect(player.state.repeat, RepeatMode.all);
      await view.setRepeat(RepeatMode.off);
      expect(player.state.repeat, RepeatMode.off);
      await view.setRepeat(RepeatMode.one);
      expect(player.state.repeat, RepeatMode.one);
      await view.setRepeat(RepeatMode.one);
      expect(player.state.repeat, RepeatMode.one);
    });
  });

  group('RemotePlayerView', () {
    late FakeRemoteHub hub;
    late RemoteController controller;
    late List<String> order;
    late RemotePlayerView view;
    Object? syncError;

    List<RemoteCommand> commands() =>
        hub.sent.whereType<RemoteCommand>().toList();

    setUp(() async {
      hub = FakeRemoteHub();
      order = [];
      syncError = null;
      await hub.channelFor('h').join(presenceOf('h'));
      await hub.channelFor('c').join(presenceOf('c'));
      controller = RemoteController(
        channel: hub.channelFor('c'),
        deviceId: 'c',
        lookup: (_) async => const {},
      );
      await controller.select(presenceOf('h'));
      view = RemotePlayerView(controller, () async {
        order.add('sync:${commands().length}');
        final e = syncError;
        if (e != null) throw e;
      });
    });
    tearDown(() => controller.dispose());

    test('is remote and shows the controller state', () {
      expect(view.isRemote, isTrue);
      expect(view.state, controller.state);
    });

    test('addNext calls syncNow, then sends addNext with the ids', () async {
      await view.addNext([track('a'), track('b')]);
      expect(order, ['sync:0']);
      final sent = commands();
      expect(sent, hasLength(1));
      expect(sent.single.op, RemoteOp.addNext);
      expect(sent.single.to, 'h');
      expect(sent.single.args['ids'], ['a', 'b']);
    });

    test('addToEnd and playTracks sync first and send ids', () async {
      await view.addToEnd([track('e')]);
      await view.playTracks(
        [track('a'), track('b')],
        startIndex: 1,
        sourcePlaylistId: 'p1',
      );
      expect(order, ['sync:0', 'sync:1']);
      final sent = commands();
      expect(sent[0].op, RemoteOp.addToEnd);
      expect(sent[0].args['ids'], ['e']);
      expect(sent[1].op, RemoteOp.playTracks);
      expect(sent[1].args, {
        'ids': ['a', 'b'],
        'start': 1,
        'playlist': 'p1',
      });
    });

    test('a failing syncNow still sends the command', () async {
      syncError = StateError('offline');
      await view.addNext([track('a')]);
      expect(commands().single.op, RemoteOp.addNext);
    });

    test('transport calls go to the controller', () async {
      await view.pause();
      await view.setRepeat(RepeatMode.one);
      await view.setShuffle(true);
      expect(order, isEmpty);
      expect(
        [for (final c in commands()) c.op],
        [RemoteOp.pause, RemoteOp.repeat, RemoteOp.shuffle],
      );
    });
  });
}
