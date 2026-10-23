import 'package:flutter/services.dart';

import '../../core/log.dart';

/// What a folder picker answered.
sealed class FolderPick {
  const FolderPick();
}

class FolderPicked extends FolderPick {
  const FolderPicked(this.path);
  final String path;
}

class FolderPickCancelled extends FolderPick {
  const FolderPickCancelled();
}

class FolderPickFailed extends FolderPick {
  const FolderPickFailed(this.error, [this.detail]);
  final FolderPickError error;
  final String? detail;
}

enum FolderPickError { unsupportedLocation, noFileManager, busy, unknown }

const _channel = MethodChannel('songies/folder_picker');

/// Android: the system folder picker through our own channel, which says why
/// it failed (file_picker swallows every error as "cancelled").
Future<FolderPick> pickFolderOnAndroid() async {
  FolderPick pick;
  try {
    final result = await _channel.invokeMapMethod<String, Object?>('pick');
    final path = result?['path'];
    if (path is String) {
      pick = FolderPicked(path);
    } else if (result?['cancelled'] == true) {
      pick = const FolderPickCancelled();
    } else {
      pick = const FolderPickFailed(FolderPickError.unknown, 'bad reply');
    }
  } on PlatformException catch (e) {
    pick = FolderPickFailed(switch (e.code) {
      'unsupported_location' => FolderPickError.unsupportedLocation,
      'no_file_manager' => FolderPickError.noFileManager,
      'busy' => FolderPickError.busy,
      _ => FolderPickError.unknown,
    }, e.message);
  } on MissingPluginException {
    pick = const FolderPickFailed(FolderPickError.unknown, 'no plugin');
  }
  AppLog.i(switch (pick) {
    FolderPicked() => 'Folder pick: picked',
    FolderPickCancelled() => 'Folder pick: cancelled',
    FolderPickFailed(:final error, :final detail) =>
      'Folder pick: failed ${error.name}${detail == null ? '' : ' ($detail)'}',
  });
  return pick;
}
