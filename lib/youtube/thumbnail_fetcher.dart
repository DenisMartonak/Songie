import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/log.dart';
import '../library/art_cache.dart';

/// Downloads a thumbnail and stores it, square-cropped, in the [ArtCache].
class ThumbnailFetcher {
  ThumbnailFetcher(
    this._art,
    this._download, {
    this.timeout = const Duration(seconds: 15),
  });

  final ArtCache _art;
  final Future<List<int>> Function(Uri) _download;

  /// Overall limit per image; a slow one must not hold up the whole pass.
  final Duration timeout;

  /// Tries each url in turn and returns the art-cache ref of the first usable
  /// image, or null when none is. A failed download (404, timeout), an
  /// undecodable body and YouTube's 120x90 "no thumbnail" placeholder all
  /// count as a miss. Never throws.
  Future<String?> fetchBest(List<String> urls) async {
    for (final url in urls) {
      if (url.isEmpty) continue;
      try {
        final bytes = Uint8List.fromList(
          await _download(Uri.parse(url)).timeout(timeout),
        );
        if (_isPlaceholder(bytes)) continue;
        final ref = await _art.put(bytes, squareCrop: true);
        if (ref != null) return ref;
      } catch (e, s) {
        AppLog.w('Thumbnail fetch failed', e, s);
      }
    }
    return null;
  }

  /// Reads only the image header, so a large cover is not decoded twice.
  bool _isPlaceholder(Uint8List bytes) {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    return info != null && info.width == 120 && info.height == 90;
  }
}
