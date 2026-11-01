/// Lets the player ask the user to install yt-dlp's JavaScript runtime. The
/// desktop shell sets [handler] (a dialog); without one the answer is no.
class RuntimePrompter {
  /// Shows the question and installs; true once a runtime is installed.
  Future<bool> Function()? handler;

  Future<bool>? _open;

  /// Asks, unless the question is already open: then waits for that answer.
  Future<bool> ask() {
    final h = handler;
    if (h == null) return Future.value(false);
    return _open ??= h().whenComplete(() => _open = null);
  }
}
