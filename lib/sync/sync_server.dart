import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/log.dart';
import 'device_identity.dart';
import 'sync_auth.dart';

/// The schema version every sync JSON body carries (`AppDatabase.schemaVersion`).
const syncSchemaVersion = 8;

/// Handles one routed request. [peerId] is the verified device id, or null on
/// an open route. A handler always closes the response.
typedef Handler = Future<void> Function(HttpRequest req, String? peerId);

/// Sends [body] (plus `schema_version`) as JSON and closes the response.
Future<void> sendJson(
  HttpRequest req,
  Map<String, Object?> body, {
  int status = HttpStatus.ok,
}) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({'schema_version': syncSchemaVersion, ...body}));
  await req.response.close();
}

/// The HTTPS server peers talk to while Sync devices is open.
///
/// Every request on a route that is not `open` must be signed (see
/// [RequestVerifier]). A request with an `application/octet-stream` body is
/// signed over [streamBodyHash] and its handler reads the stream; any other
/// body is read whole (at most [maxJsonBytes]), and when non-empty it must be
/// a JSON object carrying this [syncSchemaVersion]. Handlers read it with
/// [jsonBody].
class SyncServer {
  SyncServer(this._identity, this._verifier);

  static const maxJsonBytes = 32 * 1024 * 1024;

  final DeviceIdentity _identity;
  final RequestVerifier _verifier;
  final _routes = <String, _Route>{};
  HttpServer? _server;

  static final _bodies = Expando<Map<String, dynamic>>('jsonBody');

  /// The parsed JSON body of [req]. Throws [StateError] (answered as a 400)
  /// when the request had none.
  static Map<String, dynamic> jsonBody(HttpRequest req) =>
      _bodies[req] ?? (throw StateError('request has no JSON body'));

  /// Adds a route. A [path] ending in `/` (such as `/files/`) matches every
  /// path under it.
  void route(String method, String path, Handler h, {bool open = false}) {
    _routes['$method $path'] = _Route(h, open);
  }

  /// Starts serving on [preferredPort], or on any free port when it is taken.
  /// Returns the port. [address] is for tests (loopback).
  Future<int> start({
    int preferredPort = 47823,
    InternetAddress? address,
  }) async {
    final host = address ?? InternetAddress.anyIPv4;
    final context = _identity.serverContext();
    HttpServer server;
    try {
      server = await HttpServer.bindSecure(host, preferredPort, context);
    } on SocketException {
      server = await HttpServer.bindSecure(host, 0, context);
    }
    _server = server;
    server.listen(
      _handle,
      onError: (Object e) => AppLog.w('Sync server error', e),
    );
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  _Route? _find(String method, String path) {
    final exact = _routes['$method $path'];
    if (exact != null) return exact;
    _Route? best;
    var bestLength = 0;
    _routes.forEach((key, route) {
      final prefix = key.substring(method.length + 1);
      if (key.startsWith('$method ') &&
          prefix.endsWith('/') &&
          path.startsWith(prefix) &&
          prefix.length > bestLength) {
        best = route;
        bestLength = prefix.length;
      }
    });
    return best;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final route = _find(req.method, req.uri.path);
      if (route == null) {
        return await _error(req, HttpStatus.notFound, 'not_found');
      }
      final streamed =
          req.headers.contentType?.mimeType == ContentType.binary.mimeType;
      List<int> bytes = const [];
      if (!streamed) {
        final read = await _readCapped(req);
        if (read == null) {
          return await _error(
            req,
            HttpStatus.requestEntityTooLarge,
            'too_large',
          );
        }
        bytes = read;
      }

      String? peerId;
      if (!route.open) {
        final hash = streamed ? streamBodyHash : bodyHashOf(bytes);
        switch (await _verifier.verify(req, hash)) {
          case VerifyResult.ok:
            peerId = req.headers.value(headerDevice);
          case VerifyResult.unknownDevice:
            return await _error(req, HttpStatus.unauthorized, 'unknown_device');
          case VerifyResult.stale ||
              VerifyResult.badSignature ||
              VerifyResult.replay:
            return await _error(req, HttpStatus.unauthorized, 'auth');
        }
      }

      if (bytes.isNotEmpty) {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          return await _error(req, HttpStatus.badRequest, 'bad_request');
        }
        if (decoded['schema_version'] != syncSchemaVersion) {
          return await _error(req, HttpStatus.conflict, 'schema');
        }
        _bodies[req] = decoded;
      }
      await route.handler(req, peerId);
    } on FormatException {
      await _error(req, HttpStatus.badRequest, 'bad_request');
    } on TypeError {
      await _error(req, HttpStatus.badRequest, 'bad_request');
    } on StateError {
      await _error(req, HttpStatus.badRequest, 'bad_request');
    } catch (e) {
      AppLog.w('Sync request ${req.method} ${req.uri.path} failed', e);
      await _error(req, HttpStatus.internalServerError, 'server');
    }
  }

  /// The whole body, or null when it exceeds [maxJsonBytes].
  static Future<List<int>?> _readCapped(HttpRequest req) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in req) {
      if (out.length + chunk.length > maxJsonBytes) return null;
      out.add(chunk);
    }
    return out.takeBytes();
  }

  /// Answers with `{"error": code}`. When the handler already sent headers,
  /// the connection is just closed.
  static Future<void> _error(HttpRequest req, int status, String code) async {
    try {
      await sendJson(req, {'error': code}, status: status);
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}

class _Route {
  _Route(this.handler, this.open);

  final Handler handler;
  final bool open;
}
