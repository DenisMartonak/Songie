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

/// A remote stream, with the HTTP headers the server expects.
final class UrlSource extends AudioSourceRef {
  const UrlSource(this.url, {this.headers = const {}});
  final Uri url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is UrlSource &&
      other.url == url &&
      other.headers.length == headers.length &&
      headers.entries.every((e) => other.headers[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(headers.entries.map((e) => (e.key, e.value))),
  );

  @override
  String toString() => 'UrlSource($url, ${headers.length} headers)';
}

/// A snapshot of what the audio engine is doing.
class BackendState {
  const BackendState({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.duration,
  });

  final bool playing;
  final bool buffering;

  /// True once the loaded source has played to its end.
  final bool completed;
  final Duration position;

  /// How far the loaded source has been buffered.
  final Duration buffered;
  final Duration? duration;
}

/// Thin wrapper over the platform audio engine; holds no queue logic.
abstract class AudioBackend {
  Future<void> setSource(AudioSourceRef s);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> stop();

  /// Output gain, 0.0 (silent) to 1.0 (full).
  Future<void> setVolume(double volume);
  Stream<BackendState> get states;

  /// Failures of the engine while it plays a loaded source (a decoder error, a
  /// file that vanished). Errors of `setSource` / `play` are thrown by those.
  Stream<Object> get errors;
  Future<void> dispose();
}
