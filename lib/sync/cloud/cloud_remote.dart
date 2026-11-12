import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/hlc.dart';
import '../sync_row.dart';

/// The shape of the synced rows this app writes, sent with every row as
/// `fmt`. Bump it when a synced table's columns change: the server then
/// keeps a newer-format row from being overwritten by an older app, and an
/// older app leaves such rows for after its update (see [PulledRow]). The
/// drift schema version it came with.
const kRowFormat = 11;

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

  /// The database can't store a value of a row (a Postgres data exception,
  /// SQLSTATE class 22, such as a NUL in text).
  badData,
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
  /// with its server seq and format.
  Future<List<PulledRow>> pull(int after, {int max = 500});

  /// Fires when [userId]'s rows may have changed, with the new highest
  /// server seq the message carries, and with null when the live connection
  /// is (re)made (a message may have been missed). Only a hint to pull.
  Stream<int?> changes(String userId);

  /// Drops the live connection.
  Future<void> close();

  /// The names of the files and sub-folders directly in [folder] (e.g.
  /// `<user id>/<kind>`) of the `sync-files` bucket.
  Future<CloudListing> listFiles(String folder);

  /// Stores [bytes] at [path] (`<user id>/<kind>/<name>`), replacing a file
  /// there. [contentType] must be one the bucket allows.
  Future<void> uploadFile(
    String path,
    Uint8List bytes, {
    required String contentType,
  });

  /// The file at [path].
  Future<Uint8List> downloadFile(String path);

  /// Deletes the files at [paths].
  Future<void> removeFiles(List<String> paths);
}

/// What one folder of the bucket holds: file names and sub-folder names.
class CloudListing {
  const CloudListing(this.files, [this.folders = const {}]);

  final Set<String> files;
  final Set<String> folders;
}

/// The bucket for synced files.
const kSyncFilesBucket = 'sync-files';

/// How long one file upload or download may take before it counts as
/// offline (files are up to 10 MB).
const kCloudFileTimeout = Duration(minutes: 5);

/// Storage reports a failed request (no network) with the exception's type
/// name as the status; a paused project answers with a gateway error.
bool _storageUnreachable(StorageException e) {
  final status = e.statusCode;
  return status == null ||
      int.tryParse(status) == null ||
      const {'502', '503', '504', '540'}.contains(status);
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

/// One pulled row: its server seq and format, and the row itself, or null
/// when this app can't read it (a newer format, or data it can't decode).
/// Such a row is left for after an app update; the rest of its page applies.
class PulledRow {
  const PulledRow(this.serverSeq, this.fmt, this.row);

  final int serverSeq;
  final int fmt;
  final SyncRow? row;
}

/// Postgres text and jsonb can't hold NUL, so strings in a row's data go up
/// with NUL as this private use character followed by '0', and the
/// character itself followed by 'E'.
const _esc = '\uE000';

final _toEscape = RegExp('[\u0000$_esc]');
final _escaped = RegExp('$_esc([0E])');

Object? _escapeNul(Object? v) => switch (v) {
  String s => s.replaceAllMapped(
    _toEscape,
    (m) => m[0] == '\u0000' ? '${_esc}0' : '${_esc}E',
  ),
  Map<dynamic, dynamic> m => {
    for (final e in m.entries) e.key: _escapeNul(e.value),
  },
  List<dynamic> l => [for (final e in l) _escapeNul(e)],
  _ => v,
};

Object? _unescapeNul(Object? v) => switch (v) {
  String s => s.replaceAllMapped(
    _escaped,
    (m) => m[1] == '0' ? '\u0000' : _esc,
  ),
  Map<dynamic, dynamic> m => {
    for (final e in m.entries) e.key: _unescapeNul(e.value),
  },
  List<dynamic> l => [for (final e in l) _unescapeNul(e)],
  _ => v,
};

/// The row as one element of `push_rows`, with its format and NUL escaped
/// in its data. The local seq stays on the device.
Map<String, Object?> rowToServer(SyncRow r) => {
  'tbl': r.table.wire,
  'id': r.id,
  'clock': r.clock,
  'origin_device': r.originDevice,
  'deleted': r.deleted,
  'fmt': kRowFormat,
  'data': _escapeNul({...r.data}..remove('localSeq')),
};

/// A `sync_rows` row as a [PulledRow]; the stamp columns win over `data`.
/// A row without `fmt` counts as [kRowFormat]. A format older than
/// [kRowFormat] is where a later app upgrades old rows.
PulledRow rowFromServer(Map<String, dynamic> m) {
  final seq = (m['server_seq'] as num).toInt();
  final fmt = (m['fmt'] as num?)?.toInt() ?? kRowFormat;
  if (fmt > kRowFormat) return PulledRow(seq, fmt, null);
  try {
    final data = Map<String, Object?>.from(_unescapeNul(m['data']) as Map)
      ..['id'] = m['id'] as String
      ..['clock'] = m['clock'] as String
      ..['originDevice'] = m['origin_device'] as String
      ..['deleted'] = m['deleted'] as bool
      ..['localSeq'] = 0;
    final row = SyncRow(SyncTable.fromWire(m['tbl'] as String), data);
    // Decodes now, so it can't fail later inside the page's transaction.
    Hlc.parse(row.clock);
    row.toInsertable(0);
    return PulledRow(seq, fmt, row);
  } catch (_) {
    return PulledRow(seq, fmt, null);
  }
}

/// The server seq in a `changed` Broadcast message (sync_rows_notify), at
/// the top or under `payload`; null when it has none.
int? broadcastSeq(Map<String, dynamic> message) {
  final inner = message['payload'];
  final seq =
      message['server_seq'] ?? (inner is Map ? inner['server_seq'] : null);
  return seq is num ? seq.toInt() : null;
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
      // `raise exception` in push_rows arrives as P0001 with its message; a
      // value Postgres can't store as a data exception (class 22).
      final reason = e.code == 'P0001'
          ? rejectionOf(e.message)
          : (e.code?.startsWith('22') ?? false)
          ? CloudRejection.badData
          : null;
      if (reason == null) rethrow;
      throw CloudRejected(reason);
    }
  });

  @override
  Future<List<PulledRow>> pull(int after, {int max = 500}) => _net(() async {
    final res = await _client().rpc<List<dynamic>>(
      'pull_rows',
      params: {'after': after, 'max': max},
    );
    return [
      for (final m in res) rowFromServer(Map<String, dynamic>.from(m as Map)),
    ];
  });

  @override
  Stream<int?> changes(String userId) {
    late final StreamController<int?> out;
    out = StreamController<int?>(
      onListen: () {
        unawaited(_drop());
        _channel = _client()
            .channel(
              'sync:$userId',
              opts: const RealtimeChannelConfig(private: true),
            )
            .onBroadcast(
              event: 'changed',
              callback: (m) => out.add(broadcastSeq(m)),
            )
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

  StorageFileApi get _bucket => _client().storage.from(kSyncFilesBucket);

  @override
  Future<CloudListing> listFiles(String folder) => _net(() async {
    const page = 1000;
    final files = <String>{};
    final folders = <String>{};
    for (var offset = 0; ; offset += page) {
      final got = await _bucket.list(
        path: folder,
        searchOptions: SearchOptions(limit: page, offset: offset),
      );
      for (final f in got) {
        // Sub-folders come back as entries without an id.
        (f.id == null ? folders : files).add(f.name);
      }
      if (got.length < page) return CloudListing(files, folders);
    }
  });

  @override
  Future<void> uploadFile(
    String path,
    Uint8List bytes, {
    required String contentType,
  }) => _net(
    () => _bucket.uploadBinary(
      path,
      bytes,
      // Named by content hash, so replacing is harmless.
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    ),
    timeout: kCloudFileTimeout,
  );

  @override
  Future<Uint8List> downloadFile(String path) =>
      _net(() => _bucket.download(path), timeout: kCloudFileTimeout);

  @override
  Future<void> removeFiles(List<String> paths) =>
      _net(() => _bucket.remove(paths));

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

  Future<T> _net<T>(Future<T> Function() f, {Duration? timeout}) async {
    try {
      // The client's own HTTP timeout covers each request; this caps the
      // whole call.
      return await f().timeout(timeout ?? _timeout);
    } on SocketException catch (e) {
      throw CloudOffline(e);
    } on TimeoutException catch (e) {
      throw CloudOffline(e);
    } on http.ClientException catch (e) {
      throw CloudOffline(e);
    } on AuthRetryableFetchException catch (e) {
      throw CloudOffline(e);
    } on StorageException catch (e) {
      if (_storageUnreachable(e)) throw CloudOffline(e);
      rethrow;
    }
  }
}
