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

/// Why `push_rows` refused a page (it takes all of a page or none).
enum CloudRejection {
  /// A row is malformed.
  invalidRow,

  /// A row's data is over 256 KB.
  tooBig,

  /// A clock is more than a day ahead of the server's.
  clockAhead,
}

/// `push_rows` refused the page because of one or more of its rows.
class CloudRejected implements Exception {
  const CloudRejected(this.reason);

  final CloudRejection reason;

  @override
  String toString() => 'CloudRejected(${reason.name})';
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

/// How long one push or pull may take before it counts as offline.
const kCloudCallTimeout = Duration(seconds: 45);

/// The row-specific `push_rows` refusal named by [message], if it is one.
CloudRejection? rejectionOf(String message) {
  if (message.contains('clock more than a day in the future')) {
    return CloudRejection.clockAhead;
  }
  if (message.contains('row data over 256 KB')) return CloudRejection.tooBig;
  if (message.startsWith('invalid row in push')) {
    return CloudRejection.invalidRow;
  }
  return null;
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
  SupabaseCloudRemote(this._client, {this._timeout = kCloudCallTimeout});

  final SupabaseClient Function() _client;
  final Duration _timeout;
  RealtimeChannel? _channel;

  @override
  Future<int> push(List<SyncRow> rows) => _net(() async {
    try {
      final n = await _client().rpc<dynamic>(
        'push_rows',
        params: {
          'rows': [for (final r in rows) rowToServer(r)],
        },
      );
      return (n as num).toInt();
    } on PostgrestException catch (e) {
      // `raise exception` in push_rows arrives as P0001 with its message.
      final reason = e.code == 'P0001' ? rejectionOf(e.message) : null;
      if (reason == null) rethrow;
      throw CloudRejected(reason);
    }
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

  Future<T> _net<T>(Future<T> Function() f) async {
    try {
      // The client's own HTTP timeout covers each request; this caps the
      // whole call.
      return await f().timeout(_timeout);
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
