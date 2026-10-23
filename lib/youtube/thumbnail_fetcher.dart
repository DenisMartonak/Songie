import 'dart:typed_data';

import '../core/log.dart';
import '../library/art_cache.dart';

/// Downloads a thumbnail and stores it, square-cropped, in the [ArtCache].
class ThumbnailFetcher {
  ThumbnailFetcher(this._art, this._download);

  final ArtCache _art;
  final Future<List<int>> Function(Uri) _download;

  /// The art-cache ref, or null for a missing url or any failure. Never throws.
  Future<String?> fetch(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final bytes = await _download(uri);
      return await _art.put(Uint8List.fromList(bytes), squareCrop: true);
    } catch (e, s) {
      AppLog.w('Thumbnail fetch failed', e, s);
      return null;
    }
  }
}
