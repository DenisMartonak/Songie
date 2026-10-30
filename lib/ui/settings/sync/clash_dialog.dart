import 'package:flutter/material.dart';

import '../../../sync/merger.dart';

/// The question for one playlist both devices changed: keep this device's,
/// keep [peerName]'s, or (unless [PlaylistClash.theirsDeleted]) keep both.
/// The route ends with null when dismissed; the caller may remove it (when
/// it leaves) and gets null then too.
DialogRoute<Resolution> clashDialogRoute(
  BuildContext context,
  PlaylistClash clash,
  String peerName,
) => DialogRoute<Resolution>(
  context: context,
  builder: (_) => ClashDialog(clash: clash, peerName: peerName),
);

class ClashDialog extends StatelessWidget {
  const ClashDialog({required this.clash, required this.peerName, super.key});

  final PlaylistClash clash;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final what = clash.mineDeleted
        ? 'Deleted on this device, changed on $peerName'
        : clash.theirsDeleted
        ? 'Deleted on $peerName, changed on this device'
        : 'Changed on both devices';
    void pick(Resolution r) => Navigator.of(context).pop(r);
    return AlertDialog(
      title: Text(clash.name ?? 'A playlist'),
      content: Text(what),
      actions: [
        TextButton(
          key: const Key('sync.clash.mine'),
          onPressed: () => pick(Resolution.keepMine),
          child: const Text("Keep this device's"),
        ),
        TextButton(
          key: const Key('sync.clash.theirs'),
          onPressed: () => pick(Resolution.keepTheirs),
          child: Text("Keep $peerName's"),
        ),
        if (!clash.theirsDeleted)
          TextButton(
            key: const Key('sync.clash.both'),
            onPressed: () => pick(Resolution.keepBoth),
            child: const Text('Keep both'),
          ),
      ],
    );
  }
}
