import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/room/room_channel.dart';
import 'package:songies/room/room_protocol.dart';

/// One message of every [RoomMessage] kind; the switch is exhaustive, so a
/// new kind does not compile until it is added here.
RoomMessage sampleOf(RoomMessage m) => switch (m) {
  RoomStateMsg() => m,
  RoomBeatMsg() => m,
  RoomRolesMsg() => m,
  RoomRequestMsg() => m,
  RoomHelloMsg() => m,
  RoomKickMsg() => m,
  RoomEndMsg() => m,
};

const List<RoomMessage> samples = [
  RoomStateMsg(
    rev: 1,
    epoch: 1,
    songs: [],
    offset: 0,
    index: 0,
    playing: true,
    positionMs: 0,
    durationMs: null,
    shuffle: false,
    repeat: RepeatMode.off,
  ),
  RoomBeatMsg(
    rev: 1,
    index: 0,
    playing: true,
    positionMs: 0,
    durationMs: null,
    shuffle: false,
    repeat: RepeatMode.off,
  ),
  RoomRolesMsg(roles: {}),
  RoomRequestMsg(from: 'd', id: 'r', op: RoomOp.next),
  RoomHelloMsg(from: 'd'),
  RoomKickMsg(deviceId: 'd'),
  RoomEndMsg(),
];

void main() {
  test('the Supabase channel listens for every message kind', () {
    final kinds = {for (final m in samples) sampleOf(m).runtimeType};
    expect(kinds, hasLength(7), reason: 'one sample per kind');
    for (final m in samples) {
      expect(
        SupabaseRoomChannel.events,
        contains(m.event),
        reason: '${m.runtimeType} is sent as "${m.event}"',
      );
      expect(RoomMessage.decode(m.event, m.toJson()), isNotNull);
    }
  });
}
