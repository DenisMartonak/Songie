import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database.dart';

/// What a message is about; it picks the island's icon.
enum IslandKind { success, failure, info }

/// A button on the island, such as Undo.
class IslandAction {
  const IslandAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// One thing to tell the user. When [song] is set, its artwork is shown
/// instead of the kind's icon.
class IslandMessage {
  const IslandMessage({
    required this.text,
    this.kind = IslandKind.info,
    this.song,
    this.action,
    this.duration = defaultDuration,
  });

  static const Duration defaultDuration = Duration(seconds: 4);

  final String text;
  final IslandKind kind;
  final Track? song;
  final IslandAction? action;
  final Duration duration;
}

/// Holds the message the island shows and when it goes away. A new message
/// replaces the current one; there is no queue.
class IslandController extends ChangeNotifier {
  IslandMessage? _current;
  int _serial = 0;
  Timer? _timer;

  /// The message on show, or null when the island is hidden.
  IslandMessage? get current => _current;

  /// Bumps on every [show], so the view can tell a replacement from a
  /// rebuild.
  int get serial => _serial;

  /// Shows [m], replacing any message and restarting the timer. Returns the
  /// new [serial], which [update] takes.
  int show(IslandMessage m) {
    _current = m;
    _serial++;
    _startTimer(m.duration);
    notifyListeners();
    return _serial;
  }

  /// Swaps the message shown since [show] returned [serial] for [m] in
  /// place, without the cross-fade or a new timer. Returns false, changing
  /// nothing, when that message is no longer on show.
  bool update(int serial, IslandMessage m) {
    if (serial != _serial || _current == null) return false;
    _current = m;
    notifyListeners();
    return true;
  }

  /// Hides the island.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Keeps the message up while the user is touching it.
  void pause() => _timer?.cancel();

  /// Starts the full duration again after a [pause].
  void resume() {
    final m = _current;
    if (m != null) _startTimer(m.duration);
  }

  /// Runs the current action, then hides the island, unless the action
  /// showed a new message (an Undo that confirms itself, say).
  void runAction() {
    final serial = _serial;
    _current?.action?.onPressed();
    if (_serial == serial) dismiss();
  }

  void _startTimer(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
