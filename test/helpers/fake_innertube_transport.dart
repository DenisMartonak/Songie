import 'dart:convert';
import 'dart:io';

import 'package:songies/innertube/transport.dart';

/// A recorded fixture: `{"status": <int>, "json": <response>}`.
InnertubeResponse fixture(String name) {
  final doc = jsonDecode(
    File('test/fixtures/innertube/$name.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return InnertubeResponse(
    doc['status']! as int,
    (doc['json'] as Map?)?.cast<String, Object?>(),
  );
}

class FakeRequest {
  FakeRequest(this.url, this.body, this.headers);
  final Uri url;
  final Map<String, Object?> body;
  final Map<String, String> headers;

  Map<String, Object?> get contextClient =>
      ((body['context']! as Map)['client']! as Map).cast<String, Object?>();
}

/// Records requests and replays queued responses (or throws queued errors).
class FakeTransport implements InnertubeTransport {
  final requests = <FakeRequest>[];
  final _replies = <Object>[];

  void reply(Object responseOrError) => _replies.add(responseOrError);

  @override
  Future<InnertubeResponse> post(
    Uri url,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) async {
    requests.add(FakeRequest(url, body, headers));
    final next = _replies.removeAt(0);
    if (next is InnertubeResponse) return next;
    throw next;
  }
}
