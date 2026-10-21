import 'dart:ui';

/// The user-editable description of the app's look (spec §9). Immutable, with
/// value equality, and serialised to the `themes.spec_json` shape.
class ThemeSpec {
  const ThemeSpec({
    required this.base,
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.followCover,
    required this.glowStrength,
    required this.cornerRadius,
    required this.fontFamily,
    required this.fontFileHash,
    required this.fontScale,
    required this.blurNowPlaying,
  });

  /// The built-in Default theme.
  static const ThemeSpec builtInDefault = ThemeSpec(
    base: 'charcoal',
    background: Color(0xFF121212),
    surface: Color(0xFF2A2A2A),
    text: Color(0xFFFFFFFF),
    mutedText: Color(0xFFA7A7A7),
    accent: Color(0xFF1DB954),
    followCover: false,
    glowStrength: 0.4,
    cornerRadius: 6,
    fontFamily: 'Inter',
    fontFileHash: null,
    fontScale: 1.0,
    blurNowPlaying: true,
  );

  final String base;
  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color accent;
  final bool followCover;
  final double glowStrength;
  final double cornerRadius;
  final String fontFamily;
  final String? fontFileHash;
  final double fontScale;
  final bool blurNowPlaying;

  /// Throws [FormatException] when a required key is missing or has the wrong
  /// type or format. `fontFileHash` may be absent or null.
  factory ThemeSpec.fromJson(Map<String, dynamic> json) {
    T req<T>(String key) {
      final v = json[key];
      if (v is T) return v;
      throw FormatException(
        v == null
            ? 'Missing theme key "$key"'
            : 'Theme key "$key" must be a $T',
        json,
      );
    }

    double number(String key) => req<num>(key).toDouble();

    Color color(String key) => _parseColor(key, req<String>(key));

    final hash = json['fontFileHash'];
    if (hash != null && hash is! String) {
      throw FormatException('Theme key "fontFileHash" must be a String', json);
    }

    return ThemeSpec(
      base: req<String>('base'),
      background: color('background'),
      surface: color('surface'),
      text: color('text'),
      mutedText: color('mutedText'),
      accent: color('accent'),
      followCover: req<bool>('followCover'),
      glowStrength: number('glowStrength'),
      cornerRadius: number('cornerRadius'),
      fontFamily: req<String>('fontFamily'),
      fontFileHash: hash as String?,
      fontScale: number('fontScale'),
      blurNowPlaying: req<bool>('blurNowPlaying'),
    );
  }

  Map<String, dynamic> toJson() => {
    'base': base,
    'background': _formatColor(background),
    'surface': _formatColor(surface),
    'text': _formatColor(text),
    'mutedText': _formatColor(mutedText),
    'accent': _formatColor(accent),
    'followCover': followCover,
    'glowStrength': glowStrength,
    'cornerRadius': cornerRadius,
    'fontFamily': fontFamily,
    'fontFileHash': fontFileHash,
    'fontScale': fontScale,
    'blurNowPlaying': blurNowPlaying,
  };

  ThemeSpec copyWith({
    String? base,
    Color? background,
    Color? surface,
    Color? text,
    Color? mutedText,
    Color? accent,
    bool? followCover,
    double? glowStrength,
    double? cornerRadius,
    String? fontFamily,
    String? fontFileHash,
    double? fontScale,
    bool? blurNowPlaying,
  }) => ThemeSpec(
    base: base ?? this.base,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    mutedText: mutedText ?? this.mutedText,
    accent: accent ?? this.accent,
    followCover: followCover ?? this.followCover,
    glowStrength: glowStrength ?? this.glowStrength,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFileHash: fontFileHash ?? this.fontFileHash,
    fontScale: fontScale ?? this.fontScale,
    blurNowPlaying: blurNowPlaying ?? this.blurNowPlaying,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSpec &&
      other.base == base &&
      other.background == background &&
      other.surface == surface &&
      other.text == text &&
      other.mutedText == mutedText &&
      other.accent == accent &&
      other.followCover == followCover &&
      other.glowStrength == glowStrength &&
      other.cornerRadius == cornerRadius &&
      other.fontFamily == fontFamily &&
      other.fontFileHash == fontFileHash &&
      other.fontScale == fontScale &&
      other.blurNowPlaying == blurNowPlaying;

  @override
  int get hashCode => Object.hash(
    base,
    background,
    surface,
    text,
    mutedText,
    accent,
    followCover,
    glowStrength,
    cornerRadius,
    fontFamily,
    fontFileHash,
    fontScale,
    blurNowPlaying,
  );
}

/// `#rrggbb`, or `#aarrggbb` when the colour is not fully opaque.
String _formatColor(Color c) {
  final v = c.toARGB32();
  final hex = v.toRadixString(16).padLeft(8, '0');
  return (v >>> 24) == 0xFF ? '#${hex.substring(2)}' : '#$hex';
}

final RegExp _colorPattern = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

Color _parseColor(String key, String s) {
  if (!_colorPattern.hasMatch(s)) {
    throw FormatException('Theme key "$key" is not a #rrggbb colour', s);
  }
  final digits = s.substring(1);
  final value = int.parse(digits, radix: 16);
  return Color(digits.length == 6 ? 0xFF000000 | value : value);
}
