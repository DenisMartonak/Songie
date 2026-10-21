import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paths.dart';
import '../../providers.dart';

/// How much disk the app's own data takes.
class StorageUsage {
  const StorageUsage({required this.artBytes, required this.databaseBytes});

  /// Everything under `art/`.
  final int artBytes;

  /// The database file plus its `-wal` and `-shm` side files.
  final int databaseBytes;
}

/// Measured when Settings opens (no timers); leaving the page discards it, so
/// opening it again measures again.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>(
  (ref) => measureStorage(ref.watch(appPathsProvider)),
);

Future<StorageUsage> measureStorage(AppPaths paths) async {
  final db = paths.db.path;
  var databaseBytes = 0;
  for (final path in [db, '$db-wal', '$db-shm']) {
    databaseBytes += await _fileSize(File(path));
  }
  return StorageUsage(
    artBytes: await _directorySize(paths.art),
    databaseBytes: databaseBytes,
  );
}

Future<int> _fileSize(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return 0; // Not there (yet), or gone while measuring.
  }
}

Future<int> _directorySize(Directory dir) async {
  var total = 0;
  try {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await _fileSize(entity);
    }
  } on FileSystemException {
    // The directory does not exist (yet) or vanished while listing.
  }
  return total;
}

/// "512 B", "2.0 KB", "12.3 MB", "3.0 GB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
