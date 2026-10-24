import 'dart:ui';

/// The user-editable description of the app's look (spec §9). Immutable, with
/// value equality, and serialised to the `themes.spec_json` shape.
class ThemeSpec {
  const ThemeSpec({
    required this.base,
    required this.background,
    required this.surface,
    required this.text,
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
    accent: Color(0xFF1DB954),
    followCover: false,
    glowStrength: 0.4,
    cornerRadius: 6,
    fontFamily: 'Inter',
    fontFileHash: null,
    fontScale: 1.0,
    blurNowPlaying: true,
  );

  /// The built-in Album glow theme: Default's charcoal base, Outfit, rounder
  /// corners, and an accent that follows the cover (green is the fallback).
  static const ThemeSpec albumGlow = ThemeSpec(
    base: 'charcoal',
    background: Color(0xFF121212),
    surface: Color(0xFF2A2A2A),
    text: Color(0xFFFFFFFF),
    accent: Color(0xFF1DB954),
    followCover: true,
    glowStrength: 0.65,
    cornerRadius: 12,
    fontFamily: 'Outfit',
    fontFileHash: null,
    fontScale: 1.0,
    blurNowPlaying: true,
  );

  /// The built-in Terminal theme: pure black, cyan, square, monospace.
  static const ThemeSpec terminal = ThemeSpec(
    base: 'black',
    background: Color(0xFF000000),
    surface: Color(0xFF141414),
    text: Color(0xFFFFFFFF),
    accent: Color(0xFF00E5FF),
    followCover: false,
    glowStrength: 0.4,
    cornerRadius: 0,
    fontFamily: 'JetBrains Mono',
    fontFileHash: null,
    fontScale: 1.0,
    blurNowPlaying: true,
  );

  final String base;
  final Color background;
  final Color surface;
  final Color text;

  /// Secondary text: [text] mixed a little over a third of the way towards
  /// [background] (#a7a7a7 for white on charcoal). Derived, never stored.
  Color get mutedText => Color.lerp(text, background, mutedTextMix)!;
  final Color accent;
  final bool followCover;
  final double glowStrength;
  final double cornerRadius;
  final String fontFamily;
  final String? fontFileHash;
  final double fontScale;
  final bool blurNowPlaying;

  /// The allowed `glowStrength`, `cornerRadius` and `fontScale`, inclusive.
  static const (double, double) glowRange = (0, 1);
  static const (double, double) cornerRadiusRange = (0, 24);
  static const (double, double) fontScaleRange = (0.85, 1.3);

  /// Throws [FormatException] when a required key is missing or has the wrong
  /// type or format. `fontFileHash` may be absent or null. A `mutedText` key
  /// (written by older versions) is ignored. Numbers outside their range are
  /// clamped into it and every colour is made fully opaque, so a stored or
  /// synced row can never make the app transparent or its text huge.
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

    double clamp(double v, (double, double) range) =>
        v.isNaN ? range.$1 : v.clamp(range.$1, range.$2);

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
      accent: color('accent'),
      followCover: req<bool>('followCover'),
      glowStrength: clamp(number('glowStrength'), glowRange),
      cornerRadius: clamp(number('cornerRadius'), cornerRadiusRange),
      fontFamily: req<String>('fontFamily'),
      fontFileHash: hash as String?,
      fontScale: clamp(number('fontScale'), fontScaleRange),
      blurNowPlaying: req<bool>('blurNowPlaying'),
    );
  }

  Map<String, dynamic> toJson() => {
    'base': base,
    'background': _formatColor(background),
    'surface': _formatColor(surface),
    'text': _formatColor(text),
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

/// How far muted text mixes from the text towards the background. White on
/// #121212 mixes to exactly #a7a7a7: 255 - 88 = 167.
const double mutedTextMix = 88 / 237;

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
  // An 8-digit colour's alpha is dropped: theme colours are always opaque.
  return Color(0xFF000000 | int.parse(s.substring(1), radix: 16) & 0xFFFFFF);
}
