import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../remote/player_view.dart' show syncBeforeSending;
import '../../remote/remote_protocol.dart';

/// The devices a menu offers "Play on" / "Add to queue on" for: the first 3
/// other online devices that speak this version. Empty signed out.
List<RemotePresence> playOnDevices(List<RemotePresence>? online) => [
  for (final d in online ?? const <RemotePresence>[])
    if (d.compatible) d,
].take(3).toList();

/// Plays [ids] on [d] from the first (as [sourcePlaylistId] when it is a
/// playlist's), or adds them to its queue. Syncs first so the device has the
/// songs ([syncBeforeSending]: a failed or slow sync still sends). Takes the
/// [container] rather than a `ref`: the menu that called is gone by the time
/// the sync is done.
Future<void> sendIdsTo(
  ProviderContainer container,
  RemotePresence d, {
  required List<String> ids,
  required bool play,
  String? sourcePlaylistId,
}) async {
  if (ids.isEmpty) return;
  final controller = container.read(remoteControllerProvider);
  if (controller == null) return;
  await syncBeforeSending(container.read(cloudSyncProvider).syncNow);
  if (play) {
    await controller.playTracksOn(d, ids, sourcePlaylistId: sourcePlaylistId);
  } else {
    await controller.addNextOn(d, ids);
  }
}
