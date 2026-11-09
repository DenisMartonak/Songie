import '../data/database.dart';
import '../remote/player_view.dart';
import 'player_service.dart';

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
