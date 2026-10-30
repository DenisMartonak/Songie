/// The steps of a sync run, as both devices show them.
enum SyncStage { hello, pulling, merging, choosing, applying, files, finishing }

/// What a sync run reports while it runs, then once at the end.
sealed class SyncProgress {
  const SyncProgress();
}

class SyncStep extends SyncProgress {
  const SyncStep(this.stage, {this.done = 0, this.total = 0});

  final SyncStage stage;

  /// Items finished of [total]; [total] is 0 when unknown.
  final int done;
  final int total;

  @override
  String toString() => 'SyncStep(${stage.name}, $done/$total)';
}

class SyncDone extends SyncProgress {
  const SyncDone(this.summary);

  final SyncSummary summary;

  @override
  String toString() => 'SyncDone($summary)';
}

class SyncFailed extends SyncProgress {
  const SyncFailed(this.failure);

  final SyncFailure failure;

  @override
  String toString() => 'SyncFailed(${failure.name})';
}

/// What a finished sync changed on this device.
class SyncSummary {
  const SyncSummary({
    required this.peerName,
    required this.playlistsChanged,
    required this.songsAdded,
    required this.filesCopied,
  });

  final String peerName;

  /// Playlists whose row or entries changed, not counting ones merged away.
  final int playlistsChanged;

  /// Songs live here now that were not before (a merged duplicate is not new).
  final int songsAdded;
  final int filesCopied;

  @override
  String toString() =>
      'SyncSummary($peerName: $playlistsChanged playlists, '
      '$songsAdded songs, $filesCopied files)';
}

enum SyncFailure {
  /// The peer did not answer at its address.
  notFound,

  /// The peer runs another schema version.
  schemaMismatch,

  /// The peer is in another sync.
  busy,

  /// The peer no longer knows this device (it unpaired).
  forgotten,

  /// The user cancelled, or left the conflict prompt.
  cancelled,

  /// The connection broke or the peer refused a step.
  network,
}

/// Asks a running sync to stop. Before changes are applied the run ends as
/// [SyncFailure.cancelled] with nothing changed; after that it finishes.
class SyncCancel {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;
}
