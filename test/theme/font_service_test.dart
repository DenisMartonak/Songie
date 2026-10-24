import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/theme/font_service.dart';
import 'package:songies/theme/theme_spec.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SyncStamp stamp;
  late Directory tmp;
  late Directory fontsDir;
  late List<(String, int)> registered;
  late FontService service;
  late File fixture;

  FontService build() => FontService(
    db,
    stamp,
    fontsDir,
    register: (family, data) async =>
        registered.add((family, data.single.length)),
  );

  setUp(() async {
    db = testDb();
    stamp = await SyncStamp.load(db);
    tmp = await Directory.systemTemp.createTemp('font_service_test');
    fontsDir = Directory(p.join(tmp.path, 'fonts'));
    registered = [];
    service = build();
    // A real font, read from the bundled assets, copied under a custom name.
    fixture = await File('assets/fonts/Inter-Regular.ttf')
        .copy(p.join(tmp.path, 'Fancy Sans-Regular.ttf'));
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  String family(Result<String> r) => (r as Ok<String>).value;
  Failure failure(Result<String> r) => (r as Err<String>).failure;

  test('importing a font stores a row, a file and registers it', () async {
    final r = await service.import(fixture.path);
    expect(family(r), 'Fancy Sans');

    final rows = await db.select(db.fonts).get();
    expect(rows, hasLength(1));
    expect(rows.single.family, 'Fancy Sans');
    expect(rows.single.ext, 'ttf');
    expect(rows.single.clock, isNotEmpty);
    expect(
      File(p.join(fontsDir.path, '${rows.single.fileHash}.ttf')).existsSync(),
      isTrue,
    );
    expect(registered, [('Fancy Sans', fixture.lengthSync())]);
    expect(service.resolveFamily(_spec('Fancy Sans')), 'Fancy Sans');
  });

  test(
    'the same file again returns the same family without a second row',
    () async {
      final first = family(await service.import(fixture.path));
      final second = family(await service.import(fixture.path));
      expect(second, first);
      expect(await db.select(db.fonts).get(), hasLength(1));
    },
  );

  test('a different file with a taken family gets a numbered name', () async {
    await service.import(fixture.path);
    final other = File(p.join(tmp.path, 'Fancy Sans-Bold.ttf'));
    await other.writeAsBytes([
      ...await fixture.readAsBytes(),
      0, // different hash, same magic bytes
    ]);
    expect(family(await service.import(other.path)), 'Fancy Sans 2');
  });

  test('a family clashing with a bundled one is numbered', () async {
    final clash = await fixture.copy(p.join(tmp.path, 'Inter-Regular.ttf'));
    expect(family(await service.import(clash.path)), 'Inter 2');
  });

  test('a text file renamed to .ttf is rejected', () async {
    final fake = File(p.join(tmp.path, 'Fake.ttf'))
      ..writeAsStringSync('hello, not a font');
    final f = failure(await service.import(fake.path));
    expect(f.kind, FailureKind.invalidInput);
    expect(f.message, "That file isn't a font");
    expect(await db.select(db.fonts).get(), isEmpty);
  });

  test('an 11 MB file is rejected', () async {
    final big = File(p.join(tmp.path, 'Big.ttf'));
    final bytes = Uint8List(11 * 1024 * 1024)..setAll(0, [0, 1, 0, 0]);
    await big.writeAsBytes(bytes);
    final f = failure(await service.import(big.path));
    expect(f.kind, FailureKind.invalidInput);
    expect(f.message, 'Font files must be under 10 MB');
  });

  test('accepts OTTO and true magic bytes, rejects other extensions', () async {
    final otf = File(p.join(tmp.path, 'Cff-Regular.otf'))
      ..writeAsBytesSync([...'OTTO'.codeUnits, 1, 2, 3]);
    expect(family(await service.import(otf.path)), 'Cff');
    final tt = File(p.join(tmp.path, 'Mac.ttf'))
      ..writeAsBytesSync([...'true'.codeUnits, 1, 2, 3]);
    expect(family(await service.import(tt.path)), 'Mac');
    final woff = File(p.join(tmp.path, 'W.woff'))
      ..writeAsBytesSync([0, 1, 0, 0, 1]);
    expect(
      failure(await service.import(woff.path)).kind,
      FailureKind.invalidInput,
    );
  });

  test(
    'loadImported registers stored fonts and skips a missing file',
    () async {
      await service.import(fixture.path);
      final gone = File(p.join(tmp.path, 'Gone-Regular.ttf'))
        ..writeAsBytesSync([0, 1, 0, 0, 9]);
      await service.import(gone.path);
      final goneRow = (await db.select(db.fonts).get()).firstWhere(
        (r) => r.family == 'Gone',
      );
      File(p.join(fontsDir.path, '${goneRow.fileHash}.ttf')).deleteSync();

      registered.clear();
      final fresh = build();
      await fresh.loadImported();
      expect(registered.map((e) => e.$1), ['Fancy Sans']);
      expect(fresh.resolveFamily(_spec('Fancy Sans')), 'Fancy Sans');
      expect(fresh.resolveFamily(_spec('Gone')), 'Inter');
    },
  );

  test('resolveFamily: bundled kept, unknown falls back to Inter', () {
    for (final f in service.bundledFamilies) {
      expect(service.resolveFamily(_spec(f)), f);
    }
    expect(service.resolveFamily(_spec('Nope')), 'Inter');
  });

  test(
    're-importing a known font restores a missing file and registers it',
    () async {
      await service.import(fixture.path);
      final row = (await db.select(db.fonts).get()).single;
      final stored = File(p.join(fontsDir.path, '${row.fileHash}.ttf'))
        ..deleteSync();

      registered.clear();
      final fresh = build();
      expect(family(await fresh.import(fixture.path)), 'Fancy Sans');
      expect(stored.existsSync(), isTrue);
      expect(registered.map((e) => e.$1), ['Fancy Sans']);
      expect(fresh.resolveFamily(_spec('Fancy Sans')), 'Fancy Sans');
      expect(await db.select(db.fonts).get(), hasLength(1));
    },
  );

  test('a registration failure leaves no row and no file', () async {
    final failing = FontService(
      db,
      stamp,
      fontsDir,
      register: (family, data) async => throw Exception('bad font'),
    );
    final f = failure(await failing.import(fixture.path));
    expect(f.kind, FailureKind.invalidInput);
    expect(f.message, "That file isn't a font");
    expect(await db.select(db.fonts).get(), isEmpty);
    expect(!fontsDir.existsSync() || fontsDir.listSync().isEmpty, isTrue);
  });

  test('only a separated style suffix is stripped from the family', () async {
    for (final (name, expected) in [
      ('Twilight', 'Twilight'),
      ('Notebook', 'Notebook'),
      ('Foo-Bold', 'Foo'),
    ]) {
      final f = await fixture.copy(p.join(tmp.path, '$name.ttf'));
      // Distinct bytes per file so each is a new font.
      await f.writeAsBytes([...await fixture.readAsBytes(), ...name.codeUnits]);
      expect(family(await service.import(f.path)), expected);
    }
  });

  test('watchAll emits imported fonts', () async {
    await service.import(fixture.path);
    final all = await service.watchAll().first;
    expect(all.map((e) => e.family), ['Fancy Sans']);
    expect(all.single.ext, 'ttf');
  });
}

ThemeSpec _spec(String fontFamily) =>
    ThemeSpec.builtInDefault.copyWith(fontFamily: fontFamily);
