import 'dart:async';

import 'package:songies/player/audio_backend.dart';

/// In-memory [AudioBackend] for tests. Records every call in [calls] as
/// `setSource:<path or url>`, `play`, `pause`, `seek:<ms>`, `stop`, `setVolume:<v>`, `dispose`.
///
/// Like a real engine, it clears `completed` when a new source is loaded or the
/// position is moved, and reports its own `playing` flag.
class FakeAudioBackend implements AudioBackend {
  final List<String> calls = [];

  /// Make the next call to the named method (e.g. `setSource`) throw once.
  final Set<String> failNext = {};

  /// Called with each source passed to `setSource` (e.g. to make it throw).
  void Function(AudioSourceRef source)? onSetSource;

  final StreamController<BackendState> _controller =
      StreamController<BackendState>.broadcast(sync: true);
  BackendState _state = const BackendState();

  /// Latest state this fake has reported.
  BackendState get current => _state;

  /// Paths/urls passed to `setSource`, in order.
  List<String> get sources => [
    for (final c in calls)
      if (c.startsWith('setSource:')) c.substring('setSource:'.length),
  ];

  /// Pushes [s] to listeners as if the engine had reported it.
  void emit(BackendState s) {
    _state = s;
    _controller.add(s);
  }

  /// The loaded source played to its end.
  void complete() => emit(
    BackendState(
      completed: true,
      position: _state.duration ?? _state.position,
      duration: _state.duration,
    ),
  );

  void setPosition(Duration d) => emit(_copy(position: d));

  void setDuration(Duration? d) => emit(_copy(duration: d));

  void setBuffering(bool b) => emit(_copy(buffering: b));

  void clearCalls() => calls.clear();

  BackendState _copy({
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
  }) => BackendState(
    playing: playing ?? _state.playing,
    buffering: buffering ?? _state.buffering,
    completed: completed ?? _state.completed,
    position: position ?? _state.position,
    duration: duration ?? _state.duration,
  );

  void _maybeFail(String name) {
    if (failNext.remove(name)) throw StateError('fake $name failure');
  }

  @override
  Future<void> setSource(AudioSourceRef s) async {
    final label = switch (s) {
      FileSource(:final path) => path,
      UrlSource(:final url) => url.toString(),
    };
    calls.add('setSource:$label');
    _maybeFail('setSource');
    onSetSource?.call(s);
    emit(
      BackendState(
        playing: false,
        completed: false,
        position: Duration.zero,
        duration: _state.duration,
      ),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _maybeFail('play');
    emit(_copy(playing: true, completed: false));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(_copy(playing: false));
  }

  @override
  Future<void> seek(Duration d) async {
    calls.add('seek:${d.inMilliseconds}');
    emit(_copy(position: d, completed: false));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    emit(
      BackendState(
        playing: false,
        completed: false,
        position: Duration.zero,
        duration: _state.duration,
      ),
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume:$volume');
    _maybeFail('setVolume');
  }

  @override
  Stream<BackendState> get states => _controller.stream;

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
  }
}
