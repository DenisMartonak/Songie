import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// File logger: `<logsDir>/songies.log`, rotated to `songies.log.1` before it
/// would exceed [maxBytes]. Lines are buffered in memory and written
/// synchronously; there are no timers (warnings and errors flush immediately).
class AppLog {
  AppLog._();

  static const int maxBytes = 2097152;
  static const int _bufferLimit = 16 * 1024;

  static File? _file;
  static File? _rotated;
  static int _size = 0;
  static final StringBuffer _buffer = StringBuffer();

  static Future<void> init(Directory logsDir) async {
    await flush();
    logsDir.createSync(recursive: true);
    final file = File('${logsDir.path}/songies.log');
    _rotated = File('${logsDir.path}/songies.log.1');
    _file = file;
    _size = file.existsSync() ? file.lengthSync() : 0;
  }

  static Future<void> flush() async {
    final file = _file;
    if (file == null || _buffer.isEmpty) return;
    final bytes = utf8.encode(_buffer.toString());
    _buffer.clear();
    try {
      if (_size > 0 && _size + bytes.length > maxBytes) {
        final rotated = _rotated!;
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
        _size = 0;
      }
      file.writeAsBytesSync(bytes, mode: FileMode.append);
      _size += bytes.length;
    } on FileSystemException catch (e) {
      debugPrint('AppLog write failed: $e');
    }
  }

  static void i(String m) => _log('I', m);

  static void w(String m, [Object? e, StackTrace? s]) => _log('W', m, e, s);

  static void e(String m, [Object? e, StackTrace? s]) => _log('E', m, e, s);

  static void _log(String level, String m, [Object? err, StackTrace? st]) {
    final line = StringBuffer('${DateTime.now().toIso8601String()} $level $m');
    if (err != null) line.write(' | $err');
    if (st != null) line.write('\n$st');
    line.write('\n');
    if (_file == null) {
      debugPrint(line.toString().trimRight());
      return;
    }
    _buffer.write(line);
    if (level != 'I' || _buffer.length >= _bufferLimit) {
      // Synchronous part of flush() runs before its first await.
      flush();
    }
  }
}

/// Sends uncaught errors to the log file, keeping the default presentation.
/// Install before crash reporting, which hands errors on to these handlers.
void installErrorLogging() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.e(
      'Flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('Uncaught error', error, stack);
    return false;
  };
}

/// The rotated log followed by the current one; null when both are empty or
/// missing. Small (at most 2 MB each), so read in one go.
Uint8List? readLogFiles(Directory logs) {
  final builder = BytesBuilder(copy: false);
  for (final name in ['songies.log.1', 'songies.log']) {
    final file = File('${logs.path}/$name');
    if (file.existsSync()) builder.add(file.readAsBytesSync());
  }
  return builder.isEmpty ? null : builder.takeBytes();
}
