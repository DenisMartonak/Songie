import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync_row.dart';

/// The server couldn't be reached (no network, a timeout).
class CloudOffline implements Exception {
  const CloudOffline([this.cause]);

  final Object? cause;

  @override
  String toString() => 'CloudOffline($cause)';
}

/// The signed-in account's synced rows on the server. Every call acts as the
/// signed-in user; a network failure throws [CloudOffline].
abstract class CloudRemote {
  /// Upserts at most 500 [rows]; the server keeps the newer clock per row.
  /// Returns how many rows it wrote.
  Future<int> push(List<SyncRow> rows);

  /// Up to [max] rows written after server seq [after], oldest first, each
  /// with its server seq.
  Future<List<(int serverSeq, SyncRow row)>> pull(int after, {int max = 500});

  /// Fires when [userId]'s rows may have changed (and when the live
  /// connection is (re)made, since a message may have been missed). Only a
  /// hint to pull.
  Stream<void> changes(String userId);

  /// Drops the live connection.
  Future<void> close();
}

/// The row as one element of `push_rows`. The local seq stays on the device.
Map<String, Object?> rowToServer(SyncRow r) => {
  'tbl': r.table.wire,
  'id': r.id,
  'clock': r.clock,
  'origin_device': r.originDevice,
  'deleted': r.deleted,
  'data': {...r.data}..remove('localSeq'),
};

/// A `sync_rows` row as a [SyncRow]; the stamp columns win over `data`.
(int, SyncRow) rowFromServer(Map<String, dynamic> m) {
  final data = Map<String, Object?>.from(m['data'] as Map)
    ..['id'] = m['id']
    ..['clock'] = m['clock']
    ..['originDevice'] = m['origin_device']
    ..['deleted'] = m['deleted']
    ..['localSeq'] = 0;
  return (
    (m['server_seq'] as num).toInt(),
    SyncRow(SyncTable.fromWire(m['tbl'] as String), data),
  );
}

/// [CloudRemote] on Supabase: the `push_rows` and `pull_rows` functions and
/// the private Broadcast topic `sync:<user id>`.
class SupabaseCloudRemote implements CloudRemote {
  /// [client] is read only when a call is made, so a signed-out app never
  /// touches Supabase.
  SupabaseCloudRemote(this._client);

  final SupabaseClient Function() _client;
  RealtimeChannel? _channel;

  @override
  Future<int> push(List<SyncRow> rows) => _net(() async {
    final n = await _client().rpc<dynamic>(
      'push_rows',
      params: {
        'rows': [for (final r in rows) rowToServer(r)],
      },
    );
    return (n as num).toInt();
  });

  @override
  Future<List<(int, SyncRow)>> pull(int after, {int max = 500}) => _net(
    () async {
      final res = await _client().rpc<List<dynamic>>(
        'pull_rows',
        params: {'after': after, 'max': max},
      );
      return [
        for (final m in res) rowFromServer(Map<String, dynamic>.from(m as Map)),
      ];
    },
  );

  @override
  Stream<void> changes(String userId) {
    late final StreamController<void> out;
    out = StreamController<void>(
      onListen: () {
        unawaited(_drop());
        _channel = _client()
            .channel(
              'sync:$userId',
              opts: const RealtimeChannelConfig(private: true),
            )
            .onBroadcast(event: 'changed', callback: (_) => out.add(null))
            .subscribe((status, _) {
              if (status == RealtimeSubscribeStatus.subscribed) out.add(null);
            });
      },
      onCancel: _drop,
    );
    return out.stream;
  }

  @override
  Future<void> close() => _drop();

  Future<void> _drop() async {
    final c = _channel;
    _channel = null;
    if (c == null) return;
    try {
      await _client().removeChannel(c);
    } catch (_) {
      // Already gone or offline: nothing to tidy.
    }
  }

  static Future<T> _net<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SocketException catch (e) {
      throw CloudOffline(e);
    } on TimeoutException catch (e) {
      throw CloudOffline(e);
    } on http.ClientException catch (e) {
      throw CloudOffline(e);
    } on AuthRetryableFetchException catch (e) {
      throw CloudOffline(e);
    }
  }
}
