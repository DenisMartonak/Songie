import 'dart:convert';
import 'dart:io';

/// One Innertube HTTP response.
class InnertubeResponse {
  const InnertubeResponse(this.status, this.json, {this.redirect});

  final int status;

  /// The decoded body, or null when it was not a JSON object.
  final Map<String, Object?>? json;

  /// The `Location` of a 3xx response (redirects are not followed, so a
  /// consent.youtube.com redirect can be seen).
  final Uri? redirect;
}

/// Posts one JSON request. Tests use a fake that replays recorded fixtures.
abstract class InnertubeTransport {
  Future<InnertubeResponse> post(
    Uri url,
    Map<String, Object?> body,
    Map<String, String> headers,
  );
}

/// The real transport: `dart:io` [HttpClient], gzip, 10 s timeouts.
class HttpInnertubeTransport implements InnertubeTransport {
  HttpInnertubeTransport({HttpClient? client})
    : _client = (client ?? HttpClient())
        ..connectionTimeout = timeout
        ..autoUncompress = true;

  static const timeout = Duration(seconds: 10);

  final HttpClient _client;

  /// Throws [SocketException], [HttpException], [TlsException] or
  /// `TimeoutException` on transport errors; [InnertubeClient] turns them
  /// into `Err`.
  @override
  Future<InnertubeResponse> post(
    Uri url,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) async {
    final req = await _client.postUrl(url).timeout(timeout);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    req.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptEncodingHeader, 'gzip');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    final location = res.headers.value(HttpHeaders.locationHeader);
    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) json = decoded.cast<String, Object?>();
    } on FormatException {
      json = null;
    }
    return InnertubeResponse(
      res.statusCode,
      json,
      redirect: location == null ? null : url.resolve(location),
    );
  }
}
