import 'dart:async';

import 'package:http/http.dart' as http;

/// How long an account request may wait for the server.
const kAccountHttpTimeout = Duration(seconds: 20);

/// The account server's HTTP client: a request fails with a
/// [TimeoutException] (shown as offline) when no answer starts within
/// [timeout], or when the answer's body stops arriving for that long. Used
/// only for Supabase, so the app's other HTTP clients are unaffected.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(this._inner, {this.timeout = kAccountHttpTimeout});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await _inner.send(request).timeout(timeout);
    return http.StreamedResponse(
      r.stream.timeout(timeout),
      r.statusCode,
      contentLength: r.contentLength,
      request: r.request,
      headers: r.headers,
      isRedirect: r.isRedirect,
      persistentConnection: r.persistentConnection,
      reasonPhrase: r.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
