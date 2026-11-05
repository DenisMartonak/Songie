import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A PNG whose header claims [width]×[height]; its pixel data is 1×1, so
/// only a header-first check can refuse it cheaply.
Uint8List hugePngHeader(int width, int height) {
  final b = Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));
  final d = ByteData.sublistView(b);
  d.setUint32(16, width);
  d.setUint32(20, height);
  // The IHDR checksum covers its type and data (bytes 12 to 28).
  d.setUint32(29, _crc32(b.sublist(12, 29)));
  return b;
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
