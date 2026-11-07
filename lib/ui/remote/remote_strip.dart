import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../remote/remote_controller.dart';
import '../../theme/app_theme.dart';
import 'devices_button.dart';

/// What the strip says about [link].
String remoteStripText(RemoteLink link) {
  final name = link.device.name;
  return switch (link.status) {
    RemoteLinkStatus.connecting => 'Connecting to $name…',
    RemoteLinkStatus.connected => 'Playing on $name',
    RemoteLinkStatus.lost => 'Lost connection to $name',
  };
}

/// Tells which device is being controlled; nothing on This device. Tapping
/// it opens the device picker.
class RemoteStrip extends ConsumerWidget {
  const RemoteStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(remoteLinkProvider).value;
    if (link == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      color: colors.accent.withAlpha(36),
      child: InkWell(
        key: const Key('remote.strip'),
        onTap: () => showDevicesPicker(context, ref),
        child: Container(
          width: double.infinity,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices_rounded, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  remoteStripText(link),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
