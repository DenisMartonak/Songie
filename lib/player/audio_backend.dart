/// Where a backend should load audio from.
sealed class AudioSourceRef {
  const AudioSourceRef();
}

/// A file on this device.
final class FileSource extends AudioSourceRef {
  const FileSource(this.path);
  final String path;

  @override
  bool operator ==(Object other) => other is FileSource && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileSource($path)';
}

/// A remote stream (used by Plan 2).
final class UrlSource extends AudioSourceRef {
  const UrlSource(this.url);
  final Uri url;

  @override
  bool operator ==(Object other) => other is UrlSource && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'UrlSource($url)';
}

/// A snapshot of what the audio engine is doing.
class BackendState {
  const BackendState({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration,
  });

  final bool playing;
  final bool buffering;

  /// True once the loaded source has played to its end.
  final bool completed;
  final Duration position;
  final Duration? duration;
}

/// Thin wrapper over the platform audio engine; holds no queue logic.
abstract class AudioBackend {
  Future<void> setSource(AudioSourceRef s);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> stop();
  Stream<BackendState> get states;
  Future<void> dispose();
}
