import 'dart:async';

/// Puts back the volume saved by [rememberVolume] (from [read], the stored
/// text). Nothing saved, or something unreadable, leaves the volume alone.
Future<void> restoreVolume({
  required Future<String?> Function() read,
  required Future<void> Function(double volume) apply,
}) async {
  final v = double.tryParse(await read() ?? '');
  if (v == null || v.isNaN) return;
  await apply(v.clamp(0.0, 1.0));
}

/// Saves the volume as it changes, so the next start can restore it. A drag
/// on the slider sends many values; only the one it settles on is written,
/// once [quiet] has passed without a change. Any change counts: the slider,
/// remote control, or a Listen together guest's own volume.
StreamSubscription<double> rememberVolume(
  Stream<double> volumes, {
  required Future<void> Function(String volume) write,
  Duration quiet = const Duration(milliseconds: 300),
}) {
  Timer? timer;
  String? saved;
  return volumes.listen((v) {
    timer?.cancel();
    timer = Timer(quiet, () {
      final text = v.toStringAsFixed(3);
      if (text == saved) return;
      saved = text;
      unawaited(write(text));
    });
  }, onDone: () => timer?.cancel());
}
