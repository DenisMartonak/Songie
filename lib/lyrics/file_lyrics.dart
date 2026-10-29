import 'dart:convert';
import 'dart:io';

import '../library/tag_reader.dart';
import 'lrc.dart';
import 'lyrics.dart';
import 'lyrics_sources.dart';

/// Lyrics that sit beside the audio file (`.lrc`) or inside its tags.
class FileLyricsSource {
  FileLyricsSource(this._tags);

  final TagReader _tags;

  Future<SourceAnswer> read(String? audioPath) async {
    if (audioPath == null) return const Nothing();
    try {
      final sidecar = await _sidecar(audioPath);
      if (sidecar != null) return _answer(sidecar);
      final tags = await _tags.read(File(audioPath));
      final text = tags.lyrics;
      if (text != null && text.trim().isNotEmpty) return _answer(text);
    } catch (_) {
      // A file without readable tags is not a failure.
    }
    return const Nothing();
  }

  Future<String?> _sidecar(String audioPath) async {
    final dot = audioPath.lastIndexOf('.');
    final sep = audioPath.lastIndexOf(Platform.pathSeparator);
    final base = dot > sep ? audioPath.substring(0, dot) : audioPath;
    for (final ext in const ['.lrc', '.LRC']) {
      final f = File('$base$ext');
      if (await f.exists()) {
        final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
        if (text.trim().isNotEmpty) return text;
      }
    }
    return null;
  }

  SourceAnswer _answer(String text) {
    final lines = parseLrc(text);
    if (lines != null) {
      return Found(
        TrackLyrics(
          kind: LyricsKind.synced,
          source: LyricsSource.file,
          lines: lines,
        ),
      );
    }
    return Found(
      TrackLyrics(
        kind: LyricsKind.plain,
        source: LyricsSource.file,
        text: text,
      ),
    );
  }
}
