/// A signed-in YouTube session: the Google cookies, kept only in secure
/// storage. Never logged: [toString] shows the count, not the values.
class YtSession {
  YtSession(Map<String, String> cookies) : cookies = Map.unmodifiable(cookies);

  final Map<String, String> cookies;

  String? get sapisid => cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];

  String cookieHeader() =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Map<String, Object?> toJson() => {'cookies': Map<String, String>.of(cookies)};

  factory YtSession.fromJson(Map<String, Object?> json) {
    final raw = json['cookies'];
    if (raw is! Map) throw const FormatException('bad session');
    return YtSession({
      for (final e in raw.entries) e.key.toString(): e.value.toString(),
    });
  }

  @override
  String toString() => 'YtSession(${cookies.length} cookies)';
}
