import 'dart:async';

import '../core/log.dart';
import '../data/database.dart';
import '../player/heard_time.dart';
import '../player/play_rules.dart';
import '../player/player_service.dart';
import 'listen_store.dart';

/// Records listens: one row per start of a song, holding the time it was
/// actually heard. Reacts to player events only, so it does nothing while
/// nothing plays: no timers, no polling.
///
/// A listen opens on each [PlayerService.trackStarts] event and ends at the
/// next one, when the current track becomes null, or on [dispose]. Pausing
/// and seeking never end one. Its row is written once something was heard,
/// saved again about every [checkpoint] of heard time, and finally when it
/// ends.
class ListenRecorder {
  ListenRecorder(
    Stream<PlayerState> states,
    Stream<Track> starts,
    this._store, {
    DateTime Function() now = DateTime.now,
    // Named parameters can't be private initializing formals.
    // ignore: prefer_initializing_formals
  }) : _now = now {
    _stateSub = states.listen(_onState);
    _startSub = starts.listen(_onStart);
  }

  /// Heard time between progress saves of a running listen.
  static const checkpoint = Duration(seconds: 30);

  final ListenStore _store;
  final DateTime Function() _now;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<Track> _startSub;

  /// Store calls run one after another, so a listen's writes stay in order.
  Future<void> _writes = Future<void>.value();
  _Listen? _open;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSub.cancel();
    _startSub.cancel();
    _close();
  }

  void _onStart(Track t) {
    // Heard time up to here belongs to the listen being left.
    _close();
    _open = _Listen(t);
  }

  void _onState(PlayerState s) {
    final t = s.current;
    if (t == null) {
      _close();
      return;
    }
    final l = _open;
    // Ticks of another song (the old one's last, or a new one's before its
    // start event) belong to no open listen.
    if (l == null || l.track.id != t.id) return;
    if (s.duration != null) l.length = s.duration;
    l.heard.onState(playing: s.playing && !s.buffering, position: s.position);
    final heard = l.heard.heard;
    if (heard == Duration.zero) return;
    if (!l.started) {
      l.started = true;
      final startedAt = _now().toUtc().subtract(heard);
      final counted = l.counted;
      _enqueue(() async {
        l.id = await _store.start(l.track, startedAt, heard, counted);
      });
    }
    if (heard >= l.nextCheckpoint) {
      // The next multiple of [checkpoint] above what was heard.
      l.nextCheckpoint =
          checkpoint * (heard.inMicroseconds ~/ checkpoint.inMicroseconds + 1);
      _save(l);
    }
  }

  /// Ends the open listen with a final save, if anything was heard.
  void _close() {
    final l = _open;
    _open = null;
    if (l != null && l.started) _save(l);
  }

  void _save(_Listen l) {
    final heard = l.heard.heard;
    final counted = l.counted;
    _enqueue(() async {
      final id = l.id;
      // The row could not be written: nothing to update.
      if (id == null) return;
      await _store.update(id, heard, counted);
    });
  }

  void _enqueue(Future<void> Function() write) {
    _writes = _writes.then((_) async {
      try {
        await write();
      } catch (e, s) {
        AppLog.w('Saving a listen failed', e, s);
      }
    });
  }
}

class _Listen {
  _Listen(this.track)
    : length = track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : null;

  final Track track;
  final heard = HeardTime();

  /// The state's duration once known, else the track's.
  Duration? length;
  bool started = false;
  String? id;
  Duration nextCheckpoint = ListenRecorder.checkpoint;

  bool get counted => reachedPlay(heard.heard, length);
}
