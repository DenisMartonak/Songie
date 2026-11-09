import 'dart:async';

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../innertube/ytm_models.dart';
import '../innertube/ytm_service.dart';
import '../library/yt_tracks.dart';
import 'player_inputs.dart';
import 'player_service.dart';

/// YouTube Music radio queues: a tapped song plays at once while its radio
/// (Innertube `next`) is fetched alongside the stream and appended to the
/// queue when it arrives.
///
/// More radio is fetched only while playing, when the player reaches the
/// second-to-last song of the radio queue, once per continuation token (no
/// idle work). A queue counts as the radio queue until anything calls
/// [PlayerService.playQueue] again ([PlayerService.queueEpoch]); answers for an
/// older queue are dropped.
///
/// Metadata upgrades for imported songs: a radio seed is upgraded from the
/// `next` response's current song ([YtTrackStore.upgradeFrom], fill-only), and
/// every song in a radio page goes through [YtTrackStore.upsertAll]'s
/// fill-only rule. Nothing here makes a request just to upgrade metadata.
class RadioController {
  RadioController(this._player, this._ytm, this._store, {this._inputs}) {
    _sub = _player.states.listen(_onState);
  }

  final PlayerService _player;
  final YtmService _ytm;
  final YtTrackStore _store;

  /// While a Listen together guest, a radio only asks the room to play its
  /// seed (no radio follows): the host owns the queue.
  final PlayerInputs? _inputs;
  late final StreamSubscription<PlayerState> _sub;

  /// [PlayerService.queueEpoch] of the radio queue, or null when none plays.
  int? _epoch;

  /// The next page's token for the radio queue; null when there is none or it
  /// is being fetched.
  String? _continuation;
  String _videoId = '';

  /// Track ids already in the radio queue, to drop repeats from later pages.
  final Set<String> _seen = {};

  /// Plays [seed] now and queues its radio. A seed that cannot be stored plays
  /// nothing (logged). A radio failure leaves the seed playing alone (logged,
  /// no notice).
  Future<void> playWithRadio(YtmSong seed) async {
    final Track track;
    switch (await _store.upsert(seed)) {
      case Ok(:final value):
        track = value;
      case Err(:final failure):
        AppLog.w('Radio: storing ${seed.videoId} failed: ${failure.message}');
        return;
    }
    await _start(track, seed.videoId);
  }

  /// [playWithRadio] for a track already in the library. A track without a
  /// YouTube video (a local file) has no radio: nothing happens (logged).
  ///
  /// With [playlistId] the queue after [t] is that radio playlist (an
  /// artist's radio, started from one of their songs) instead of [t]'s own.
  Future<void> startRadio(Track t, {String? playlistId}) async {
    final videoId = t.ytVideoId;
    if (videoId == null || videoId.isEmpty) {
      AppLog.i('Radio: ${t.id} has no YouTube video; not starting radio');
      return;
    }
    await _start(t, videoId, playlistId: playlistId);
  }

  Future<void> dispose() => _sub.cancel();

  Future<void> _start(Track seed, String videoId, {String? playlistId}) async {
    if (_inputs?.room case final room?) {
      await room.playTracks([seed]);
      return;
    }
    // The stream start and the radio request go out together.
    final playing = _player.playQueue([seed]);
    final epoch = _player.queueEpoch;
    _epoch = epoch;
    _continuation = null;
    _videoId = videoId;
    _seen
      ..clear()
      ..add(seed.id);
    final radio = _ytm.radio(videoId, playlistId: playlistId);
    await playing;
    final res = await radio;
    switch (res) {
      case Err(:final failure):
        AppLog.w('Radio for $videoId failed: ${failure.message}');
        return;
      case Ok(:final value):
        if (_player.queueEpoch != epoch) return;
        final current = value.current;
        if (current != null) await _store.upgradeFrom(seed, current);
        await _append(value, epoch);
    }
  }

  Future<void> _append(YtmRadio page, int epoch) async {
    final tracks = await _store.upsertAll(page.songs);
    // No await between this check and appendToQueue: a later playQueue would
    // otherwise be overtaken by this append.
    if (_player.queueEpoch != epoch || _epoch != epoch) return;
    final fresh = [
      for (final t in tracks)
        if (_seen.add(t.id)) t,
    ];
    // A page with nothing new ends the radio rather than asking again.
    if (fresh.isEmpty) {
      _continuation = null;
      return;
    }
    try {
      await _player.appendToQueue(fresh);
    } catch (e, st) {
      AppLog.w('Radio: queueing failed', e, st);
      return;
    }
    // The token is armed only once the page is in the queue: a playing tick
    // during the append would otherwise see the old end and fetch early.
    if (_player.queueEpoch != epoch || _epoch != epoch) return;
    _continuation = page.continuation;
  }

  void _onState(PlayerState s) {
    final epoch = _epoch;
    final token = _continuation;
    if (epoch == null || token == null) return;
    if (_player.queueEpoch != epoch) {
      _epoch = null;
      _continuation = null;
      return;
    }
    if (!s.playing || s.index < 0 || s.index < s.queue.length - 2) return;
    _continuation = null; // fetched once
    unawaited(_more(_videoId, token, epoch));
  }

  Future<void> _more(String videoId, String token, int epoch) async {
    try {
      final res = await _ytm.radio(videoId, continuation: token);
      switch (res) {
        case Err(:final failure):
          AppLog.w('Radio continuation failed: ${failure.message}');
        case Ok(:final value):
          await _append(value, epoch);
      }
    } catch (e, st) {
      AppLog.w('Radio continuation failed', e, st);
    }
  }
}
