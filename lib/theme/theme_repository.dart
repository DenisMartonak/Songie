import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/result.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/settings_repository.dart';
import '../data/sync_stamp.dart';
import 'theme_spec.dart';

const kActiveThemeId = 'active_theme_id';
const kDefaultThemeId = 'builtin:default';
const kAlbumGlowThemeId = 'builtin:album-glow';
const kTerminalThemeId = 'builtin:terminal';

const _builtInPrefix = 'builtin:';
const _maxNameLength = 40;

/// A theme as shown in the list: a built-in or a saved (synced) one.
class ThemeEntry {
  const ThemeEntry({
    required this.id,
    required this.name,
    required this.spec,
    required this.builtIn,
  });

  final String id;
  final String name;
  final ThemeSpec spec;
  final bool builtIn;

  @override
  bool operator ==(Object other) =>
      other is ThemeEntry &&
      other.id == id &&
      other.name == name &&
      other.spec == spec &&
      other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(id, name, spec, builtIn);
}

const _builtIns = <ThemeEntry>[
  ThemeEntry(
    id: kDefaultThemeId,
    name: 'Default',
    spec: ThemeSpec.builtInDefault,
    builtIn: true,
  ),
  ThemeEntry(
    id: kAlbumGlowThemeId,
    name: 'Album glow',
    spec: ThemeSpec.albumGlow,
    builtIn: true,
  ),
  ThemeEntry(
    id: kTerminalThemeId,
    name: 'Terminal',
    spec: ThemeSpec.terminal,
    builtIn: true,
  ),
];

bool _isBuiltIn(String id) => id.startsWith(_builtInPrefix);

/// The built-in themes plus the user's saved themes (synced `themes` table),
/// and the device-local choice of active theme.
class ThemeRepository {
  ThemeRepository(this._db, this._stamp, this._settings);

  final AppDatabase _db;
  final SyncStamp _stamp;
  final SettingsRepository _settings;

  ThemeEntry? _builtIn(String id) {
    for (final b in _builtIns) {
      if (b.id == id) return b;
    }
    return null;
  }

  ThemeEntry _fromRow(ThemeRow row) => ThemeEntry(
    id: row.id,
    name: row.name,
    spec: ThemeSpec.fromJson(jsonDecode(row.specJson) as Map<String, dynamic>),
    builtIn: false,
  );

  Future<List<ThemeRow>> _liveRows() =>
      (_db.select(_db.themes)
            ..where((t) => t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.name.lower())]))
          .get();

  Future<ThemeRow?> _liveRow(String id) => (_db.select(
    _db.themes,
  )..where((t) => t.id.equals(id) & t.deleted.equals(false))).getSingleOrNull();

  /// Built-ins first, then saved themes by name.
  Stream<List<ThemeEntry>> watchAll() =>
      (_db.select(_db.themes)
            ..where((t) => t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.name.lower())]))
          .watch()
          .map((rows) => [..._builtIns, for (final r in rows) _fromRow(r)]);

  /// The active theme. With no stored choice, a fresh install (no tracks yet)
  /// becomes Album glow, persisted so importing a song doesn't flip it; an
  /// existing library resolves to Default. A stored id that is missing or
  /// tombstoned resolves to Default.
  Stream<ThemeEntry> watchActive() {
    final changes = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.settings, _db.themes, _db.tracks},
        )
        .watch();
    return changes.asyncMap((_) => _resolveActive()).distinct();
  }

  Future<ThemeEntry> _resolveActive() async {
    var id = await _settings.getString(kActiveThemeId);
    if (id == null) {
      final anyTrack =
          await (_db.selectOnly(_db.tracks)
                ..addColumns([_db.tracks.id])
                ..limit(1))
              .get();
      if (anyTrack.isNotEmpty) return _builtIns[0];
      id = kAlbumGlowThemeId;
      await _settings.setString(kActiveThemeId, id);
    }
    final builtIn = _builtIn(id);
    if (builtIn != null) return builtIn;
    final row = await _liveRow(id);
    if (row == null) return _builtIns[0];
    try {
      return _fromRow(row);
    } on FormatException {
      return _builtIns[0];
    }
  }

  String? _cleanName(String name) {
    final t = name.trim();
    return t.isEmpty || t.length > _maxNameLength ? null : t;
  }

  /// [base], or `<base> 2`, `<base> 3`, … when another live theme (not
  /// [exceptId]) already has that name, ignoring case.
  Future<String> _uniqueName(String base, {String? exceptId}) async {
    final taken = {
      for (final r in await _liveRows())
        if (r.id != exceptId) r.name.toLowerCase(),
      for (final b in _builtIns) b.name.toLowerCase(),
    };
    var candidate = base;
    for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
      final suffix = ' $n';
      final head = base.length + suffix.length > _maxNameLength
          ? base.substring(0, _maxNameLength - suffix.length).trimRight()
          : base;
      candidate = '$head$suffix';
    }
    return candidate;
  }

  String _copyName(String name) {
    const suffix = ' copy';
    final head = name.length + suffix.length > _maxNameLength
        ? name.substring(0, _maxNameLength - suffix.length).trimRight()
        : name;
    return '$head$suffix';
  }

  Result<T> _badName<T>() => Err(
    Failure(
      FailureKind.invalidInput,
      'Theme names must be 1-$_maxNameLength characters',
    ),
  );

  Result<T> _notFound<T>(String what) =>
      Err(Failure(FailureKind.notFound, 'No such theme: $what'));

  /// Saves [spec] as [name]. A null or built-in [id] inserts a new row (a
  /// built-in is copied as `<name> copy`); a saved id updates it in place.
  /// Returns the id of the written row.
  Future<Result<String>> save(String? id, String name, ThemeSpec spec) async {
    final clean = _cleanName(name);
    if (clean == null) return _badName<String>();
    return guardDb(_db, () async {
      if (id == null || _isBuiltIn(id)) {
        final base = id == null ? clean : _copyName(clean);
        final unique = await _uniqueName(base);
        return Ok(await _insertReturningId(unique, spec));
      }
      if (await _liveRow(id) == null) return _notFound<String>(id);
      final unique = await _uniqueName(clean, exceptId: id);
      final stamp = await _stamp.next();
      await (_db.update(_db.themes)..where((t) => t.id.equals(id))).write(
        ThemesCompanion(
          name: Value(unique),
          specJson: Value(jsonEncode(spec.toJson())),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      return Ok(id);
    });
  }

  Future<String> _insertReturningId(String name, ThemeSpec spec) async {
    final stamp = await _stamp.next();
    await _db
        .into(_db.themes)
        .insert(
          ThemesCompanion.insert(
            id: stamp.id,
            clock: stamp.clock,
            originDevice: stamp.originDevice,
            localSeq: stamp.localSeq,
            name: name,
            specJson: jsonEncode(spec.toJson()),
          ),
        );
    return stamp.id;
  }

  /// Tombstones a saved theme. Built-ins are refused. Deleting the active
  /// theme switches to Default.
  Future<Result<void>> delete(String id) async {
    if (_isBuiltIn(id)) {
      return Err(
        Failure(FailureKind.invalidInput, 'Built-in themes cannot be deleted'),
      );
    }
    return guardDb(_db, () async {
      if (await _liveRow(id) == null) return _notFound<void>(id);
      final stamp = await _stamp.next();
      await (_db.update(_db.themes)..where((t) => t.id.equals(id))).write(
        ThemesCompanion(
          deleted: const Value(true),
          clock: Value(stamp.clock),
          originDevice: Value(stamp.originDevice),
          localSeq: Value(stamp.localSeq),
        ),
      );
      if (await _settings.getString(kActiveThemeId) == id) {
        await _settings.setString(kActiveThemeId, kDefaultThemeId);
      }
      return const Ok(null);
    });
  }

  Future<void> setActive(String id) => _settings.setString(kActiveThemeId, id);

  /// Saves a copy of [id] (built-in or saved) named `<name> copy`.
  Future<Result<String>> duplicate(String id) async {
    final ThemeEntry source;
    final builtIn = _builtIn(id);
    if (builtIn != null) {
      source = builtIn;
    } else {
      final row = await _liveRow(id);
      if (row == null) return _notFound<String>(id);
      source = _fromRow(row);
    }
    return guardDb(_db, () async {
      final unique = await _uniqueName(_copyName(source.name));
      return Ok(await _insertReturningId(unique, source.spec));
    });
  }
}
