import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import 'theme_spec.dart';

/// Registers font [data] under [family] with the engine.
typedef FontRegistrar = Future<void> Function(
  String family,
  List<Uint8List> data,
);

Future<void> _registerWithFontLoader(
  String family,
  List<Uint8List> data,
) async {
  final loader = FontLoader(family);
  for (final d in data) {
    loader.addFont(Future.value(ByteData.sublistView(d)));
  }
  await loader.load();
}

const _maxFontBytes = 10 * 1024 * 1024;
const _fallbackFamily = 'Inter';

/// An imported font as listed in the theme editor.
class FontEntry {
  const FontEntry({
    required this.family,
    required this.fileHash,
    required this.ext,
  });

  final String family;
  final String fileHash;
  final String ext;

  @override
  bool operator ==(Object other) =>
      other is FontEntry &&
      other.family == family &&
      other.fileHash == fileHash &&
      other.ext == ext;

  @override
  int get hashCode => Object.hash(family, fileHash, ext);
}

final _styleSuffix = RegExp(
  r'(?:[-_ ]*(?:Regular|Bold|SemiBold|ExtraBold|Light|ExtraLight|Medium|Thin|Black|Heavy|Book|Italic|Oblique|Variable|VF))+$',
  caseSensitive: false,
);

/// Bundled fonts plus fonts the user imported (`<fontsDir>/<sha256>.<ext>`,
/// one synced `fonts` row each).
class FontService {
  FontService(
    this._db,
    this._stamp,
    this._fontsDir, {
    FontRegistrar register = _registerWithFontLoader,
    // ignore: prefer_initializing_formals
  }) : _register = register;

  final AppDatabase _db;
  final SyncStamp _stamp;
  final Directory _fontsDir;
  final FontRegistrar _register;

  final List<String> bundledFamilies = const [
    'Inter',
    'Outfit',
    'JetBrains Mono',
  ];

  /// Imported families registered on this device, so [resolveFamily] is sync.
  final Set<String> _registered = {};

  Future<List<FontRow>> _liveRows() =>
      (_db.select(_db.fonts)..where((f) => f.deleted.equals(false))).get();

  /// Registers every stored font; a missing or unreadable file is logged and
  /// skipped.
  Future<void> loadImported() async {
    for (final row in await _liveRows()) {
      final file = File(p.join(_fontsDir.path, '${row.fileHash}.${row.ext}'));
      try {
        if (!await file.exists()) {
          AppLog.w('Font file missing for ${row.family}; skipping');
          continue;
        }
        await _register(row.family, [await file.readAsBytes()]);
        _registered.add(row.family);
      } catch (e) {
        AppLog.w('Could not load font ${row.family}', e);
      }
    }
  }

  Stream<List<FontEntry>> watchAll() =>
      (_db.select(_db.fonts)
            ..where((f) => f.deleted.equals(false))
            ..orderBy([(f) => OrderingTerm(expression: f.family.lower())]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                FontEntry(family: r.family, fileHash: r.fileHash, ext: r.ext),
            ],
          );

  /// The font family [s] should render with: a bundled or registered family,
  /// else Inter.
  String resolveFamily(ThemeSpec s) =>
      bundledFamilies.contains(s.fontFamily) ||
          _registered.contains(s.fontFamily)
      ? s.fontFamily
      : _fallbackFamily;

  Result<String> _notAFont() =>
      Err(Failure(FailureKind.invalidInput, "That file isn't a font"));

  static bool _hasFontMagic(List<int> b) {
    if (b.length < 4) return false;
    if (b[0] == 0 && b[1] == 1 && b[2] == 0 && b[3] == 0) return true;
    final tag = String.fromCharCodes(b.sublist(0, 4));
    return tag == 'true' || tag == 'OTTO';
  }

  static String _familyOf(String path) {
    final base = p.basenameWithoutExtension(path);
    final stripped = base
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceFirst(_styleSuffix, '')
        .trim();
    return stripped.isEmpty ? base.trim() : stripped;
  }

  /// Imports the `.ttf`/`.otf` at [path]; returns its family name.
  Future<Result<String>> import(String path) async {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext != 'ttf' && ext != 'otf') return _notAFont();

    final Uint8List bytes;
    try {
      final file = File(path);
      if (await file.length() > _maxFontBytes) {
        return Err(
          Failure(FailureKind.invalidInput, 'Font files must be under 10 MB'),
        );
      }
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      return Err(Failure(FailureKind.io, "Couldn't read that file", cause: e));
    }
    if (bytes.length > _maxFontBytes) {
      return Err(
        Failure(FailureKind.invalidInput, 'Font files must be under 10 MB'),
      );
    }
    if (!_hasFontMagic(bytes)) return _notAFont();

    final hash = sha256.convert(bytes).toString();
    try {
      return await guardDb(_db, () async {
        final rows = await _liveRows();
        for (final r in rows) {
          if (r.fileHash == hash) return Ok(r.family);
        }

        final taken = {
          for (final r in rows) r.family.toLowerCase(),
          for (final b in bundledFamilies) b.toLowerCase(),
        };
        final base = _familyOf(path);
        var family = base;
        for (var n = 2; taken.contains(family.toLowerCase()); n++) {
          family = '$base $n';
        }

        await _fontsDir.create(recursive: true);
        final dest = File(p.join(_fontsDir.path, '$hash.$ext'));
        if (!await dest.exists()) await dest.writeAsBytes(bytes, flush: true);
        await _register(family, [bytes]);

        final s = await _stamp.next();
        await _db
            .into(_db.fonts)
            .insert(
              FontsCompanion.insert(
                id: s.id,
                clock: s.clock,
                originDevice: s.originDevice,
                localSeq: s.localSeq,
                family: family,
                fileHash: hash,
                ext: ext,
              ),
            );
        _registered.add(family);
        return Ok(family);
      });
    } on FileSystemException catch (e) {
      return Err(Failure(FailureKind.io, "Couldn't save that font", cause: e));
    } catch (e) {
      AppLog.w('Font registration failed', e);
      return Err(Failure(FailureKind.unknown, "That file isn't a font"));
    }
  }
}
