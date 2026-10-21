import 'dart:async';

import 'package:window_manager/window_manager.dart';

/// The native window's title-bar actions, behind an interface so widget tests
/// never reach the platform plugin.
abstract class WindowControls {
  Future<void> minimize();
  Future<void> maximizeOrRestore();
  Future<void> close();
  Future<bool> isMaximized();

  /// Emits `true` when the window is maximized and `false` when restored.
  Stream<bool> get maximizedChanges;
}

/// [WindowControls] over `window_manager`.
class WindowManagerControls with WindowListener implements WindowControls {
  WindowManagerControls();

  late final StreamController<bool> _changes = StreamController<bool>.broadcast(
    onListen: () => windowManager.addListener(this),
    onCancel: () => windowManager.removeListener(this),
  );

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximizeOrRestore() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Stream<bool> get maximizedChanges => _changes.stream;

  @override
  void onWindowMaximize() => _changes.add(true);

  @override
  void onWindowUnmaximize() => _changes.add(false);
}
