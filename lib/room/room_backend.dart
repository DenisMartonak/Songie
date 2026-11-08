import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why joining a room failed.
enum RoomJoinError { notFound, ended, full, offline, other }

class RoomJoinException implements Exception {
  const RoomJoinException(this.kind);
  final RoomJoinError kind;

  @override
  String toString() => 'RoomJoinException(${kind.name})';
}

/// A room the caller just opened as host.
class OpenedRoom {
  const OpenedRoom({required this.roomId, required this.code});
  final String roomId;

  /// The 8 characters, without the dash.
  final String code;
}

/// The room tables behind Supabase functions (open_room, join_room, ...).
abstract class RoomBackend {
  Future<OpenedRoom> open();

  /// The room id for [code]; throws [RoomJoinException] when it can't join.
  Future<String> join(String code);
  Future<void> leave(String roomId);

  /// Host only: takes [userId] out of the room.
  Future<void> remove(String roomId, String userId);

  /// Host only: ends the room for everyone.
  Future<void> end(String roomId);
}

typedef RoomRpc =
    Future<Object?> Function(String fn, Map<String, Object?> params);

class SupabaseRoomBackend implements RoomBackend {
  /// [client] is read only when a call is made, so a signed-out app never
  /// touches Supabase.
  SupabaseRoomBackend(SupabaseClient Function() client)
    : _rpc = ((fn, params) => client().rpc<dynamic>(fn, params: params));

  @visibleForTesting
  SupabaseRoomBackend.withRpc(this._rpc);

  final RoomRpc _rpc;

  @override
  Future<OpenedRoom> open() async {
    final res = await _rpc('open_room', {}) as List<dynamic>;
    final row = Map<String, dynamic>.from(res.first as Map);
    return OpenedRoom(
      roomId: row['room_id'] as String,
      code: row['code'] as String,
    );
  }

  @override
  Future<String> join(String code) async {
    try {
      return await _rpc('join_room', {'p_code': code}) as String;
    } on PostgrestException catch (e) {
      throw RoomJoinException(switch (e.message) {
        final m when m.contains('room_not_found') => RoomJoinError.notFound,
        final m when m.contains('room_ended') => RoomJoinError.ended,
        final m when m.contains('room_full') => RoomJoinError.full,
        _ => RoomJoinError.other,
      });
    } on SocketException {
      throw const RoomJoinException(RoomJoinError.offline);
    } on TimeoutException {
      throw const RoomJoinException(RoomJoinError.offline);
    } on http.ClientException {
      throw const RoomJoinException(RoomJoinError.offline);
    } on AuthRetryableFetchException {
      throw const RoomJoinException(RoomJoinError.offline);
    }
  }

  @override
  Future<void> leave(String roomId) async {
    await _rpc('leave_room', {'p_room': roomId});
  }

  @override
  Future<void> remove(String roomId, String userId) async {
    await _rpc('remove_member', {'p_room': roomId, 'p_user': userId});
  }

  @override
  Future<void> end(String roomId) async {
    await _rpc('end_room', {'p_room': roomId});
  }
}
