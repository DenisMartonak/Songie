import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:songies/core/hlc.dart';
import 'package:songies/sync/cloud/cloud_remote.dart';
import 'package:songies/sync/sync_row.dart';

/// The server side of cloud sync in memory: rows per user, a server seq
/// that grows on every write, and the newer-clock rule of `push_rows`.
class FakeServer {
  final _rows = <String, Map<String, (int, Map<String, dynamic>)>>{};
  var _seq = 0;
  final _topics = <String, StreamController<void>>{};

  /// Whether a push that wrote rows tells the user's devices (Realtime).
  bool notify = false;

  /// The server's clock; a pushed clock more than a day past it is refused.
  int Function()? nowMs;

  /// Row ids the server refuses as invalid.
  final rejectIds = <String>{};

  int write(String user, List<SyncRow> rows) {
    // All or nothing, checked in push_rows' order.
    if (rows.any((r) => rejectIds.contains(r.id))) {
      throw const CloudRejected(CloudRejection.invalidRow);
    }
    final now = nowMs?.call();
    if (now != null &&
        rows.any((r) => Hlc.parse(r.clock).wallMs > now + 86400000)) {
      throw const CloudRejected(CloudRejection.clockAhead);
    }
    final mine = _rows.putIfAbsent(user, () => {});
    var written = 0;
    for (final r in rows) {
      // Through JSON, as jsonb would.
      final wire =
          jsonDecode(jsonEncode(rowToServer(r))) as Map<String, dynamic>;
      final key = '${r.table.wire}/${r.id}';
      final old = mine[key];
      if (old != null &&
          Hlc.parse(wire['clock'] as String)
                  .compareTo(Hlc.parse(old.$2['clock'] as String)) <=
              0) {
        continue;
      }
      mine[key] = (++_seq, {...wire, 'server_seq': _seq});
      written++;
    }
    if (written > 0 && notify) broadcast(user);
    return written;
  }

  List<(int, SyncRow)> read(String user, int after, int max) {
    final rows =
        (_rows[user]?.values ?? const <(int, Map<String, dynamic>)>[])
            .where((e) => e.$1 > after)
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (final e in rows.take(max))
        rowFromServer(jsonDecode(jsonEncode(e.$2)) as Map<String, dynamic>),
    ];
  }

  /// The user's rows as `'<wire>/<id>'` to their data.
  Map<String, Map<String, dynamic>> rowsOf(String user) => {
    for (final e in (_rows[user] ?? const {}).entries)
      e.key: e.value.$2['data'] as Map<String, dynamic>,
  };

  Stream<void> topic(String user) =>
      _topics.putIfAbsent(user, StreamController<void>.broadcast).stream;

  /// A Realtime message to [user]'s devices.
  void broadcast(String user) =>
      _topics.putIfAbsent(user, StreamController<void>.broadcast).add(null);

  /// The `sync-files` bucket: path to bytes and content type.
  final files = <String, (Uint8List, String)>{};

  /// The bucket's allowed content types (the migration's list).
  static const allowedTypes = {
    'font/ttf',
    'font/otf',
    'application/vnd.ms-opentype',
    'application/x-font-ttf',
    'application/x-font-otf',
    'application/font-sfnt',
    'image/jpeg',
    'image/png',
    'image/webp',
  };
}

/// One device's [CloudRemote] on a [FakeServer], counting every call.
class FakeRemote implements CloudRemote {
  FakeRemote(this.server);

  final FakeServer server;

  /// Who is signed in (the server's `auth.uid()`).
  String? user;

  var pushCalls = 0;
  var pullCalls = 0;
  var changesCalls = 0;
  var closeCalls = 0;

  /// Every push attempted, failed ones too.
  final pushes = <List<SyncRow>>[];

  /// Pushes still to fail (as offline).
  var failPushes = 0;

  /// Every call fails as offline.
  var offline = false;

  /// Runs inside each push, before it writes.
  Future<void> Function()? duringPush;

  /// Runs inside each close, before the connection drops.
  Future<void> Function()? duringClose;

  /// Thrown by every push (a server error that isn't about the rows).
  Object? pushError;

  int get calls => pushCalls + pullCalls + changesCalls + closeCalls;

  /// Storage calls: every upload's path, downloads, listings, removals.
  final uploads = <String>[];
  final downloads = <String>[];
  var listCalls = 0;
  var removeCalls = 0;

  /// Storage calls fail as offline.
  var filesOffline = false;

  /// Runs inside each download, before the bytes come back.
  Future<void> Function()? duringDownload;

  /// Uploads fail as a server error (not the connection).
  var failUploads = false;

  /// Storage policies: only the signed-in user's folder.
  void _own(String path) {
    if (user == null || !path.startsWith('$user/')) {
      throw StateError('not your folder: $path');
    }
  }

  @override
  Future<CloudListing> listFiles(String folder) async {
    listCalls++;
    if (filesOffline) throw const CloudOffline();
    _own('$folder/');
    final files = <String>{};
    final folders = <String>{};
    for (final k in server.files.keys) {
      if (!k.startsWith('$folder/')) continue;
      final rest = k.substring(folder.length + 1);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        files.add(rest);
      } else {
        folders.add(rest.substring(0, slash));
      }
    }
    return CloudListing(files, folders);
  }

  @override
  Future<void> uploadFile(
    String path,
    Uint8List bytes, {
    required String contentType,
  }) async {
    uploads.add(path);
    if (filesOffline) throw const CloudOffline();
    if (failUploads) throw StateError('server error');
    _own(path);
    if (!FakeServer.allowedTypes.contains(contentType)) {
      throw StateError('mime type $contentType is not supported');
    }
    if (bytes.length > 10 * 1024 * 1024) throw StateError('too big');
    server.files[path] = (Uint8List.fromList(bytes), contentType);
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    downloads.add(path);
    await duringDownload?.call();
    if (filesOffline) throw const CloudOffline();
    _own(path);
    final f = server.files[path];
    if (f == null) throw StateError('not found');
    return Uint8List.fromList(f.$1);
  }

  @override
  Future<void> removeFiles(List<String> paths) async {
    removeCalls++;
    if (filesOffline) throw const CloudOffline();
    for (final p in paths) {
      _own(p);
      server.files.remove(p);
    }
  }

  @override
  Future<int> push(List<SyncRow> rows) async {
    pushCalls++;
    pushes.add(rows);
    if (rows.length > 500) throw StateError('more than 500 rows');
    await duringPush?.call();
    if (offline) throw const CloudOffline();
    if (failPushes > 0) {
      failPushes--;
      throw const CloudOffline();
    }
    final e = pushError;
    if (e != null) throw e;
    return server.write(user!, rows);
  }

  @override
  Future<List<(int, SyncRow)>> pull(int after, {int max = 500}) async {
    pullCalls++;
    await Future<void>.delayed(Duration.zero);
    if (offline) throw const CloudOffline();
    return server.read(user!, after, max);
  }

  /// Whether the last of changes() and close() was changes().
  var live = false;

  @override
  Stream<void> changes(String userId) {
    changesCalls++;
    live = true;
    return server.topic(userId);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await duringClose?.call();
    live = false;
  }
}
