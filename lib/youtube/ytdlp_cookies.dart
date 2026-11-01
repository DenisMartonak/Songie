import '../innertube/yt_session.dart';

/// The YouTube session yt-dlp runs signed in with, plus the arguments that
/// give it a JavaScript runtime (age-restricted videos need both).
class YtDlpAuth {
  const YtDlpAuth(this.session, this.runtimeArgs);

  final YtSession session;
  final List<String> runtimeArgs;
}

/// [session] as a Netscape cookies file for `yt-dlp --cookies`. The session
/// keeps only youtube.com name→value pairs (R8), so every line is for
/// `.youtube.com`, path `/`, secure, expiring a year from [now].
///
/// Throws [FormatException] (naming neither the cookie nor its value) for a
/// cookie that can't go in a header.
String netscapeCookies(YtSession session, DateTime now) {
  final expiry =
      now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000;
  final b = StringBuffer('# Netscape HTTP Cookie File\n');
  for (final e in session.cookies.entries) {
    if (!YtSession.validName(e.key) || !YtSession.validValue(e.value)) {
      throw const FormatException('invalid session cookie');
    }
    b.write('.youtube.com\tTRUE\t/\tTRUE\t$expiry\t${e.key}\t${e.value}\n');
  }
  return b.toString();
}
