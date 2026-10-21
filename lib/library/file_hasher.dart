import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Lower-case hex SHA-256 of the file content. The file is streamed (never
/// fully in memory) on a background isolate. A [FileSystemException] from
/// opening or reading the file propagates to the caller.
Future<String> sha256File(File f) {
  final path = f.path;
  return Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  });
}
