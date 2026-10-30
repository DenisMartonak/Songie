import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'device_identity.dart';
import 'sync_auth.dart';
import 'sync_server.dart';

enum SyncNetKind {
  unreachable,
  timeout,
  wrongCertificate,
  unknownDevice,
  auth,
  schema,
  busy,
  server,
}

/// A failed request to a peer. [status] is the HTTP status when the peer
/// answered (for example 403, 404 or 400).
class SyncNetError implements Exception {
  SyncNetError(this.kind, this.message, {this.status});

  final SyncNetKind kind;
  final String message;
  final int? status;

  @override
  String toString() =>
      'SyncNetError(${kind.name}${status == null ? '' : ', $status'}: $message)';
}

/// HTTPS client for one peer.
///
/// [SyncClient.pinned] accepts only the peer's pinned certificate and signs
/// every request with the pair key. [SyncClient.open] (pairing) accepts the
/// first certificate it sees, exposes it as [seenFingerprint], and from then
/// on accepts only that one; it signs nothing.
class SyncClient {
  SyncClient.pinned({
    required String host,
    required int port,
    required String fingerprint,
    required Uint8List pairKey,
    required String myDeviceId,
    Duration clockOffset = Duration.zero,
    Duration responseTimeout = defaultResponseTimeout,
  }) : this._(
         host,
         port,
         fingerprint,
         pairKey,
         myDeviceId,
         clockOffset,
         responseTimeout,
       );

  SyncClient.open({required String host, required int port})
    : this._(
        host,
        port,
        null,
        null,
        null,
        Duration.zero,
        defaultResponseTimeout,
      );

  SyncClient._(
    this._host,
    this._port,
    this._pinned,
    this._pairKey,
    this._myDeviceId,
    this._clockOffset,
    this.responseTimeout,
  ) {
    _http = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = connectTimeout
      ..badCertificateCallback = (cert, host, port) => _accept(cert);
  }

  static const connectTimeout = Duration(seconds: 5);

  /// How long a request may wait for a response, or a body for its next chunk.
  static const defaultResponseTimeout = Duration(seconds: 60);

  /// How long a request that applies a whole sync on the peer (one
  /// transaction, possibly a large first sync on a phone) may wait for its
  /// response; see [postJson].
  static const applyTimeout = Duration(minutes: 10);

  /// This client's [defaultResponseTimeout] (shorter in tests).
  final Duration responseTimeout;

  final String _host;
  final int _port;
  final String? _pinned;
  final Uint8List? _pairKey;
  final String? _myDeviceId;
  final Duration _clockOffset;
  late final HttpClient _http;
  bool _sawWrongCertificate = false;

  String? _seen;

  /// The fingerprint of the certificate the peer presented, once connected.
  String? get seenFingerprint => _seen;

  bool _accept(X509Certificate cert) {
    final fp = DeviceIdentity.fingerprintOf(cert);
    final expected = _pinned ?? _seen;
    if (expected != null && fp != expected) {
      _sawWrongCertificate = true;
      return false;
    }
    _seen = fp;
    return true;
  }

  /// Connects once and returns the peer's certificate fingerprint without
  /// sending a request. On an open client this fixes the certificate later
  /// requests must present.
  Future<String> fetchFingerprint() => _guard(() async {
    final socket = await SecureSocket.connect(
      _host,
      _port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: _accept,
      timeout: connectTimeout,
    ).timeout(responseTimeout);
    final cert = socket.peerCertificate;
    socket.destroy();
    if (cert == null || !_accept(cert)) {
      throw SyncNetError(SyncNetKind.wrongCertificate, 'no usable certificate');
    }
    return _seen!;
  });

  Future<Map<String, dynamic>> getJson(String pathAndQuery) => _guard(() async {
    final req = await _open('GET', pathAndQuery, bodyHashOf(const []));
    return _readJson(await req.close().timeout(responseTimeout));
  });

  /// Posts [body] with `schema_version` added (a value in [body] wins). The
  /// response may take up to [timeout] (default [responseTimeout]).
  Future<Map<String, dynamic>> postJson(
    String pathAndQuery,
    Map<String, Object?> body, {
    Duration? timeout,
  }) => _guard(() async {
    final bytes = utf8.encode(
      jsonEncode({'schema_version': syncSchemaVersion, ...body}),
    );
    final req = await _open('POST', pathAndQuery, bodyHashOf(bytes));
    req.headers.contentType = ContentType.json;
    req.contentLength = bytes.length;
    req.add(bytes);
    return _readJson(await req.close().timeout(timeout ?? responseTimeout));
  });

  /// The body of [path] from byte [from] on (a Range request when > 0).
  Stream<List<int>> getFile(String path, {int from = 0}) async* {
    final res = await _guard(() async {
      final req = await _open('GET', path, bodyHashOf(const []));
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final res = await req.close().timeout(responseTimeout);
      _checkCertificate(res);
      if (res.statusCode != HttpStatus.ok &&
          res.statusCode != HttpStatus.partialContent) {
        throw _errorFrom(res.statusCode, await _decode(res));
      }
      return res;
    });
    yield* _guardStream(res.timeout(responseTimeout));
  }

  /// Uploads [bytes] (the file from byte [from] on, [total] bytes in all) to
  /// [path], adding `from` and `total` to its query. Returns the JSON reply.
  Future<Map<String, dynamic>> putFile(
    String path,
    Stream<List<int>> bytes, {
    int from = 0,
    required int total,
  }) => _guard(() async {
    final uri = Uri.parse(path);
    final target = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'from': '$from',
        'total': '$total',
      },
    );
    final req = await _open('PUT', pathAndQueryOf(target), streamBodyHash);
    req.headers.contentType = ContentType.binary;
    req.contentLength = total - from;
    await req.addStream(bytes);
    return _readJson(await req.close().timeout(responseTimeout));
  });

  void close() => _http.close(force: true);

  Future<HttpClientRequest> _open(
    String method,
    String pathAndQuery,
    String bodyHash,
  ) async {
    final uri = Uri.parse('https://$_host:$_port$pathAndQuery');
    final req = await _http.openUrl(method, uri).timeout(responseTimeout);
    final key = _pairKey;
    if (key != null) {
      final timeMs = DateTime.now().add(_clockOffset).millisecondsSinceEpoch;
      req.headers
        ..set(headerDevice, _myDeviceId!)
        ..set(headerTime, '$timeMs')
        ..set(
          headerSig,
          signRequest(
            key,
            method: method,
            pathAndQuery: pathAndQueryOf(uri),
            timeMs: timeMs,
            bodyHash: bodyHash,
          ),
        );
    }
    return req;
  }

  /// Rejects a response whose certificate is not the expected one, in case
  /// the TLS stack accepted it without asking [_accept].
  void _checkCertificate(HttpClientResponse res) {
    final cert = res.certificate;
    if (cert == null || !_accept(cert)) {
      throw SyncNetError(SyncNetKind.wrongCertificate, 'certificate mismatch');
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpClientResponse res) async {
    _checkCertificate(res);
    final body = await _decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFrom(res.statusCode, body);
    }
    if (body == null) {
      throw SyncNetError(
        SyncNetKind.server,
        'not JSON',
        status: res.statusCode,
      );
    }
    if (body['schema_version'] != syncSchemaVersion) {
      throw SyncNetError(SyncNetKind.schema, 'peer schema differs');
    }
    return body;
  }

  /// The response body as a JSON object, or null when it is not one.
  Future<Map<String, dynamic>?> _decode(HttpClientResponse res) async {
    final bytes = await res
        .fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c))
        .timeout(responseTimeout);
    try {
      final v = jsonDecode(utf8.decode(bytes.takeBytes()));
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  static SyncNetError _errorFrom(int status, Map<String, dynamic>? body) {
    final code = body?['error'];
    final message = code is String ? code : 'HTTP $status';
    final kind = switch ((status, code)) {
      (HttpStatus.unauthorized, 'unknown_device') => SyncNetKind.unknownDevice,
      (HttpStatus.unauthorized || HttpStatus.forbidden, _) => SyncNetKind.auth,
      (HttpStatus.conflict, 'schema') => SyncNetKind.schema,
      (HttpStatus.conflict, 'busy') => SyncNetKind.busy,
      _ => SyncNetKind.server,
    };
    return SyncNetError(kind, message, status: status);
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw _translate(e);
    }
  }

  Stream<List<int>> _guardStream(Stream<List<int>> s) =>
      s.handleError((Object e) => throw _translate(e));

  SyncNetError _translate(Object e) {
    if (e is SyncNetError) return e;
    if (_sawWrongCertificate) {
      return SyncNetError(SyncNetKind.wrongCertificate, 'certificate mismatch');
    }
    return switch (e) {
      TimeoutException() => SyncNetError(SyncNetKind.timeout, 'timed out'),
      IOException() => SyncNetError(
        SyncNetKind.unreachable,
        e.runtimeType.toString(),
      ),
      _ => SyncNetError(SyncNetKind.server, e.runtimeType.toString()),
    };
  }
}
