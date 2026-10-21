import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// The embedded tags the library cares about. Every field may be absent.
class TrackTags {
  const TrackTags({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.picture,
  });

  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;

  /// Raw bytes of the cover image (any format the art cache can decode).
  final Uint8List? picture;
}

abstract class TagReader {
  /// Reads the tags of [f]. Throws if the file is unreadable or has no
  /// recognisable tags.
  Future<TrackTags> read(File f);
}

/// Reads tags with `audio_metadata_reader`, off the UI isolate.
class AudioMetadataTagReader implements TagReader {
  @override
  Future<TrackTags> read(File f) {
    final path = f.path;
    return Isolate.run(() => _read(path));
  }
}

TrackTags _read(String path) {
  final m = readMetadata(File(path), getImage: true);
  final pictures = m.pictures;
  final cover =
      pictures
          .where((p) => p.pictureType == PictureType.coverFront)
          .firstOrNull ??
      pictures.firstOrNull;
  return TrackTags(
    title: m.title,
    artist: m.artist,
    album: m.album,
    duration: m.duration,
    picture: cover?.bytes,
  );
}
