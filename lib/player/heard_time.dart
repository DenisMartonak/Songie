/// Time a song was actually heard, from a stream of player positions.
///
/// It is the sum of small forward position steps while playing: a seek (a
/// big jump either way) and paused time add nothing. Shared by YouTube play
/// reports and listening statistics.
class HeardTime {
  /// Position steps larger than this are seeks, not listening.
  static const _maxStep = Duration(seconds: 5);

  /// A first tick this close to the start is credited as heard.
  static const _startCredit = Duration(seconds: 2);

  Duration _heard = Duration.zero;
  Duration? _lastPos;
  bool _wasPlaying = false;

  Duration get heard => _heard;

  /// Starts over: nothing heard and no previous position.
  void reset() {
    _heard = Duration.zero;
    _lastPos = null;
    _wasPlaying = false;
  }

  void onState({required bool playing, required Duration position}) {
    final last = _lastPos;
    _lastPos = position;
    // The step into a stopping state counts: playing was true until then.
    if (playing || _wasPlaying) {
      if (last == null) {
        if (playing && position <= _startCredit) _heard += position;
      } else {
        final step = position - last;
        if (step > Duration.zero && step <= _maxStep) _heard += step;
      }
    }
    _wasPlaying = playing;
  }
}
