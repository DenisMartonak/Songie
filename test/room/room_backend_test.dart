import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/room/room_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<(String, Map<String, Object?>)> calls;

  SupabaseRoomBackend backend(Future<Object?> Function(String) answer) {
    calls = [];
    return SupabaseRoomBackend.withRpc((fn, params) {
      calls.add((fn, params));
      return answer(fn);
    });
  }

  test('open returns the room id and code', () async {
    final b = backend(
      (_) async => [
        {'room_id': 'r1', 'code': 'ABCD2345'},
      ],
    );
    final room = await b.open();
    expect(room.roomId, 'r1');
    expect(room.code, 'ABCD2345');
    expect(calls.single.$1, 'open_room');
  });

  test('join sends the code and returns the room id', () async {
    final b = backend((_) async => 'r1');
    expect(await b.join('ABCD2345'), 'r1');
    expect(calls.single.$1, 'join_room');
    expect(calls.single.$2, {'p_code': 'ABCD2345'});
  });

  test('join ignores case, spaces and dashes in the code', () async {
    final b = backend((_) async => 'r1');
    await b.join('abcd 2345');
    await b.join('abcd-2345');
    expect(calls[0].$2, {'p_code': 'ABCD2345'});
    expect(calls[1].$2, {'p_code': 'ABCD2345'});
  });

  for (final (msg, kind) in [
    ('room_not_found', RoomJoinError.notFound),
    ('room_ended', RoomJoinError.ended),
    ('room_full', RoomJoinError.full),
  ]) {
    test('join maps $msg to ${kind.name}', () async {
      final b = backend((_) async => throw PostgrestException(message: msg));
      await expectLater(
        b.join('ABCD2345'),
        throwsA(isA<RoomJoinException>().having((e) => e.kind, 'kind', kind)),
      );
    });
  }

  test('join maps a SocketException to offline', () async {
    final b = backend((_) async => throw const SocketException('down'));
    await expectLater(
      b.join('ABCD2345'),
      throwsA(
        isA<RoomJoinException>().having(
          (e) => e.kind,
          'kind',
          RoomJoinError.offline,
        ),
      ),
    );
  });

  test('leave, remove and end call their functions', () async {
    final b = backend((_) async => null);
    await b.leave('r1');
    await b.remove('r1', 'u2');
    await b.end('r1');
    expect(calls.map((c) => c.$1), ['leave_room', 'remove_member', 'end_room']);
    expect(calls[0].$2, {'p_room': 'r1'});
    expect(calls[1].$2, {'p_room': 'r1', 'p_user': 'u2'});
    expect(calls[2].$2, {'p_room': 'r1'});
  });
}
