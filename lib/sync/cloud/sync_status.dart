/// Where cloud sync is at.
enum SyncPhase {
  /// Nothing to do: everything is up and down (or not signed in).
  idle,

  /// Pushing or pulling rows.
  syncing,

  /// The device is offline; changes wait for the connection.
  offline,

  /// The last sync failed for another reason; the next trigger retries.
  error,

  /// The server refuses this device's changes because its date and time are
  /// more than a day ahead; changes still come down.
  clockWrong,

  /// Another device runs a newer Songies: some of its changes wait here
  /// until this app is updated. Everything else syncs.
  updateNeeded,
}

/// Cloud sync's state for the account screen.
class SyncStatus {
  const SyncStatus(this.phase, {this.lastSynced});

  final SyncPhase phase;

  /// When a sync last finished for the signed-in account, if ever.
  final DateTime? lastSynced;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSynced == lastSynced;

  @override
  int get hashCode => Object.hash(phase, lastSynced);

  @override
  String toString() => 'SyncStatus(${phase.name}, $lastSynced)';
}
