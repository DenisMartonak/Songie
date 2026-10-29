/// A signed-in YouTube session: the cookies a browser sends to
/// music.youtube.com (R8), kept only in secure storage. Never logged:
/// [toString] shows the count, not the values.
class YtSession {
  YtSession(Map<String, String> cookies) : cookies = Map.unmodifiable(cookies);

  /// Whether [name] can be a cookie name in a `Cookie` header: non-empty
  /// RFC 6265 cookie-octets without `=`.
  static bool validName(String name) =>
      name.isNotEmpty && _isCookieOctets(name) && !name.contains('=');

  /// Whether [value] can be a cookie value in a `Cookie` header: RFC 6265
  /// cookie-octets, optionally wrapped in DQUOTEs.
  static bool validValue(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return _isCookieOctets(value.substring(1, value.length - 1));
    }
    return _isCookieOctets(value);
  }

  static bool _isCookieOctets(String s) => s.codeUnits.every(
    (u) =>
        u >= 0x21 &&
        u <= 0x7E &&
        u != 0x22 &&
        u != 0x2C &&
        u != 0x3B &&
        u != 0x5C,
  );

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
