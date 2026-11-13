import 'dart:async';

import '../room/room_links.dart' show kRoomSiteBase;

/// Shared playlists' links: `<site>/p/<code>` on the website (website/404.html
/// hands it to the app as `songies://playlist/<code>`). Codes are 12 letters
/// from the room codes' alphabet.
const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const int kPlaylistCodeLength = 12;

/// The link that opens the shared playlist [code].
String playlistLink(String code) => '$kRoomSiteBase/p/$code';

String? _code(String s) {
  final c = s.trim().toUpperCase();
  if (c.length != kPlaylistCodeLength) return null;
  for (final r in c.runes) {
    if (!_alphabet.contains(String.fromCharCode(r))) return null;
  }
  return c;
}

/// The playlist code in a link or typed text, or null. Room links (`/r/`,
/// `songies://room`) are not playlist links.
String? parsePlaylistCode(String input) {
  final t = input.trim();
  final uri = Uri.tryParse(t);
  if (uri != null && uri.hasScheme) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme == 'songies') {
      if (uri.host == 'playlist' && segs.length == 1) return _code(segs[0]);
      return null;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        segs.length >= 2 &&
        segs[segs.length - 2] == 'p') {
      return _code(segs.last);
    }
    return null;
  }
  return _code(t);
}

/// Turns opened links into playlist codes, like `RoomLinkListener`: the same
/// code twice within 2 s counts once.
class PlaylistLinkListener {
  PlaylistLinkListener(Stream<Uri> links, this.onCode) {
    _sub = links.listen(_onLink);
  }

  final void Function(String code) onCode;
  late final StreamSubscription<Uri> _sub;
  String? _lastCode;
  Timer? _window;

  void _onLink(Uri uri) {
    final code = parsePlaylistCode(uri.toString());
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
