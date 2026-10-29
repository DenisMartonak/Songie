import '../core/result.dart';
import '../innertube/ytm_service.dart';
import 'lyrics_sources.dart';

/// Source 4: YouTube Music's plain lyrics, signed out.
class YtmLyricsSource {
  YtmLyricsSource(this._ytm);

  final YtmService _ytm;

  Future<SourceAnswer> fetch(String? videoId) async {
    if (videoId == null) return const Nothing();
    return switch (await _ytm.lyrics(videoId)) {
      Ok(:final value?) => Found(value),
      Ok() => const Nothing(),
      Err(:final failure) => Failed(failure),
    };
  }
}
