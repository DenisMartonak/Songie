import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'remote_controller.dart';

/// What the player UI (player bar, Now Playing, queue, playlist page) reads
/// and commands: this device's player, or the device being controlled.
abstract class PlayerView {
  Stream<PlayerState> get states;
  PlayerState get state;

  /// Whether this shows another device.
  bool get isRemote;

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlay();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration d);
  Future<void> setVolume(double v);
  Future<void> setShuffle(bool on);
  Future<void> setRepeat(RepeatMode m);

  /// Index into [state]`.queue`.
  Future<void> playAt(int i);
  Future<void> removeAt(int i);
  Future<void> move(int from, int to);

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  });

  /// Queued right after the current song.
  Future<void> addNext(List<Track> tracks);

  /// Queued at the end.
  Future<void> addToEnd(List<Track> tracks);
}

/// This device's player.
class LocalPlayerView implements PlayerView {
  LocalPlayerView(this._player);

  final PlayerService _player;

  @override
  Stream<PlayerState> get states => _player.states;
  @override
  PlayerState get state => _player.state;
  @override
  bool get isRemote => false;

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> togglePlay() => _player.togglePlay();
  @override
  Future<void> next() => _player.next();
  @override
  Future<void> previous() => _player.previous();
  @override
  Future<void> seek(Duration d) => _player.seek(d);
  @override
  Future<void> setVolume(double v) => _player.setVolume(v);

  @override
  Future<void> setShuffle(bool on) async => _player.setShuffle(on);

  /// The player only cycles off → all → one; at most two steps get there.
  @override
  Future<void> setRepeat(RepeatMode m) async {
    for (var i = 0; i < RepeatMode.values.length; i++) {
      if (_player.state.repeat == m) return;
      _player.cycleRepeat();
    }
  }

  @override
  Future<void> playAt(int i) => _player.playAt(i);
  @override
  Future<void> removeAt(int i) => _player.removeAt(i);
  @override
  Future<void> move(int from, int to) async => _player.move(from, to);

  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) => _player.playQueue(
    tracks,
    startIndex: startIndex,
    sourcePlaylistId: sourcePlaylistId,
  );

  @override
  Future<void> addNext(List<Track> tracks) => _player.addToQueue(tracks);
  @override
  Future<void> addToEnd(List<Track> tracks) => _player.appendToQueue(tracks);
}

/// The device [RemoteController] is linked to. Songs are sent as ids; a sync
/// goes first so songs stored here just now can reach the host (P2).
class RemotePlayerView implements PlayerView {
  RemotePlayerView(this._controller, this._syncNow);

  final RemoteController _controller;
  final Future<void> Function() _syncNow;

  @override
  Stream<PlayerState> get states => _controller.states;
  @override
  PlayerState get state => _controller.state;
  @override
  bool get isRemote => true;

  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> togglePlay() => _controller.togglePlay();
  @override
  Future<void> next() => _controller.next();
  @override
  Future<void> previous() => _controller.previous();
  @override
  Future<void> seek(Duration d) => _controller.seek(d);
  @override
  Future<void> setVolume(double v) => _controller.setVolume(v);
  @override
  Future<void> setShuffle(bool on) => _controller.setShuffle(on);
  @override
  Future<void> setRepeat(RepeatMode m) => _controller.setRepeat(m);
  @override
  Future<void> playAt(int i) => _controller.playAt(i);
  @override
  Future<void> removeAt(int i) => _controller.removeAt(i);
  @override
  Future<void> move(int from, int to) => _controller.move(from, to);

  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) async {
    if (tracks.isEmpty) return;
    await _sync();
    await _controller.playTracks(
      _ids(tracks),
      startIndex: startIndex,
      sourcePlaylistId: sourcePlaylistId,
    );
  }

  @override
  Future<void> addNext(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await _sync();
    await _controller.addNext(_ids(tracks));
  }

  @override
  Future<void> addToEnd(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await _sync();
    await _controller.addToEnd(_ids(tracks));
  }

  /// A failed sync still lets the command go: the host waits a little for
  /// ids it lacks and the songs may well be there already.
  Future<void> _sync() async {
    try {
      await _syncNow();
    } on Object catch (e, s) {
      AppLog.w('remote view: sync before sending failed', e, s);
    }
  }

  static List<String> _ids(List<Track> tracks) => [
    for (final t in tracks) t.id,
  ];
}
