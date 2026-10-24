import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late SettingsRepository settings;
  late ThemeRepository repo;

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    settings = SettingsRepository(db);
    repo = ThemeRepository(db, stamp, settings);
  });
  tearDown(() => db.close());

  String ok(Result<String> r) => (r as Ok<String>).value;
  FailureKind failureOf(Result<Object?> r) => (r as Err<Object?>).failure.kind;
  const spec = ThemeSpec.builtInDefault;

  group('built-ins', () {
    test('match the spec values', () async {
      final all = await repo.watchAll().first;
      expect(all.map((e) => e.id), [
        'builtin:default',
        'builtin:album-glow',
        'builtin:terminal',
      ]);
      expect(all.every((e) => e.builtIn), isTrue);
      expect(all.map((e) => e.name), ['Default', 'Album glow', 'Terminal']);

      final d = all[0].spec;
      expect(d.base, 'charcoal');
      expect(d.accent, const Color(0xFF1DB954));
      expect(d.fontFamily, 'Inter');
      expect(d.cornerRadius, 6);
      expect(d.followCover, isFalse);

      final a = all[1].spec;
      expect(a.base, 'charcoal');
      expect(a.background, d.background);
      expect(a.surface, d.surface);
      expect(a.text, d.text);
      expect(a.accent, const Color(0xFF1DB954));
      expect(a.fontFamily, 'Outfit');
      expect(a.cornerRadius, 12);
      expect(a.followCover, isTrue);
      expect(a.glowStrength, 0.65);
      expect(d.glowStrength, 0.4);

      final t = all[2].spec;
      expect(t.base, 'black');
      expect(t.background, const Color(0xFF000000));
      expect(t.accent, const Color(0xFF00E5FF));
      expect(t.fontFamily, 'JetBrains Mono');
      expect(t.cornerRadius, 0);
      expect(t.followCover, isFalse);
      expect(t.glowStrength, 0.4);
    });

    test('are never stored', () async {
      await repo.watchAll().first;
      await repo.watchActive().first;
      expect(await db.select(db.themes).get(), isEmpty);
    });
  });

  group('save', () {
    test('inserts a stamped row that round-trips spec_json', () async {
      final custom = spec.copyWith(
        accent: const Color(0xFFFF00AA),
        cornerRadius: 9,
      );
      final id = ok(await repo.save(null, '  Mine  ', custom));
      final row = await db.select(db.themes).getSingle();
      expect(row.id, id);
      expect(row.name, 'Mine');
      expect(row.deleted, isFalse);
      expect(row.originDevice, stamp.deviceId);
      expect(row.localSeq, greaterThan(0));
      expect(ThemeSpec.fromJson(jsonDecode(row.specJson)), custom);

      final all = await repo.watchAll().first;
      expect(all.last.id, id);
      expect(all.last.builtIn, isFalse);
      expect(all.last.spec, custom);
    });

    test('updating re-stamps the row and renames it', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      final before = await db.select(db.themes).getSingle();
      expect(ok(await repo.save(id, 'Renamed', spec)), id);
      final after = await db.select(db.themes).getSingle();
      expect(after.name, 'Renamed');
      expect(after.localSeq, greaterThan(before.localSeq));
      expect(after.clock.compareTo(before.clock), greaterThan(0));
    });

    test('a name clash gets a numeric suffix', () async {
      await repo.save(null, 'Mine', spec);
      final b = ok(await repo.save(null, 'Mine', spec));
      final c = ok(await repo.save(null, 'mine', spec));
      final names = {for (final e in await repo.watchAll().first) e.id: e.name};
      expect(names[b], 'Mine 2');
      expect(names[c], 'mine 3');
    });

    test('keeping its own name on update is not a clash', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      await repo.save(id, 'Mine', spec.copyWith(cornerRadius: 3));
      final row = await db.select(db.themes).getSingle();
      expect(row.name, 'Mine');
    });

    test('a deleted theme frees its name', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      await repo.delete(id);
      final again = ok(await repo.save(null, 'Mine', spec));
      final row = await (db.select(
        db.themes,
      )..where((t) => t.id.equals(again))).getSingle();
      expect(row.name, 'Mine');
    });

    test('a built-in id saves a copy named "<name> copy"', () async {
      final id = ok(await repo.save('builtin:default', 'Default', spec));
      expect(id, isNot(startsWith('builtin:')));
      final again = ok(await repo.save('builtin:default', 'Default', spec));
      final names = {for (final e in await repo.watchAll().first) e.id: e.name};
      expect(names[id], 'Default copy');
      expect(names[again], 'Default copy 2');
    });

    test('rejects empty and over-long names', () async {
      expect(
        failureOf(await repo.save(null, '   ', spec)),
        FailureKind.invalidInput,
      );
      expect(
        failureOf(await repo.save(null, 'x' * 41, spec)),
        FailureKind.invalidInput,
      );
      expect(ok(await repo.save(null, 'x' * 40, spec)), isNotEmpty);
    });

    test('an unknown or deleted id is notFound', () async {
      expect(
        failureOf(await repo.save('nope', 'A', spec)),
        FailureKind.notFound,
      );
      final id = ok(await repo.save(null, 'A', spec));
      await repo.delete(id);
      expect(failureOf(await repo.save(id, 'A', spec)), FailureKind.notFound);
    });
  });

  group('delete', () {
    test('tombstones with a fresh stamp', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      final before = await db.select(db.themes).getSingle();
      expect(await repo.delete(id), isA<Ok<void>>());
      final row = await db.select(db.themes).getSingle();
      expect(row.deleted, isTrue);
      expect(row.localSeq, greaterThan(before.localSeq));
      expect(row.clock.compareTo(before.clock), greaterThan(0));
      expect(
        (await repo.watchAll().first).map((e) => e.id),
        isNot(contains(id)),
      );
    });

    test('refuses built-ins', () async {
      for (final id in [
        'builtin:default',
        'builtin:album-glow',
        'builtin:terminal',
      ]) {
        expect(failureOf(await repo.delete(id)), FailureKind.invalidInput);
      }
    });

    test('unknown id is notFound', () async {
      expect(failureOf(await repo.delete('nope')), FailureKind.notFound);
    });

    test('deleting the active theme switches to Default', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      await repo.setActive(id);
      expect((await repo.watchActive().first).id, id);
      await repo.delete(id);
      expect((await repo.watchActive().first).id, 'builtin:default');
      expect(await settings.getString('active_theme_id'), 'builtin:default');
    });

    test('deleting an inactive theme leaves the active one', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      await repo.setActive('builtin:terminal');
      await repo.delete(id);
      expect((await repo.watchActive().first).id, 'builtin:terminal');
    });
  });

  group('active theme', () {
    test(
      'a fresh install (no row, no tracks) is Album glow, persisted',
      () async {
        expect((await repo.watchActive().first).id, 'builtin:album-glow');
        expect(
          await settings.getString('active_theme_id'),
          'builtin:album-glow',
        );
      },
    );

    test('an existing library is Default, persisted', () async {
      await db.into(db.tracks).insert(trackRow(id: 't1'));
      expect((await repo.watchActive().first).id, 'builtin:default');
      expect(
        await settings.getString('active_theme_id'),
        equals('builtin:default'),
      );
    });

    test(
      'an existing library stays Default after the library is emptied',
      () async {
        await db.into(db.tracks).insert(trackRow(id: 't1'));
        expect((await repo.watchActive().first).id, 'builtin:default');
        expect(await settings.getString('active_theme_id'), 'builtin:default');
        await db.delete(db.tracks).go();
        expect((await repo.watchActive().first).id, 'builtin:default');
      },
    );

    test('a fresh install stays Album glow after a track is added', () async {
      expect((await repo.watchActive().first).id, 'builtin:album-glow');
      await db.into(db.tracks).insert(trackRow(id: 't1'));
      expect((await repo.watchActive().first).id, 'builtin:album-glow');
    });

    test('setActive switches and the stream emits the change', () async {
      final emitted = <String>[];
      final sub = repo.watchActive().listen((e) => emitted.add(e.id));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await repo.setActive('builtin:terminal');
      await pumpEventQueue();
      expect(emitted.last, 'builtin:terminal');
    });

    test('a missing stored id falls back to Default', () async {
      await settings.setString('active_theme_id', 'gone');
      expect((await repo.watchActive().first).id, 'builtin:default');
    });

    test('a tombstoned stored id falls back to Default', () async {
      final id = ok(await repo.save(null, 'Mine', spec));
      await repo.setActive(id);
      // Tombstoned by another device's sync: the setting still points at it.
      await (db.update(db.themes)..where((t) => t.id.equals(id))).write(
        const ThemesCompanion(deleted: Value(true)),
      );
      expect((await repo.watchActive().first).id, 'builtin:default');
    });
  });

  group('duplicate', () {
    test('copies a saved theme as "<name> copy"', () async {
      final custom = spec.copyWith(cornerRadius: 11);
      final id = ok(await repo.save(null, 'Mine', custom));
      final copy = ok(await repo.duplicate(id));
      final entry = (await repo.watchAll().first).firstWhere(
        (e) => e.id == copy,
      );
      expect(entry.name, 'Mine copy');
      expect(entry.spec, custom);
    });

    test('copies a built-in, de-duplicating the name', () async {
      final a = ok(await repo.duplicate('builtin:default'));
      final b = ok(await repo.duplicate('builtin:default'));
      final names = {for (final e in await repo.watchAll().first) e.id: e.name};
      expect(names[a], 'Default copy');
      expect(names[b], 'Default copy 2');
    });

    test('unknown id is notFound', () async {
      expect(failureOf(await repo.duplicate('nope')), FailureKind.notFound);
    });
  });

  group('unparseable synced rows', () {
    Future<String> badRow(String json, {String name = 'Bad'}) async {
      final st = await stamp.next();
      await db
          .into(db.themes)
          .insert(
            ThemesCompanion.insert(
              id: st.id,
              clock: st.clock,
              originDevice: st.originDevice,
              localSeq: st.localSeq,
              name: name,
              specJson: json,
            ),
          );
      return st.id;
    }

    const bad = ['not json', '[1,2]', '{"base": 5}', '{"accent": "#12"}'];

    test('watchAll skips them and keeps the good ones', () async {
      final good = ok(await repo.save(null, 'Good', spec));
      for (final j in bad) {
        await badRow(j);
      }
      final ids = (await repo.watchAll().first).map((e) => e.id);
      expect(ids, contains(good));
      expect(ids.length, 4);
    });

    test('duplicate returns invalidInput', () async {
      for (final j in bad) {
        final id = await badRow(j);
        expect(failureOf(await repo.duplicate(id)), FailureKind.invalidInput);
      }
    });

    test('a bad active row falls back to Default', () async {
      for (final j in bad) {
        final id = await badRow(j);
        await repo.setActive(id);
        expect((await repo.watchActive().first).id, 'builtin:default');
      }
    });
  });
}
