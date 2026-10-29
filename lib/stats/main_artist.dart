/// Separators for local songs: a comma, `;`, ` / `, and the "featuring"
/// words, bracketed or not. Never `&`, `+` or ` x `.
final _localSeparator = RegExp(
  r'\s*[(\[]\s*(?:feat\.?|ft\.?|featuring)\s'
  r'|,|;|\s/\s|\s(?:feat\.?|ft\.?|featuring)\s',
  caseSensitive: false,
);

/// The artist a listen is credited to: the text before the first separator,
/// trimmed. YouTube artists split on `", "` only. A band name with a comma
/// ("Earth, Wind & Fire") is cut at it; that trade-off is accepted.
String mainArtist(String artist, {required bool youtube}) {
  final cut = youtube
      ? artist.indexOf(', ')
      : _localSeparator.firstMatch(artist)?.start ?? -1;
  return (cut < 0 ? artist : artist.substring(0, cut)).trim();
}
