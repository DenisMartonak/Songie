import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../motion/motion.dart';

/// `RRGGBB` for an opaque [c].
String hexOf(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// The opaque colour for six hex digits, or null.
Color? parseHex(String s) {
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}

/// One theme colour: a row with its swatch and hex that expands into
/// [presets] (eight), a hue / saturation / value picker and a hex field.
/// Every change is reported through [onChanged] at once.
class ColourField extends StatefulWidget {
  const ColourField({
    required this.label,
    required this.value,
    required this.presets,
    required this.onChanged,
    this.headerKey,
    super.key,
  });

  final String label;
  final Color value;
  final List<Color> presets;
  final ValueChanged<Color> onChanged;

  /// Key of the tappable header row (tests).
  final Key? headerKey;

  @override
  State<ColourField> createState() => _ColourFieldState();
}

class _ColourFieldState extends State<ColourField> {
  bool _expanded = false;
  late HSVColor _hsv = HSVColor.fromColor(widget.value);
  late final TextEditingController _hex = TextEditingController(
    text: hexOf(widget.value),
  );

  @override
  void didUpdateWidget(ColourField old) {
    super.didUpdateWidget(old);
    if (widget.value.toARGB32() != _hsv.toColor().toARGB32()) {
      // Changed from outside (a base reset, a preset, the hex field): keep
      // the hue when the new colour is grey.
      final next = HSVColor.fromColor(widget.value);
      _hsv = next.saturation == 0 ? next.withHue(_hsv.hue) : next;
    }
    if (parseHex(_hex.text)?.toARGB32() != widget.value.toARGB32()) {
      _hex.text = hexOf(widget.value);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final motion = Motion.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: widget.headerKey,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(color: colors.text),
                  ),
                ),
                Text(
                  '#${hexOf(widget.value)}',
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
                const SizedBox(width: 10),
                _Swatch(
                  color: widget.value,
                  size: 28,
                  border: colors.mutedText,
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: colors.mutedText,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: motion.standard,
          curve: Motion.standardCurve,
          alignment: Alignment.topCenter,
          child: _expanded
              ? _picker(colors)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _picker(SongiesColors colors) {
    final current = widget.value.toARGB32();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (i, preset) in widget.presets.indexed)
                Semantics(
                  button: true,
                  label: '#${hexOf(preset)}',
                  selected: preset.toARGB32() == current,
                  child: InkWell(
                    key: Key('colourField.preset.$i'),
                    customBorder: const CircleBorder(),
                    onTap: () => widget.onChanged(preset),
                    child: _Swatch(
                      color: preset,
                      size: 32,
                      border: preset.toARGB32() == current
                          ? colors.accent
                          : colors.mutedText.withValues(alpha: 0.4),
                      borderWidth: preset.toARGB32() == current ? 3 : 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SaturationValueSquare(hsv: _hsv, onChanged: _setHsv),
          Slider(
            key: const Key('colourField.hue'),
            min: 0,
            max: 360,
            value: _hsv.hue,
            activeColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
            semanticFormatterCallback: (v) => 'Hue ${v.round()}',
            onChanged: (h) => _setHsv(_hsv.withHue(h)),
          ),
          TextField(
            key: const Key('colourField.hex'),
            controller: _hex,
            style: TextStyle(color: colors.text),
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              labelText: 'Hex',
              prefixText: '#',
              counterText: '',
              isDense: true,
              labelStyle: TextStyle(color: colors.mutedText),
            ),
            onChanged: (s) {
              final c = parseHex(s);
              if (c != null) widget.onChanged(c);
            },
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.size,
    required this.border,
    this.borderWidth = 1,
  });

  final Color color;
  final double size;
  final Color border;
  final double borderWidth;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: border, width: borderWidth),
    ),
  );
}

/// Saturation left to right, value top to bottom, for the current hue.
class _SaturationValueSquare extends StatelessWidget {
  const _SaturationValueSquare({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const double _height = 140;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      void pick(Offset p) => onChanged(
        hsv
            .withSaturation((p.dx / width).clamp(0.0, 1.0))
            .withValue(1 - (p.dy / _height).clamp(0.0, 1.0)),
      );
      return Semantics(
        label: 'Saturation and brightness',
        child: GestureDetector(
          key: const Key('colourField.saturationValue'),
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: SizedBox(
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xFF000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * width - 8,
                  top: (1 - hsv.value) * _height - 8,
                  child: IgnorePointer(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hsv.toColor(),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
