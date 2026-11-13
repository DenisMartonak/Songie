import '../data/database.dart';
import '../remote/player_view.dart';
import 'player_service.dart';

/// A room guest's player view: can go quiet on its own (headphones out, a
/// call) and later rejoin the room's playback.
abstract interface class LocalHold {
  /// Pauses this device only and keeps it quiet until [resumeLocally] or a
  /// local play.
  Future<void> holdLocally();

  /// Plays with the room again, at the host's song and position.
  Future<void> resumeLocally();

  /// Whether this device is holding quiet (see [holdLocally]).
  bool get heldLocally;
}

/// Where this device's own playback inputs go: keyboard shortcuts, the
/// system media controls (notification, headset, MPRIS, SMTC), song taps
/// and radio. Normally straight to [PlayerService], as always. While this
/// device is a Listen together guest ([room] returns its view), they go to
/// the room instead, where the guest's role decides: what it allows becomes
/// a request to the host, the rest is ignored. So a guest never plays,
/// pauses or replaces its own music on its own.
class PlayerInputs {
  PlayerInputs(this._player, {PlayerView? Function()? room})
    : _room = room ?? _none;

  static PlayerView? _none() => null;

  final PlayerService _player;
  final PlayerView? Function() _room;

  /// The room's guest view while this device is a guest; null otherwise.
  PlayerView? get room => _room();

  Future<void> play() => room?.play() ?? _player.play();
  Future<void> pause() => room?.pause() ?? _player.pause();
  Future<void> togglePlay() => room?.togglePlay() ?? _player.togglePlay();
  Future<void> next() => room?.next() ?? _player.next();
  Future<void> previous() => room?.previous() ?? _player.previous();
  Future<void> seek(Duration d) => room?.seek(d) ?? _player.seek(d);

  /// This device must go quiet on its own (headphones unplugged, an audio
  /// interruption): pauses it. While a guest, only this device holds; it
  /// does not ask the room to pause.
  Future<void> hold() {
    if (room case final LocalHold r) return r.holdLocally();
    return _player.pause();
  }

  /// Whether an interruption starting now should [hold] this device: when
  /// it plays, and while a room guest that is not held yet even when the
  /// room is paused, so the host playing on mid-call stays quiet here.
  bool get holdsForInterruption {
    if (room case final LocalHold r) return !r.heldLocally;
    return _player.state.playing;
  }

  /// The interruption [hold] was for ended and asks to resume.
  Future<void> resumeAfterHold() {
    if (room case final LocalHold r) return r.resumeLocally();
    return _player.play();
  }

  Future<void> setShuffle(bool on) async {
    final r = room;
    if (r != null) return r.setShuffle(on);
    _player.setShuffle(on);
  }

  Future<void> toggleShuffle() async {
    final r = room;
    if (r != null) return r.setShuffle(!r.state.shuffle);
    _player.setShuffle(!_player.state.shuffle);
  }

  /// Off, all, one, off.
  Future<void> cycleRepeat() async {
    final r = room;
    if (r == null) {
      _player.cycleRepeat();
      return;
    }
    await r.setRepeat(switch (r.state.repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    });
  }

  /// Plays [tracks] from [startIndex] (a song tap); in a room, asks the host
  /// to play them (Full control only).
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) =>
      room?.playTracks(
        tracks,
        startIndex: startIndex,
        sourcePlaylistId: sourcePlaylistId,
      ) ??
      _player.playQueue(
        tracks,
        startIndex: startIndex,
        sourcePlaylistId: sourcePlaylistId,
      );
}
