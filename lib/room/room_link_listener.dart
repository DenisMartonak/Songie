import 'dart:async';

import 'room_links.dart';

/// Turns opened links into room codes: every link [parseRoomCode] accepts
/// calls [onCode]; others are ignored. The same code twice within 2 s counts
/// once (a link can arrive both as the initial link and as a stream event).
class RoomLinkListener {
  RoomLinkListener(Stream<Uri> links, this.onCode) {
    _sub = links.listen(_onLink);
  }

  final void Function(String code) onCode;
  late final StreamSubscription<Uri> _sub;
  String? _lastCode;
  Timer? _window;

  void _onLink(Uri uri) {
    final code = parseRoomCode(uri.toString());
    if (code == null || code == _lastCode) return;
    _lastCode = code;
    _window?.cancel();
    _window = Timer(const Duration(seconds: 2), () => _lastCode = null);
    onCode(code);
  }

  Future<void> dispose() {
    _window?.cancel();
    return _sub.cancel();
  }
}
