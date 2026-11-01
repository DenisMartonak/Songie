import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/log.dart';
import '../../../core/result.dart';
import '../../../providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/contrast.dart';
import '../../../theme/font_service.dart';
import '../../../theme/theme_spec.dart';
import '../../widgets/page_snack_bar.dart';
import 'colour_field.dart';
import 'theme_preview.dart';

/// The editor route's id for a theme that doesn't exist yet.
const newThemeId = 'new';

/// The colours a base resets the editor to.
typedef BaseColours = ({
  Color background,
  Color surface,
  Color text,
  Color accent,
});

const editorBaseColours = <String, BaseColours>{
  'charcoal': (
    background: Color(0xFF121212),
    surface: Color(0xFF2A2A2A),
    text: Color(0xFFFFFFFF),
    accent: Color(0xFF1DB954),
  ),
  'black': (
    background: Color(0xFF000000),
    surface: Color(0xFF141414),
    text: Color(0xFFFFFFFF),
    accent: Color(0xFF1DB954),
  ),
  'light': (
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF121212),
    accent: Color(0xFF117A37),
  ),
};

const _baseLabels = {
  'charcoal': 'Charcoal',
  'black': 'Black',
  'light': 'Light',
};

const _backgroundPresets = [
  Color(0xFF121212),
  Color(0xFF000000),
  Color(0xFF0D1117),
  Color(0xFF1A1A2E),
  Color(0xFF1E1B18),
  Color(0xFF0F2027),
  Color(0xFFF5F5F5),
  Color(0xFFFFFFFF),
];
const _surfacePresets = [
  Color(0xFF2A2A2A),
  Color(0xFF141414),
  Color(0xFF161B22),
  Color(0xFF25253D),
  Color(0xFF2B2622),
  Color(0xFF1B3440),
  Color(0xFFFFFFFF),
  Color(0xFFE8E8E8),
];
const _textPresets = [
  Color(0xFFFFFFFF),
  Color(0xFFF5F5F5),
  Color(0xFFE0E0E0),
  Color(0xFFFFF8E7),
  Color(0xFFCCE7FF),
  Color(0xFF121212),
  Color(0xFF000000),
  Color(0xFF333333),
];
const _accentPresets = [
  Color(0xFF1DB954),
  Color(0xFF00E5FF),
  Color(0xFFFF4081),
  Color(0xFFFFB300),
  Color(0xFF7C4DFF),
  Color(0xFFFF5722),
  Color(0xFF2979FF),
  Color(0xFF117A37),
];

const _maxNameLength = 40;

/// Asks for a `.ttf`/`.otf` file; null when cancelled.
typedef FontFilePicker = Future<String?> Function();

/// The native file dialog; tests replace it. Any file can be picked:
/// [FontService.import] checks what it is.
final fontFilePickerProvider = Provider<FontFilePicker>(
  (ref) => () async {
    final file = await FilePicker.pickFile(dialogTitle: 'Import font');
    return file?.path;
  },
);

/// Edits a theme against a live preview. Nothing is written, and the app's
/// theme doesn't change, until Save, which saves the theme (a built-in as a
/// new copy) and makes it active. [id] is a theme id or [newThemeId].
class ThemeEditorPage extends ConsumerStatefulWidget {
  const ThemeEditorPage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends ConsumerState<ThemeEditorPage> {
  final _name = TextEditingController();
  bool _loaded = false;
  bool _missing = false;
  bool _saving = false;

  /// The saved theme Save updates, or null to insert a new one.
  String? _saveId;
  late ThemeSpec _original;
  late ThemeSpec _spec;
  late String _originalName;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    ThemeSpec spec = ThemeSpec.builtInDefault;
    var name = 'My theme';
    if (widget.id != newThemeId) {
      final all = await ref.read(themeRepositoryProvider).watchAll().first;
      final entry = all.where((e) => e.id == widget.id).firstOrNull;
      if (!mounted) return;
      if (entry == null) {
        setState(() => _missing = true);
        return;
      }
      spec = entry.spec;
      if (entry.builtIn) {
        name = '${entry.name} copy';
      } else {
        name = entry.name;
        _saveId = entry.id;
      }
    }
    if (!mounted) return;
    setState(() {
      _original = _spec = _inRange(spec);
      _originalName = name;
      _name.text = name;
      _loaded = true;
    });
  }

  /// [s] with its slider values inside the editor's ranges (a synced theme
  /// could hold anything).
  static ThemeSpec _inRange(ThemeSpec s) => s.copyWith(
    glowStrength: s.glowStrength.clamp(0.0, 1.0),
    cornerRadius: s.cornerRadius.clamp(0.0, 24.0),
    fontScale: s.fontScale.clamp(0.85, 1.3),
    base: editorBaseColours.containsKey(s.base) ? s.base : 'charcoal',
  );

  bool get _dirty =>
      _loaded && (_spec != _original || _name.text.trim() != _originalName);

  void _edit(ThemeSpec spec) => setState(() => _spec = spec);

  void _setBase(String base) {
    final c = editorBaseColours[base]!;
    _edit(
      _spec.copyWith(
        base: base,
        background: c.background,
        surface: c.surface,
        text: c.text,
        accent: c.accent,
      ),
    );
  }

  /// [_spec] rendered with [family] ([hash] for an imported font, null for a
  /// bundled one).
  ThemeSpec _withFont(String family, String? hash) => ThemeSpec.fromJson({
    ..._spec.toJson(),
    'fontFamily': family,
    'fontFileHash': hash,
  });

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this theme will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// Leaves the editor, asking first when there are unsaved changes.
  Future<void> _leave() async {
    if (_dirty && !await _confirmDiscard()) return;
    if (mounted) context.pop();
  }

  Future<void> _save() async {
    final snacks = PageSnackBars.of(context);
    final repo = ref.read(themeRepositoryProvider);
    setState(() => _saving = true);
    final r = await repo.save(_saveId, _name.text, _spec);
    switch (r) {
      case Err(:final failure):
        snacks.show(content: Text(failure.message));
        if (mounted) setState(() => _saving = false);
        return;
      case Ok(:final value):
        // Saved: from now on Save updates this theme, and leaving loses
        // nothing.
        if (mounted) {
          setState(() {
            _saveId = value;
            _original = _spec;
            _originalName = _name.text.trim();
          });
        }
        try {
          await repo.setActive(value);
        } catch (e, s) {
          AppLog.e('Making theme $value active failed', e, s);
          snacks.show(content: const Text("Couldn't apply the theme"));
          if (mounted) setState(() => _saving = false);
          return;
        }
        if (mounted) context.pop();
    }
  }

  Future<void> _importFont() async {
    final snacks = PageSnackBars.of(context);
    // The import outlives the page if it is closed meanwhile; the providers
    // must still learn about the new font.
    final container = ProviderScope.containerOf(context, listen: false);
    final path = await ref.read(fontFilePickerProvider)();
    if (path == null) return;
    final fonts = ref.read(fontServiceProvider);
    final r = await fonts.importFont(path);
    switch (r) {
      case Err(:final failure):
        snacks.show(content: Text(failure.message));
      case Ok(value: FontImport(:final entry)):
        // The new family is usable at once, by the editor and by any theme
        // that already names it.
        container.invalidate(resolvedFontFamilyProvider);
        container.invalidate(importedFontsProvider);
        if (mounted) _edit(_withFont(entry.family, entry.fileHash));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: SafeArea(
        child: Column(
          children: [
            _header(colors),
            Expanded(child: _body(colors)),
          ],
        ),
      ),
    );
  }

  Widget _header(SongiesColors colors) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
    child: Row(
      children: [
        IconButton(
          key: const Key('themeEditor.back'),
          tooltip: 'Back',
          color: colors.text,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _leave,
        ),
        Expanded(
          child: Text(
            widget.id == newThemeId ? 'New theme' : 'Edit theme',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(
          key: const Key('themeEditor.cancel'),
          onPressed: _leave,
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('themeEditor.save'),
          onPressed: _loaded && !_saving && _name.text.trim().isNotEmpty
              ? _save
              : null,
          child: const Text('Save'),
        ),
      ],
    ),
  );

  /// The family [_spec] renders with; rebuilt when the imported fonts
  /// change, as a font registers.
  String _resolvedFamily() {
    ref.watch(importedFontsProvider);
    return ref.watch(fontServiceProvider).resolveFamily(_spec);
  }

  Widget _body(SongiesColors colors) {
    if (_missing) {
      return Center(
        child: Text(
          'This theme no longer exists',
          style: TextStyle(color: colors.mutedText),
        ),
      );
    }
    if (!_loaded) return const SizedBox.shrink();
    final preview = Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ThemePreview(spec: _spec, fontFamily: _resolvedFamily()),
      ),
    );
    final controls = SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: _controls(colors),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: controls),
              SizedBox(width: 400, child: preview),
            ],
          );
        }
        return Column(
          children: [
            // Phones in landscape keep most of the height for the controls.
            SizedBox(
              height: math.min(240, constraints.maxHeight * 0.4),
              child: preview,
            ),
            Expanded(child: controls),
          ],
        );
      },
    );
  }

  Widget _controls(SongiesColors colors) {
    final lowContrast = contrastRatio(_spec.text, _spec.background) < 4.5;
    TextStyle label() => TextStyle(color: colors.text);
    TextStyle hint() => TextStyle(color: colors.mutedText, fontSize: 12);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          color: colors.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget slider({
      required Key key,
      required String title,
      required double value,
      required double min,
      required double max,
      required int divisions,
      required String Function(double) format,
      required ValueChanged<double> onChanged,
    }) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: label())),
              Text(format(value), style: hint()),
            ],
          ),
          Slider(
            key: key,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
    Widget colour(
      String field,
      String title,
      Color value,
      List<Color> presets,
      ThemeSpec Function(Color) apply,
    ) => ColourField(
      key: Key('themeEditor.colourField.$field'),
      headerKey: Key('themeEditor.colour.$field'),
      label: title,
      value: value,
      presets: presets,
      onChanged: (c) => _edit(apply(c)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const Key('themeEditor.name'),
            controller: _name,
            maxLength: _maxNameLength,
            style: label(),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: colors.mutedText),
            ),
          ),
        ),
        heading('Base'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            key: const Key('themeEditor.base'),
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(:key, :value) in _baseLabels.entries)
                ButtonSegment(value: key, label: Text(value)),
            ],
            selected: {_spec.base},
            onSelectionChanged: (s) => _setBase(s.single),
          ),
        ),
        heading('Colours'),
        colour(
          'background',
          'Background',
          _spec.background,
          _backgroundPresets,
          (c) => _spec.copyWith(background: c),
        ),
        colour(
          'surface',
          'Surface',
          _spec.surface,
          _surfacePresets,
          (c) => _spec.copyWith(surface: c),
        ),
        colour(
          'text',
          'Text',
          _spec.text,
          _textPresets,
          (c) => _spec.copyWith(text: c),
        ),
        colour(
          'accent',
          'Accent',
          _spec.accent,
          _accentPresets,
          (c) => _spec.copyWith(accent: c),
        ),
        if (lowContrast)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                key: const Key('themeEditor.contrastWarning'),
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Text may be hard to read'),
              ),
            ),
          ),
        heading('Effects'),
        SwitchListTile(
          key: const Key('themeEditor.followCover'),
          title: Text('Follow cover', style: label()),
          subtitle: Text(
            "The accent comes from the playing song's cover",
            style: hint(),
          ),
          value: _spec.followCover,
          onChanged: (v) => _edit(_spec.copyWith(followCover: v)),
        ),
        slider(
          key: const Key('themeEditor.glow'),
          title: 'Glow strength',
          value: _spec.glowStrength,
          min: 0,
          max: 1,
          divisions: 20,
          format: (v) => '${(v * 100).round()} %',
          onChanged: (v) => _edit(_spec.copyWith(glowStrength: v)),
        ),
        slider(
          key: const Key('themeEditor.radius'),
          title: 'Corner radius',
          value: _spec.cornerRadius,
          min: 0,
          max: 24,
          divisions: 24,
          format: (v) => '${v.round()}',
          onChanged: (v) => _edit(_spec.copyWith(cornerRadius: v)),
        ),
        SwitchListTile(
          key: const Key('themeEditor.blur'),
          title: Text('Blur Now Playing', style: label()),
          subtitle: Text('A blurred cover behind Now Playing', style: hint()),
          value: _spec.blurNowPlaying,
          onChanged: (v) => _edit(_spec.copyWith(blurNowPlaying: v)),
        ),
        heading('Text'),
        _fontMenu(colors),
        slider(
          key: const Key('themeEditor.fontScale'),
          title: 'Font scale',
          value: _spec.fontScale,
          min: 0.85,
          max: 1.3,
          divisions: 9,
          format: (v) => '${(v * 100).round()} %',
          onChanged: (v) => _edit(_spec.copyWith(fontScale: v)),
        ),
      ],
    );
  }

  static const _importItem = '\u0000import';

  Widget _fontMenu(SongiesColors colors) {
    final bundled = ref.watch(fontServiceProvider).bundledFamilies;
    final imported = ref.watch(importedFontsProvider).value ?? const [];
    String bundledValue(String f) => 'bundled:$f';
    String importedValue(FontEntry f) => 'font:${f.fileHash}';

    final items = <DropdownMenuItem<String>>[
      for (final f in bundled)
        DropdownMenuItem(
          value: bundledValue(f),
          child: Text(f, style: TextStyle(fontFamily: f)),
        ),
      for (final f in imported)
        DropdownMenuItem(
          value: importedValue(f),
          child: Text(f.family, style: TextStyle(fontFamily: f.family)),
        ),
    ];
    final hash = _spec.fontFileHash;
    var selected = hash != null ? 'font:$hash' : bundledValue(_spec.fontFamily);
    if (!items.any((i) => i.value == selected)) {
      // A font this device doesn't have (yet): keep it, labelled as such.
      selected = 'current';
      items.add(
        DropdownMenuItem(
          value: selected,
          child: Text('${_spec.fontFamily} (not on this device)'),
        ),
      );
    }
    items.add(
      const DropdownMenuItem(value: _importItem, child: Text('Import font…')),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text('Font', style: TextStyle(color: colors.text)),
          ),
          DropdownButton<String>(
            key: const Key('themeEditor.font'),
            value: selected,
            items: items,
            dropdownColor: colors.surface,
            style: TextStyle(color: colors.text),
            onChanged: (v) {
              if (v == null || v == selected) return;
              if (v == _importItem) {
                _importFont();
                return;
              }
              if (v.startsWith('bundled:')) {
                _edit(_withFont(v.substring('bundled:'.length), null));
                return;
              }
              final font = imported.firstWhere((f) => importedValue(f) == v);
              _edit(_withFont(font.family, font.fileHash));
            },
          ),
        ],
      ),
    );
  }
}
