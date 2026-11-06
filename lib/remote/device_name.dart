import '../bug_report/bug_report.dart' show DeviceSummary;
import '../core/log.dart';

/// The name other devices see for this one: the `kDeviceName` setting when
/// one is set (left from the old home-network sync), else the Android model,
/// else the desktop's hostname. Never throws.
Future<String> remoteDeviceName({
  required Future<String?> Function() storedName,
  required bool isAndroid,
  required Future<DeviceSummary> Function() readDevice,
  required String hostname,
}) async {
  try {
    final stored = (await storedName())?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
  } on Object catch (e, s) {
    AppLog.w('remote: reading the device name setting failed', e, s);
  }
  if (isAndroid) {
    try {
      final model = (await readDevice()).model.trim();
      if (model.isNotEmpty && model != 'unknown') return model;
    } on Object catch (e, s) {
      AppLog.w('remote: reading the device model failed', e, s);
    }
    return 'Android';
  }
  final host = hostname.trim();
  return host.isEmpty ? 'Computer' : host;
}
