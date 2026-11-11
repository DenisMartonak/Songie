/// The website that serves `/r/<code>` links (website/404.html), which
/// hands the code to the app as `songies://room/<code>`.
const String kRoomSiteBase = 'https://denismartonak.github.io/Songie';

const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// `ABCD2345` shown as `ABCD-2345`.
String formatRoomCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// The link that opens the room [code].
String roomLink(String code) =>
    kRoomSiteBase.isEmpty ? 'songies://room/$code' : '$kRoomSiteBase/r/$code';

String? _code(String s) {
  final c = s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (c.length != 8) return null;
  for (final r in c.runes) {
    if (!_alphabet.contains(String.fromCharCode(r))) return null;
  }
  return c;
}

/// The room code in a link or typed text, or null.
String? parseRoomCode(String input) {
  final t = input.trim();
  final uri = Uri.tryParse(t);
  if (uri != null && uri.hasScheme) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme == 'songies') {
      if (uri.host == 'room' && segs.length == 1) return _code(segs[0]);
      return null;
    }
    // Any site address ending in `/r/<code>`, e.g. `<kRoomSiteBase>/r/<code>`.
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        segs.length >= 2 &&
        segs[segs.length - 2] == 'r') {
      return _code(segs.last);
    }
    return null;
  }
  return _code(t);
}
