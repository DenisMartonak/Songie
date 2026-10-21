import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Asks the user for a music folder; null when cancelled.
typedef FolderPicker = Future<String?> Function();

/// Asks the user for one MP3 file; null when cancelled.
typedef AudioFilePicker = Future<String?> Function();

/// Makes sure the app may read music files; false when the user refused.
typedef MediaAccessRequest = Future<bool> Function();

/// The pickers and the permission prompt are providers so tests can replace
/// the native dialogs.
final folderPickerProvider = Provider<FolderPicker>(
  (ref) =>
      () => FilePicker.getDirectoryPath(dialogTitle: 'Choose a music folder'),
);

final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Locate the audio file',
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );
    return file?.path;
  },
);

final mediaAccessProvider = Provider<MediaAccessRequest>(
  (ref) => requestMediaAccess,
);

/// Android needs `READ_MEDIA_AUDIO` (API 33+) or `READ_EXTERNAL_STORAGE`
/// (API 32 and below) to read files in place. The permission that does not
/// apply to this Android version is never granted, so either one is enough.
/// Other platforms need no permission.
Future<bool> requestMediaAccess() async {
  if (!Platform.isAndroid) return true;
  final audio = await Permission.audio.request();
  if (audio.isGranted) return true;
  final storage = await Permission.storage.request();
  return storage.isGranted;
}

/// Opens the system settings page of this app (to grant a refused permission).
Future<void> openMediaSettings() => openAppSettings();
