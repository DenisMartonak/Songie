import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/audio_handler.dart';
import 'package:songies/player/player_inputs.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_room_hub.dart';
import '../helpers/room_rig.dart';

/// A host and a guest device in one room, the guest with [role]; [body]
/// gets the guest's player, its inputs and the host's player.
void inRoom(
  String name,
  RoomRole role,
  void Function(
    FakeAsync async,
    PlayerService guest,
    PlayerInputs inputs,
    PlayerService host,
  )
  body,
) {
  test(name, () {
    fakeAsync((async) {
      final hub = FakeRoomHub();
      final backend = FakeRoomBackend();
      final hostPlayer = PlayerService(FakeAudioBackend(), RigResolver());
      final guestPlayer = PlayerService(FakeAudioBackend(), RigResolver());
      RoomService service(String id, PlayerService p) => RoomService(
        backend: backend,
        channelFor: (_) => hub.channelFor(id),
        player: p,
        tracksFor: roomTracksFor,
        deviceId: id,
        platform: 'linux',
      );
      final host = service('h', hostPlayer);
      final guest = service('g', guestPlayer);
      host.open(userId: 'u1', name: 'denis', play: [roomTrack('a')]);
      async.elapse(const Duration(seconds: 1));
      guest.join('ABCD2345', userId: 'u2', name: 'me');
      async.elapse(const Duration(seconds: 1));
      if (role != RoomRole.listener) host.setRole('g', role);
      async.elapse(const Duration(seconds: 1));
      expect(guest.status, isA<RoomGuesting>());
      expect(guestPlayer.state.playing, isTrue);
      final inputs = PlayerInputs(guestPlayer, room: () => guest.guestView);
      body(async, guestPlayer, inputs, hostPlayer);
      host.dispose();
      guest.dispose();
      hostPlayer.dispose();
      guestPlayer.dispose();
      async.elapse(const Duration(seconds: 1));
    });
  });
}

void main() {
  final art = ArtCache(Directory.systemTemp.absolute);

  inRoom(
    'a listener\'s media-session pause and skip leave the guest '
    'playing in step',
    RoomRole.listener,
    (async, guest, inputs, host) {
      final handler = SongiesAudioHandler(guest, art, inputs: inputs);
      handler.pause();
      handler.skipToNext();
      handler.customAction(SongiesAudioHandler.shuffleAction);
      async.elapse(const Duration(seconds: 1));
      expect(guest.state.playing, isTrue);
      expect(guest.state.shuffle, isFalse);
      expect(host.state.playing, isTrue);
      handler.dispose();
    },
  );

  inRoom(
    'a listener\'s Space (toggle) and song tap change nothing',
    RoomRole.listener,
    (async, guest, inputs, host) {
      inputs.togglePlay();
      inputs.playQueue([roomTrack('z'), roomTrack('y')]);
      async.elapse(const Duration(seconds: 1));
      expect(guest.state.playing, isTrue);
      expect(guest.state.queue.map((t) => t.id), ['a']);
      expect(host.state.queue.map((t) => t.id), ['a']);
    },
  );

  inRoom(
    'full control: the media session pauses the host, a song tap '
    'plays it there',
    RoomRole.full,
    (async, guest, inputs, host) {
      final handler = SongiesAudioHandler(guest, art, inputs: inputs);
      handler.pause();
      async.elapse(const Duration(seconds: 1));
      expect(host.state.playing, isFalse);
      inputs.playQueue([roomTrack('z')]);
      async.elapse(const Duration(seconds: 1));
      expect(host.state.current?.id, 'z');
      expect(guest.state.current?.id, 'z');
      handler.dispose();
    },
  );

  test('no room: inputs go straight to the player', () {
    fakeAsync((async) {
      final player = PlayerService(FakeAudioBackend(), RigResolver());
      final inputs = PlayerInputs(player);
      inputs.playQueue([roomTrack('a'), roomTrack('b')]);
      async.elapse(const Duration(milliseconds: 100));
      expect(player.state.playing, isTrue);
      inputs.togglePlay();
      inputs.toggleShuffle();
      inputs.cycleRepeat();
      async.elapse(const Duration(milliseconds: 100));
      expect(player.state.playing, isFalse);
      expect(player.state.shuffle, isTrue);
      expect(player.state.repeat, RepeatMode.all);
      player.dispose();
      async.elapse(const Duration(milliseconds: 100));
    });
  });
}
