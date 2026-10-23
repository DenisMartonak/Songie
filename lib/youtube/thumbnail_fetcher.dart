import 'dart:async';
import 'dart:typed_data';

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

  /// The art-cache ref, or null for a missing url or any failure. Never throws.
  Future<String?> fetch(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final bytes = await _download(uri).timeout(timeout);
      return await _art.put(Uint8List.fromList(bytes), squareCrop: true);
    } catch (e, s) {
      AppLog.w('Thumbnail fetch failed', e, s);
      return null;
    }
  }
}
