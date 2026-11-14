import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/avatar_image.dart' show ImageTooBigException;
import '../../core/log.dart';

/// A picked picture's size and bytes; [bytes] is null when the file is over
/// [maxAvatarSourceBytes]: it is not read.
typedef AvatarPick = ({int size, Uint8List? bytes});

/// The biggest image file accepted as a picture (before shrinking).
const int maxAvatarSourceBytes = 10 * 1024 * 1024;

/// Asks the user for an image; null when cancelled. A provider so tests can
/// replace the native dialog.
final avatarPickerProvider = Provider<Future<AvatarPick?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a picture',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = file?.path;
    if (path == null) return null;
    final f = File(path);
    final size = await f.length();
    return (
      size: size,
      bytes: size > maxAvatarSourceBytes ? null : await f.readAsBytes(),
    );
  },
);

/// What to tell the user when an account action failed with [e]; an
/// unexpected failure is logged.
String accountActionError(Object e) {
  switch (e) {
    case AccountException(:final error):
      return error.message;
    case ImageTooBigException():
      return 'That image is too big';
    case FormatException():
      return "Couldn't read that image";
    default:
      AppLog.w('Account action failed: ${e.runtimeType}');
      return AccountError.unknown.message;
  }
}
