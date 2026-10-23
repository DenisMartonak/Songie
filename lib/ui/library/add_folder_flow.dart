import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../library/library_scanner.dart';
import '../../providers.dart';
import '../widgets/name_dialog.dart';
import '../widgets/page_snack_bar.dart';
import 'pickers.dart';

/// The "add a music folder" flow shared by Your Library and Settings: ask for
/// media access, pick a folder, ask whether to also create a playlist from it,
/// then scan it through the scan queue with a progress snack bar.
Future<void> addMusicFolder(BuildContext context, WidgetRef ref) async {
  final snacks = PageSnackBars.of(context);
  final requestAccess = ref.read(mediaAccessProvider);
  final pickFolder = ref.read(folderPickerProvider);
  final queue = ref.read(scanQueueProvider);

  final access = await requestAccess();
  if (!context.mounted) return;
  if (!access) {
    await _explainPermission(context);
    return;
  }
  final pick = await pickFolder();
  if (!context.mounted) return;
  final path = switch (pick) {
    FolderPicked(:final path) => path,
    FolderPickCancelled() => null,
    FolderPickFailed(:final error) => () {
      snacks.show(content: Text(folderPickFailureMessage(error)));
      return null;
    }(),
  };
  if (path == null) return;

  final name = folderDisplayName(path);
  final createPlaylist = await showDialog<bool>(
    context: context,
    builder: (_) => _AddFolderDialog(path: path, folderName: name),
  );
  if (createPlaylist == null) return;

  final progress = snacks.show(
    content: _ScanProgressText(folderName: name),
    duration: const Duration(days: 1),
  );
  try {
    final result = await queue.enqueue(
      path,
      createPlaylistNamed: createPlaylist ? _playlistNameFor(name) : null,
    );
    progress.close();
    snacks.show(content: Text(_summary(result, name)));
  } catch (_) {
    // ScanQueue has already logged the details.
    progress.close();
    snacks.show(content: Text("Couldn't scan $name"));
  }
}

/// What to tell the user when the folder picker could not open.
String folderPickFailureMessage(FolderPickError error) => switch (error) {
  FolderPickError.unsupportedLocation =>
    "That folder can't be used — pick one under Internal storage or the SD "
        'card (not Downloads or a cloud folder)',
  FolderPickError.noFileManager => 'No file manager found to pick a folder',
  FolderPickError.busy => 'The folder picker is already open',
  FolderPickError.unknown => "Couldn't open the folder picker",
};

/// The last segment of a folder path (the path itself for a root).
String folderDisplayName(String path) {
  final name = p.basename(path);
  return name.isEmpty ? path : name;
}

Future<void> _explainPermission(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow access to your music'),
      content: const Text(
        'Songies needs permission to read the music files on this device. '
        'Allow it in the app settings, then add the folder again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            openMediaSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
}

/// The repository rejects names over 100 characters.
String _playlistNameFor(String folderName) =>
    folderName.length > maxPlaylistNameLength
    ? folderName.substring(0, maxPlaylistNameLength)
    : folderName;

String _summary(ScanProgress? result, String folderName) {
  if (result == null) return 'Scanned $folderName';
  final songs = result.added == 1 ? '1 song' : '${result.added} songs';
  final skipped = result.skipped > 0 ? ' · ${result.skipped} skipped' : '';
  if (result.found == 0) return 'No MP3 files in $folderName';
  if (result.added == 0) {
    return 'No new songs in $folderName$skipped';
  }
  return 'Added $songs from $folderName$skipped';
}

class _AddFolderDialog extends StatefulWidget {
  const _AddFolderDialog({required this.path, required this.folderName});

  final String path;
  final String folderName;

  @override
  State<_AddFolderDialog> createState() => _AddFolderDialogState();
}

class _AddFolderDialogState extends State<_AddFolderDialog> {
  bool _createPlaylist = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add music folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.path, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _createPlaylist,
            onChanged: (on) => setState(() => _createPlaylist = on ?? false),
            title: Text("Also create playlist '${widget.folderName}'"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_createPlaylist),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// The body of the "scanning" snack bar; follows the scan queue.
class _ScanProgressText extends ConsumerWidget {
  const _ScanProgressText({required this.folderName});

  final String folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scanProgressProvider).value;
    final found = progress?.found ?? 0;
    final text = found == 0
        ? 'Looking for music in $folderName…'
        : 'Scanning $folderName · ${progress!.processed} of $found';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: found == 0 ? null : progress!.processed / found,
        ),
      ],
    );
  }
}
