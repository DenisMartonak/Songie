import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../remote/player_view.dart' show syncBeforeSending;
import '../../remote/remote_protocol.dart';
import '../island/island_host.dart';

/// The devices a menu offers "Play on" / "Add to queue on" for: the first 3
/// other online devices that speak this version. Empty signed out.
List<RemotePresence> playOnDevices(List<RemotePresence>? online) => [
  for (final d in online ?? const <RemotePresence>[])
    if (d.compatible && !d.inRoom) d,
].take(3).toList();

/// Plays [ids] on [d] from the first (as [sourcePlaylistId] when it is a
/// playlist's), or adds them to its queue. Syncs first so the device has the
/// songs ([syncBeforeSending]: a failed or slow sync still sends). Takes the
/// [container] rather than a `ref`, and [islands] got before the menu
/// closed: the menu that called is gone by the time the sync is done. Once
/// sent, the island says "Playing on" or "Added to queue on" the device.
Future<void> sendIdsTo(
  ProviderContainer container,
  Islands islands,
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
    islands.show('Playing on ${d.name}');
  } else {
    await controller.addNextOn(d, ids);
    islands.show('Added to queue on ${d.name}');
  }
}
