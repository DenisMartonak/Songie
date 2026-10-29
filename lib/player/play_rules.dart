/// How much of a song must be heard before it counts as played. Shared by
/// YouTube play reports and (Plan 7) listening statistics.
const kPlayThreshold = Duration(seconds: 30);

/// A short song counts as heard whole when it got within this of its end:
/// position ticks are sparse, so the last one rarely lands exactly on the
/// duration.
const kPlayEndTolerance = Duration(seconds: 1);

/// Whether [heard] makes a play: the threshold, or the whole song when it is
/// shorter than that.
bool reachedPlay(Duration heard, Duration? length) =>
    heard >= kPlayThreshold || (length != null && heard >= length);

/// [reachedPlay], allowing [kPlayEndTolerance] for the whole-song rule.
bool reachedPlayNearEnd(Duration heard, Duration? length) =>
    reachedPlay(heard, length == null ? null : length - kPlayEndTolerance);
