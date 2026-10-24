import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/log.dart';
import '../../../core/result.dart';
import '../../../providers.dart';
import '../../../theme/font_service.dart';
import '../../../theme/theme_repository.dart';
import '../../../theme/theme_spec.dart';

/// What a theme file's name ends with.
const themeFileExtension = '.songies-theme.json';

/// The message for any file that fails validation.
const notAThemeFile = "That isn't a Songies theme file";

const _formatVersion = 1;
const _maxFontBytes = 10 * 1024 * 1024;
// Base64 of the largest allowed font, plus room for the rest of the file.
const _maxFileBytes = (_maxFontBytes + 2) ~/ 3 * 4 + 64 * 1024;
const _maxNameLength = 40;
const _bases = {'charcoal', 'black', 'light'};

/// A font embedded in a theme file.
class ThemeFileFont {
  const ThemeFileFont({
    required this.family,
    required this.ext,
    required this.bytes,
  });

  final String family;

  /// `ttf` or `otf`.
  final String ext;
  final Uint8List bytes;
}

/// A theme as shared between people: `{"songiesTheme": 1, "name", "spec",
/// "font"?}`, where `font` (`family`, `ext`, `base64`) is present only for
/// an imported font.
class ThemeFile {
  const ThemeFile({required this.name, required this.spec, this.font});

  final String name;
  final ThemeSpec spec;
  final ThemeFileFont? font;

  /// The file's contents, as UTF-8 JSON.
  Uint8List encode() => utf8.encode(
    jsonEncode({
      'songiesTheme': _formatVersion,
      'name': name,
      'spec': spec.toJson(),
      if (font case final f?)
        'font': {
          'family': f.family,
          'ext': f.ext,
          'base64': base64Encode(f.bytes),
        },
    }),
  );

  /// Parses and strictly validates [bytes]; any problem is [notAThemeFile].
  static Result<ThemeFile> decode(List<int> bytes) {
    try {
      if (bytes.length > _maxFileBytes) throw const FormatException('size');
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) throw const FormatException('shape');
      final version = json['songiesTheme'];
      if (version is! int || version != _formatVersion) {
        throw const FormatException('version');
      }
      final name = json['name'];
      if (name is! String || name.trim().isEmpty) {
        throw const FormatException('name');
      }
      final specJson = json['spec'];
      if (specJson is! Map<String, dynamic>) {
        throw const FormatException('spec');
      }
      // Before fromJson, which would clamp the numbers and drop the alpha.
      _checkRanges(specJson);
      final spec = ThemeSpec.fromJson(specJson);
      return Ok(
        ThemeFile(
          name: name.trim(),
          spec: spec,
          font: _decodeFont(json['font']),
        ),
      );
    } catch (e) {
      AppLog.w('Rejected a theme file', e);
      return const Err(Failure(FailureKind.invalidInput, notAThemeFile));
    }
  }

  /// Rejects a raw spec whose base, numbers or font family are out of range,
  /// or with a colour that is not fully opaque (a theme file is strict where
  /// stored rows are clamped). Wrong types are left to [ThemeSpec.fromJson].
  static void _checkRanges(Map<String, dynamic> s) {
    bool within(String key, (double, double) range) {
      final v = s[key];
      return v is! num || (v.isFinite && v >= range.$1 && v <= range.$2);
    }

    bool opaque(String key) {
      final v = s[key];
      return v is! String ||
          v.length != 9 ||
          v.substring(1, 3).toLowerCase() == 'ff';
    }

    final base = s['base'];
    final family = s['fontFamily'];
    if ((base is String && !_bases.contains(base)) ||
        !within('glowStrength', ThemeSpec.glowRange) ||
        !within('cornerRadius', ThemeSpec.cornerRadiusRange) ||
        !within('fontScale', ThemeSpec.fontScaleRange) ||
        (family is String && family.trim().isEmpty) ||
        !['background', 'surface', 'text', 'accent'].every(opaque)) {
      throw const FormatException('range');
    }
  }

  static ThemeFileFont? _decodeFont(Object? json) {
    if (json == null) return null;
    if (json is! Map<String, dynamic>) throw const FormatException('font');
    final family = json['family'];
    final ext = json['ext'];
    final data = json['base64'];
    if (family is! String ||
        family.trim().isEmpty ||
        (ext != 'ttf' && ext != 'otf') ||
        data is! String) {
      throw const FormatException('font');
    }
    final bytes = base64Decode(data);
    if (bytes.isEmpty || bytes.length > _maxFontBytes) {
      throw const FormatException('font size');
    }
    return ThemeFileFont(
      family: family.trim(),
      ext: ext as String,
      bytes: bytes,
    );
  }
}

final _unsafeFileChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

/// `<name>.songies-theme.json`, with characters no file system allows
/// replaced by `_`.
String themeFileName(String themeName) {
  final safe = themeName.replaceAll(_unsafeFileChars, '_').trim();
  return '${safe.isEmpty ? 'theme' : safe}$themeFileExtension';
}

/// Builds theme files for export and saves imported ones.
class ThemeFiles {
  ThemeFiles(this._themes, this._fonts);

  final ThemeRepository _themes;
  final FontService _fonts;

  /// The file for [theme]. An imported font is embedded (when its file is on
  /// this device); a bundled one is referenced by family only.
  Future<ThemeFile> fileFor(ThemeEntry theme) async {
    final hash = theme.spec.fontFileHash;
    final font = hash == null ? null : await _fonts.importedFile(hash);
    return ThemeFile(
      name: theme.name,
      spec: theme.spec,
      font: font == null
          ? null
          : ThemeFileFont(
              family: font.family,
              ext: font.ext,
              bytes: font.bytes,
            ),
    );
  }

  /// Validates [bytes] and saves the theme under a de-duplicated name,
  /// returning its id. An embedded font is imported first, through
  /// [FontService.import] (so its contents are checked); if that fails, its
  /// error is returned and nothing is saved.
  Future<Result<String>> import(List<int> bytes) async {
    final decoded = ThemeFile.decode(bytes);
    final ThemeFile file;
    switch (decoded) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        file = value;
    }

    var spec = file.spec;
    FontImport? added;
    if (file.font case final font?) {
      final imported = await _importFont(font);
      switch (imported) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          if (value.created) added = value;
          spec = ThemeSpec.fromJson({
            ...spec.toJson(),
            'fontFamily': value.entry.family,
            'fontFileHash': value.entry.fileHash,
          });
      }
    }

    final name = file.name.length > _maxNameLength
        ? file.name.substring(0, _maxNameLength).trimRight()
        : file.name;
    final saved = await _themes.save(null, name, spec);
    if (saved is Err<String> && added != null) {
      // Never half an import: drop the font this import brought. The save
      // most likely failed on the database, so this may fail too; the save's
      // error is still the one the user sees.
      try {
        await _fonts.removeImported(added.entry.fileHash);
      } catch (e) {
        AppLog.w('Rolling back an imported theme font failed', e);
      }
    }
    return saved;
  }

  /// Reads the file at [path] and imports it as [import] does; a file too
  /// large to be a theme is rejected unread.
  Future<Result<String>> importFile(String path) async {
    final List<int> bytes;
    try {
      final file = File(path);
      if (await file.length() > _maxFileBytes) {
        return const Err(Failure(FailureKind.invalidInput, notAThemeFile));
      }
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      return Err(Failure(FailureKind.io, "Couldn't read that file", cause: e));
    }
    return import(bytes);
  }

  /// Hands [font] to [FontService.import] from a temporary file named after
  /// its family, deleted afterwards.
  Future<Result<FontImport>> _importFont(ThemeFileFont font) async {
    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('songies_theme_font');
      final safe = font.family.replaceAll(_unsafeFileChars, '_').trim();
      final path = p.join(
        dir.path,
        '${safe.isEmpty ? 'Font' : safe}.${font.ext}',
      );
      await File(path).writeAsBytes(font.bytes, flush: true);
      return await _fonts.importFont(path);
    } on FileSystemException catch (e) {
      return Err(Failure(FailureKind.io, "Couldn't import the font", cause: e));
    } finally {
      try {
        await dir?.delete(recursive: true);
      } on FileSystemException catch (e) {
        AppLog.w('Could not delete a temporary font file', e);
      }
    }
  }
}

final themeFilesProvider = Provider<ThemeFiles>(
  (ref) => ThemeFiles(
    ref.watch(themeRepositoryProvider),
    ref.watch(fontServiceProvider),
  ),
);

/// Saves an exported theme file: true once saved, false if cancelled.
/// Throws if saving fails.
typedef ThemeFileSaver = Future<bool> Function(
  String fileName,
  Uint8List bytes,
);

/// The same native save dialog as the log export; tests replace it.
final themeFileSaverProvider = Provider<ThemeFileSaver>(
  (ref) => (fileName, bytes) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export theme',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
    );
    return saved != null;
  },
);

/// Asks for a theme file to import; null when cancelled.
typedef ThemeFilePicker = Future<String?> Function();

/// The native file dialog; tests replace it. Any file can be picked: the
/// contents are what's validated.
final themeFilePickerProvider = Provider<ThemeFilePicker>(
  (ref) => () async {
    final file = await FilePicker.pickFile(dialogTitle: 'Import theme');
    return file?.path;
  },
);
