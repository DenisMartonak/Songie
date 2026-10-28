import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The `Authorization` value for a signed-in Innertube request:
/// `SAPISIDHASH <ts>_<sha1("<ts> <sapisid> <origin>")>`, with `<ts>` in Unix
/// seconds (ytmusicapi; see docs/innertube-notes.md, Signed in). It is as
/// secret as the cookie it is made from: never log it.
String sapisidHash(String sapisid, String origin, DateTime now) {
  final ts = now.millisecondsSinceEpoch ~/ 1000;
  final digest = sha1.convert(utf8.encode('$ts $sapisid $origin'));
  return 'SAPISIDHASH ${ts}_$digest';
}
