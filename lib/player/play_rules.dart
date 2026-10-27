/// How much of a song must be heard before it counts as played. Shared by
/// YouTube play reports and (Plan 7) listening statistics.
const kPlayThreshold = Duration(seconds: 30);

/// Whether [heard] makes a play: the threshold, or the whole song when it is
/// shorter than that.
bool reachedPlay(Duration heard, Duration? length) =>
    heard >= kPlayThreshold || (length != null && heard >= length);
