const _hosts = {
  'music.youtube.com',
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
};

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Canonical `https://music.youtube.com/playlist?list=<id>` or null.
String? parsePlaylistLink(String input) {
  var s = input.trim();
  if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!_hosts.contains(uri.host.toLowerCase())) return null;
  final id = uri.queryParameters['list'];
  if (id == null || !_idPattern.hasMatch(id)) return null;
  // `RD…` ids are radio/mix lists generated per listener, not playlists;
  // `RDCLAK…` are YouTube Music's curated (static) playlists and do import.
  if (id.startsWith('RD') && !id.startsWith('RDCLAK')) return null;
  return 'https://music.youtube.com/playlist?list=$id';
}

/// Finds the first URL-ish token in [text] that is a playlist link.
String? extractLinkFromSharedText(String text) {
  final matches = RegExp(r'(?:https?://)?[^\s]*youtu[^\s]*').allMatches(text);
  for (final m in matches) {
    final link = parsePlaylistLink(m.group(0)!);
    if (link != null) return link;
  }
  return null;
}
