import 'dart:async';
import 'dart:math';

import 'package:songies/core/log.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/youtube/yt_models.dart';

enum RepeatMode { off, all, one }

/// Immutable snapshot of the player. [queue] is the *playing* order (already
/// shuffled when [shuffle] is on) and [index] is -1 when it is empty.
class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.volume = 1.0,
    this.sourcePlaylistId,
    this.error,
  });

  final List<Track> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration? duration;
  final bool shuffle;
  final RepeatMode repeat;

  /// Output gain 0..1; not persisted.
  final double volume;
  final String? sourcePlaylistId;
  final String? error;

  Track? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  static const Object _keep = Object();

  /// Nullable fields ([duration], [sourcePlaylistId], [error]) keep their value
  /// unless a new one (including an explicit null) is passed.
  PlayerState copyWith({
    List<Track>? queue,
    int? index,
    bool? playing,
    bool? buffering,
    Duration? position,
    Object? duration = _keep,
    bool? shuffle,
    RepeatMode? repeat,
    double? volume,
    Object? sourcePlaylistId = _keep,
    Object? error = _keep,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      index: index ?? this.index,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      position: position ?? this.position,
      duration: identical(duration, _keep)
          ? this.duration
          : duration as Duration?,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      volume: volume ?? this.volume,
      sourcePlaylistId: identical(sourcePlaylistId, _keep)
          ? this.sourcePlaylistId
          : sourcePlaylistId as String?,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

/// A queue slot. Identity (not the track) distinguishes the same track queued
/// twice.
class _Entry {
  _Entry(this.track);
  final Track track;

  /// Whether the engine-error retry (fresh stream URL) was already used.
  bool engineRetried = false;
}

/// The single source of truth for what is playing. Platform-agnostic: audio
/// goes through an [AudioBackend], file lookup through a [TrackResolver].
///
/// Commands that touch the backend (`playQueue`, `next`, `previous`, `playAt`,
/// `removeAt`, `play`, `pause`, `togglePlay`, `seek`) run one at a time, in call
/// order. `move`, `setShuffle` and `cycleRepeat` are synchronous state edits
/// that never touch the backend.
class PlayerService {
  PlayerService(
    this._backend,
    this._resolver, {
    this._onMissing,
    this._onTrackStarted,
    this._onUnavailable,
    Random? random,
  }) : _random = random ?? Random() {
    _sub = _backend.states.listen(_onBackendState);
    _errorSub = _backend.errors.listen(_onBackendError);
  }

  /// Past this much progress, "previous" restarts the track instead.
  static const Duration restartThreshold = Duration(seconds: 3);

  static const String noPlayableFilesError = 'No playable files in queue';
  static const String playbackFailedError = 'Playback failed';
  static const String engineFailedError = 'Engine failed on every track';

  final AudioBackend _backend;
  final TrackResolver _resolver;
  final Future<void> Function(String trackId)? _onMissing;
  final Future<void> Function(Track track, String? playlistId)? _onTrackStarted;
  final Future<void> Function(String trackId)? _onUnavailable;
  final Random _random;

  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();
  late final StreamSubscription<BackendState> _sub;
  late final StreamSubscription<Object> _errorSub;

  PlayerState _state = const PlayerState();

  /// Playing order, and the order before shuffling (removals applied to both).
  final List<_Entry> _queue = [];
  final List<_Entry> _original = [];

  /// Whether the backend currently holds the current track's source.
  bool _loaded = false;

  /// Bumped whenever playback starts or stops; lets a stale completion event
  /// be recognised and dropped.
  int _generation = 0;
  bool _wasCompleted = false;
  bool _disposed = false;

  /// Tracks in a row the engine failed on mid-playback, to stop skipping when
  /// the whole queue is unplayable. Reset when something plays to its end or
  /// the user picks what to play.
  int _engineFailures = 0;
  Future<void> _tail = Future<void>.value();

  /// Set by [_tryStart] when resolving failed in a way that would fail every
  /// track alike (no network, or yt-dlp itself broken); playback then stops
  /// instead of skipping on.
  Failure? _networkFailure;

  /// The entry that failed with [_networkFailure]; it becomes current so a
  /// later play retries it.
  _Entry? _networkEntry;

  /// True while [_tryStart] resolves a stream for an entry that was already
  /// shown as current; the old track's position ticks are ignored meanwhile.
  bool _resolving = false;

  /// The entry whose successor was already prefetched.
  _Entry? _prefetchedFor;

  Stream<PlayerState> get states => _controller.stream;
  PlayerState get state => _state;

  // --- commands -------------------------------------------------------------

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) => _locked(() async {
    _engineFailures = 0;
    final entries = [for (final t in tracks) _Entry(t)];
    _original
      ..clear()
      ..addAll(entries);
    _queue.clear();
    if (entries.isEmpty) {
      _emit(
        _state.copyWith(
          queue: const [],
          index: -1,
          sourcePlaylistId: sourcePlaylistId,
        ),
      );
      await _stopBackend();
      _markStopped();
      return;
    }
    var start = startIndex.clamp(0, entries.length - 1);
    if (_state.shuffle) {
      final first = entries[start];
      _queue
        ..add(first)
        ..addAll(_shuffled(entries.where((e) => !identical(e, first))));
      start = 0;
    } else {
      _queue.addAll(entries);
    }
    _emit(
      _state.copyWith(
        queue: _queueTracks(),
        index: start,
        sourcePlaylistId: sourcePlaylistId,
        position: Duration.zero,
        duration: null,
      ),
    );
    await _startFirstPlayable(_candidates(start, wrap: _wraps));
  });

  Future<void> play() => _locked(_playNow);

  Future<void> pause() => _locked(_pauseNow);

  /// Decides inside the lock, so rapid taps alternate instead of repeating.
  Future<void> togglePlay() =>
      _locked(() => _state.playing ? _pauseNow() : _playNow());

  /// Manual next. Ignores repeat-one; at the end of the queue it wraps (repeat
  /// all) or stops (otherwise).
  Future<void> next() => _locked(() {
    _engineFailures = 0;
    return _advance();
  });

  Future<void> previous() => _locked(() async {
    _engineFailures = 0;
    final entry = _currentEntry;
    if (entry == null) return;
    final index = _state.index;
    if (index == 0 || _state.position > restartThreshold) {
      await _restartCurrent(entry);
      return;
    }
    final found = await _startFirstPlayable(
      _candidates(index - 1, step: -1, wrap: false),
      giveUpOnFailure: false,
    );
    if (!found && _networkFailure == null) {
      // Nothing earlier can be played: keep the current track going.
      await _restartCurrent(entry);
    }
  });

  Future<void> seek(Duration d) => _locked(() async {
    if (!_loaded) return;
    _wasCompleted = false;
    await _backend.seek(d);
    _emit(_state.copyWith(position: d));
  });

  /// Sets the output gain, clamped to 0..1 (NaN is ignored).
  Future<void> setVolume(double volume) => _locked(() async {
    if (volume.isNaN) return;
    final v = volume.clamp(0.0, 1.0);
    await _backend.setVolume(v);
    _emit(_state.copyWith(volume: v));
  });

  Future<void> playAt(int index) => _locked(() async {
    _engineFailures = 0;
    if (index < 0 || index >= _queue.length) return;
    await _startFirstPlayable(_candidates(index, wrap: _wraps));
  });

  Future<void> removeAt(int index) => _locked(() async {
    if (index < 0 || index >= _queue.length) return;
    final current = _state.index;
    final wasPlaying = _state.playing;
    final removed = _queue.removeAt(index);
    _original.remove(removed);

    if (index != current) {
      _emit(
        _state.copyWith(
          queue: _queueTracks(),
          index: index < current ? current - 1 : current,
        ),
      );
      return;
    }

    if (_queue.isEmpty) {
      _emit(_state.copyWith(queue: const [], index: -1));
      await _stopBackend();
      _markStopped();
      return;
    }
    final atEnd = index >= _queue.length;
    _emit(
      _state.copyWith(
        queue: _queueTracks(),
        index: atEnd ? _queue.length - 1 : index,
      ),
    );
    if (!wasPlaying) {
      // Don't start anything the user didn't ask for; play() loads it.
      await _stopBackend();
      _markStopped();
    } else if (!atEnd) {
      await _startFirstPlayable(_candidates(index, wrap: _wraps));
    } else if (_state.repeat == RepeatMode.all) {
      await _startFirstPlayable(_candidates(0, wrap: true));
    } else {
      await _endOfQueue();
    }
  });

  // --- synchronous state edits ---------------------------------------------

  /// Moves the track at [from] so it ends up at [to]. The current track keeps
  /// playing; only [PlayerState.index] follows it.
  void move(int from, int to) {
    final n = _queue.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    final current = _currentEntry;
    _queue.insert(to, _queue.removeAt(from));
    _emit(
      _state.copyWith(
        queue: _queueTracks(),
        index: current == null ? -1 : _queue.indexOf(current),
      ),
    );
  }

  void setShuffle(bool on) {
    if (on == _state.shuffle) return;
    final current = _currentEntry;
    if (on) {
      _original
        ..clear()
        ..addAll(_queue);
      if (current != null) {
        final rest = _shuffled(_queue.where((e) => !identical(e, current)));
        _queue
          ..clear()
          ..add(current)
          ..addAll(rest);
      }
    } else {
      _queue
        ..clear()
        ..addAll(_original);
    }
    _emit(
      _state.copyWith(
        shuffle: on,
        queue: _queueTracks(),
        index: current == null ? -1 : _queue.indexOf(current),
      ),
    );
  }

  void cycleRepeat() {
    final next = switch (_state.repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    _emit(_state.copyWith(repeat: next));
  }

  /// Stops the player and releases the backend.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _sub.cancel();
    await _errorSub.cancel();
    await _controller.close();
    await _backend.dispose();
  }

  // --- internals ------------------------------------------------------------

  bool get _wraps => _state.repeat == RepeatMode.all;

  _Entry? get _currentEntry {
    final i = _state.index;
    return i >= 0 && i < _queue.length ? _queue[i] : null;
  }

  List<Track> _queueTracks() =>
      List<Track>.unmodifiable([for (final e in _queue) e.track]);

  List<_Entry> _shuffled(Iterable<_Entry> entries) =>
      entries.toList()..shuffle(_random);

  void _emit(PlayerState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  /// Runs [body] after every previously queued command has finished.
  Future<void> _locked(Future<void> Function() body) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous
        .then((_) async {
          if (_disposed) return;
          await body();
        })
        .whenComplete(done.complete);
  }

  /// Queue entries to try, starting at [start] and moving by [step]; each entry
  /// at most once, wrapping around only when [wrap] is set.
  List<_Entry> _candidates(int start, {int step = 1, required bool wrap}) {
    final n = _queue.length;
    final out = <_Entry>[];
    for (var k = 0; k < n; k++) {
      var pos = start + step * k;
      if (pos < 0 || pos >= n) {
        if (!wrap) break;
        pos = ((pos % n) + n) % n;
      }
      out.add(_queue[pos]);
    }
    return out;
  }

  /// Starts the first entry of [candidates] that can be played. Missing files
  /// are reported through `onMissing`. If none can be played, either gives up
  /// (stop + error) or just reports failure.
  Future<bool> _startFirstPlayable(
    List<_Entry> candidates, {
    bool giveUpOnFailure = true,
  }) async {
    // A new attempt starts clean, so failing again is a new error to show.
    if (_state.error != null) _emit(_state.copyWith(error: null));
    _networkFailure = null;
    final shownIndex = _state.index;
    for (final entry in candidates) {
      if (await _tryStart(entry)) return true;
      if (await _haltOnNetworkFailure()) return false;
    }
    if (!giveUpOnFailure && _state.index != shownIndex) {
      // A YouTube candidate was shown while it resolved; nothing started, so
      // the previous track is still the current one.
      _emit(_state.copyWith(index: shownIndex, buffering: false));
    }
    if (giveUpOnFailure) {
      await _stopBackend();
      _markStopped();
      final last = candidates.isEmpty ? null : _queue.indexOf(candidates.last);
      _emit(
        _state.copyWith(
          error: noPlayableFilesError,
          index: last == null || last < 0 ? null : last,
        ),
      );
    }
    return false;
  }

  Future<void> _playNow() async {
    final entry = _currentEntry;
    if (entry == null) return;
    if (!_loaded) {
      await _startFirstPlayable([entry]);
      return;
    }
    _wasCompleted = false;
    await _backend.play();
    _emit(_state.copyWith(playing: true));
  }

  Future<void> _pauseNow() async {
    if (!_loaded) return;
    await _backend.pause();
    _emit(_state.copyWith(playing: false));
  }

  /// Stops playback with the network failure's message, if [_tryStart] saw one.
  Future<bool> _haltOnNetworkFailure() async {
    final failure = _networkFailure;
    if (failure == null) return false;
    await _stopBackend();
    _markStopped();
    final i = _networkEntry == null ? -1 : _queue.indexOf(_networkEntry!);
    _emit(_state.copyWith(error: failure.message, index: i < 0 ? null : i));
    return true;
  }

  /// yt-dlp failures that would hit every YouTube track alike.
  static bool _haltsQueue(Failure f) => switch (ytErrorKindOf(f)) {
    YtErrorKind.extractor ||
    YtErrorKind.missingBinary ||
    YtErrorKind.unknown => true,
    _ => false,
  };

  Future<bool> _tryStart(_Entry entry, {bool report = true}) async {
    final track = entry.track;
    _prefetchedFor = null;
    if (track.source == 'yt' && !track.unavailable) {
      // Resolving a stream can take seconds: show the target right away.
      final index = _queue.indexOf(entry);
      if (index >= 0) {
        _emit(
          _state.copyWith(
            index: index,
            position: Duration.zero,
            buffering: true,
            duration: _durationOf(track),
          ),
        );
      }
    }
    final Result<AudioSourceRef> resolved;
    _resolving = true;
    try {
      resolved = await _resolver.resolve(track);
    } catch (e, s) {
      AppLog.w('Resolving ${track.id} failed', e, s);
      return false;
    } finally {
      _resolving = false;
    }
    switch (resolved) {
      case Err(:final failure):
        if (failure.kind == FailureKind.network ||
            (track.source == 'yt' && _haltsQueue(failure))) {
          AppLog.w('Cannot play ${track.id}: ${failure.message}');
          _networkFailure = failure;
          _networkEntry = entry;
        } else if (failure.kind == FailureKind.notFound) {
          if (track.source == 'yt') {
            await _reportUnavailable(track.id);
          } else {
            await _reportMissing(track.id);
          }
        } else {
          AppLog.w('Cannot play ${track.id}: ${failure.message}');
        }
        return false;
      case Ok(:final value):
        final index = _queue.indexOf(entry);
        if (index < 0) return false;
        _loaded = false; // the backend's contents are undefined from here on
        _wasCompleted = false;
        _emit(
          _state.copyWith(
            index: index,
            position: Duration.zero,
            buffering: false,
            duration: _durationOf(track),
          ),
        );
        try {
          await _backend.setSource(value);
          await _backend.play();
        } catch (e, s) {
          AppLog.w('Backend failed to play ${track.id}', e, s);
          // Usually an expired or IP-bound stream URL (HTTP 403).
          return _retryWithFreshStream(entry, report: report);
        }
        _loaded = true;
        _generation++;
        _emit(_state.copyWith(playing: true, error: null));
        if (report) await _reportStarted(track);
        return true;
    }
  }

  /// Re-resolves a YouTube [entry] once with its cached stream URL dropped
  /// (it may have expired or be bound to an old IP). False when the entry is
  /// not a YouTube track, was already retried, or failed again.
  Future<bool> _retryWithFreshStream(
    _Entry entry, {
    required bool report,
  }) async {
    if (entry.track.source != 'yt' || entry.engineRetried) return false;
    entry.engineRetried = true;
    _resolver.invalidate(entry.track);
    _networkFailure = null;
    return _tryStart(entry, report: report);
  }

  Duration? _durationOf(Track t) =>
      t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null;

  Future<void> _reportMissing(String trackId) async {
    try {
      await _onMissing?.call(trackId);
    } catch (e, s) {
      AppLog.e('onMissing failed for $trackId', e, s);
    }
  }

  Future<void> _reportUnavailable(String trackId) async {
    try {
      await _onUnavailable?.call(trackId);
    } catch (e, s) {
      AppLog.e('onUnavailable failed for $trackId', e, s);
    }
  }

  Future<void> _reportStarted(Track track) async {
    try {
      await _onTrackStarted?.call(track, _state.sourcePlaylistId);
    } catch (e, s) {
      AppLog.e('onTrackStarted failed for ${track.id}', e, s);
    }
  }

  Future<void> _stopBackend() async {
    try {
      await _backend.stop();
    } catch (e, s) {
      AppLog.w('Backend stop failed', e, s);
    }
  }

  void _markStopped() {
    _loaded = false;
    _wasCompleted = false;
    _generation++;
    _emit(
      _state.copyWith(
        playing: false,
        buffering: false,
        position: Duration.zero,
      ),
    );
  }

  /// Moves on after the current track ended or was skipped: next track, wrap
  /// (repeat all) or stop (repeat off).
  Future<void> _advance() async {
    if (_queue.isEmpty) return;
    final next = _state.index + 1;
    if (next < _queue.length) {
      await _startFirstPlayable(_candidates(next, wrap: _wraps));
    } else if (_wraps) {
      await _startFirstPlayable(_candidates(0, wrap: true));
    } else {
      await _endOfQueue();
    }
  }

  Future<void> _endOfQueue() async {
    await _stopBackend();
    _markStopped();
  }

  /// Back to the start of [entry]: a seek if it is loaded, a fresh load if not.
  Future<void> _restartCurrent(_Entry entry) async {
    if (!_loaded) {
      await _startFirstPlayable([entry]);
      return;
    }
    _wasCompleted = false;
    await _backend.seek(Duration.zero);
    _emit(_state.copyWith(position: Duration.zero));
  }

  // --- backend events -------------------------------------------------------

  void _onBackendState(BackendState s) {
    if (_disposed) return;
    final completedNow = s.completed && !_wasCompleted;
    _wasCompleted = s.completed;
    // The previous track's ticks would overwrite the resolving one's state.
    if (_resolving) return;
    _emit(
      _state.copyWith(
        position: s.position,
        buffering: s.buffering,
        duration: s.duration ?? _currentDuration(),
      ),
    );
    _maybePrefetch();
    if (completedNow && _loaded) {
      final generation = _generation;
      _locked(() => _handleCompleted(generation))
          .catchError((Object e, StackTrace st) {
            AppLog.e('Handling track completion failed', e, st);
          });
    }
  }

  static const Duration prefetchLead = Duration(seconds: 20);

  /// Warms the next track's stream once the current one is nearly over.
  void _maybePrefetch() {
    final entry = _currentEntry;
    final duration = _state.duration;
    if (entry == null ||
        duration == null ||
        !_state.playing ||
        !_loaded ||
        identical(_prefetchedFor, entry) ||
        duration - _state.position > prefetchLead) {
      return;
    }
    _prefetchedFor = entry;
    if (_state.repeat == RepeatMode.one) return;
    // The same order `_advance` tries entries in, minus ones known unplayable.
    _Entry? next;
    for (final c in _candidates(_state.index + 1, wrap: _wraps)) {
      if (identical(c, entry)) break;
      if (!c.track.unavailable) {
        next = c;
        break;
      }
    }
    if (next == null) return;
    _resolver.prefetch(next.track).catchError((Object e, StackTrace st) {
      AppLog.w('Prefetching ${next!.track.id} failed', e, st);
    });
  }

  Duration? _currentDuration() {
    final t = _state.current;
    return t == null ? null : _durationOf(t);
  }

  /// The engine failed while playing the current track: log it, then move on
  /// as if the track had ended (next playable track, wrap, or stop).
  void _onBackendError(Object error) {
    if (_disposed) return;
    final entry = _currentEntry;
    if (entry == null) return;
    _locked(() async {
      // Stopped, or the user already moved on since this was reported.
      if (!_loaded || !identical(_currentEntry, entry)) return;
      AppLog.w('Playback of ${entry.track.id} failed: $error');
      if (entry.track.source == 'yt' && !entry.engineRetried) {
        // The stream URL may have expired: fetch a fresh one, once per entry.
        if (await _retryWithFreshStream(entry, report: false)) return;
        if (await _haltOnNetworkFailure()) return;
      }
      if (++_engineFailures >= _queue.length) {
        await _stopBackend();
        _markStopped();
        _emit(_state.copyWith(error: engineFailedError));
        return;
      }
      await _advance();
      if (!_state.playing && _state.error == null) {
        _emit(_state.copyWith(error: playbackFailedError));
      }
    }).catchError((Object e, StackTrace st) {
      AppLog.e('Handling a playback error failed', e, st);
    });
  }

  Future<void> _handleCompleted(int generation) async {
    // The user (or a queue edit) already moved on since this was reported.
    if (generation != _generation || !_loaded) return;
    _engineFailures = 0;
    final track = _state.current;
    if (_state.repeat == RepeatMode.one && track != null) {
      _wasCompleted = false;
      await _backend.seek(Duration.zero);
      await _backend.play();
      _generation++;
      _emit(_state.copyWith(position: Duration.zero, playing: true));
      await _reportStarted(track);
      return;
    }
    await _advance();
  }
}
