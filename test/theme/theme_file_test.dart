import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/theme/font_service.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/settings/themes/theme_file.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late ThemeRepository themes;
  late FontService fonts;
  late ThemeFiles files;
  late Uint8List fontBytes;

  setUp(() async {
    db = testDb();
    final stamp = await SyncStamp.load(db);
    tmp = await Directory.systemTemp.createTemp('theme_file_test');
    themes = ThemeRepository(db, stamp, SettingsRepository(db));
    fonts = FontService(
      db,
      stamp,
      Directory(p.join(tmp.path, 'fonts')),
      register: (_, _) async {},
    );
    files = ThemeFiles(themes, fonts);
    fontBytes = await File('assets/fonts/Inter-Regular.ttf').readAsBytes();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  ThemeFile decoded(Result<ThemeFile> r) => (r as Ok<ThemeFile>).value;
  String message(Result<Object?> r) => (r as Err<Object?>).failure.message;

  final custom = ThemeSpec.terminal.copyWith(
    accent: const Color(0xFFFF4081),
    cornerRadius: 18,
  );

  group('ThemeFile', () {
    test('round-trips without a font', () {
      final file = ThemeFile(name: 'Pink', spec: custom);
      final json = jsonDecode(utf8.decode(file.encode())) as Map;
      expect(json['songiesTheme'], 1);
      expect(json['name'], 'Pink');
      expect(json['spec'], custom.toJson());
      expect(json.containsKey('font'), isFalse);

      final back = decoded(ThemeFile.decode(file.encode()));
      expect(back.name, 'Pink');
      expect(back.spec, custom);
      expect(back.font, isNull);
    });

    test('round-trips with a font', () {
      final file = ThemeFile(
        name: 'Fancy',
        spec: custom,
        font: ThemeFileFont(family: 'Fancy Sans', ext: 'ttf', bytes: fontBytes),
      );
      final json = jsonDecode(utf8.decode(file.encode())) as Map;
      expect(json['font'], {
        'family': 'Fancy Sans',
        'ext': 'ttf',
        'base64': base64Encode(fontBytes),
      });

      final back = decoded(ThemeFile.decode(file.encode()));
      expect(back.font!.family, 'Fancy Sans');
      expect(back.font!.ext, 'ttf');
      expect(back.font!.bytes, fontBytes);
    });

    List<int> withJson(Object? json) => utf8.encode(jsonEncode(json));
    Map<String, Object?> good() => {
      'songiesTheme': 1,
      'name': 'Pink',
      'spec': custom.toJson(),
    };

    final bad = <String, List<int>>{
      'not JSON': utf8.encode('{"songiesTheme": 1,'),
      'not UTF-8': [0xff, 0xfe, 0x00],
      'a JSON list': withJson([1, 2]),
      'no version': withJson(good()..remove('songiesTheme')),
      'version 2': withJson(good()..['songiesTheme'] = 2),
      'a numeric name': withJson(good()..['name'] = 3),
      'a blank name': withJson(good()..['name'] = '  '),
      'no spec': withJson(good()..remove('spec')),
      'a spec missing a key': withJson(
        good()..['spec'] = (custom.toJson()..remove('accent')),
      ),
      'a bad colour': withJson(
        good()..['spec'] = (custom.toJson()..['accent'] = 'pink'),
      ),
      'an unknown base': withJson(
        good()..['spec'] = (custom.toJson()..['base'] = 'neon'),
      ),
      'a radius out of range': withJson(
        good()..['spec'] = (custom.toJson()..['cornerRadius'] = 99),
      ),
      'a font scale out of range': withJson(
        good()..['spec'] = (custom.toJson()..['fontScale'] = 4),
      ),
      'a font without data': withJson(
        good()..['font'] = {'family': 'X', 'ext': 'ttf'},
      ),
      'a font with a bad extension': withJson(
        good()..['font'] = {'family': 'X', 'ext': 'exe', 'base64': 'AAEAAA=='},
      ),
      'a font with bad base64': withJson(
        good()..['font'] = {'family': 'X', 'ext': 'ttf', 'base64': '***'},
      ),
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test('$key is not a theme file', () {
        expect(message(ThemeFile.decode(value)), notAThemeFile);
      });
    }

    test('names the file after the theme', () {
      expect(
        themeFileName('Night: Blue/Green'),
        'Night_ Blue_Green.songies-theme.json',
      );
      expect(themeFileName('   '), 'theme.songies-theme.json');
    });
  });

  group('ThemeFiles', () {
    test('a built-in font is referenced by family only', () async {
      final file = await files.fileFor(
        const ThemeEntry(
          id: kTerminalThemeId,
          name: 'Terminal',
          spec: ThemeSpec.terminal,
          builtIn: true,
        ),
      );
      expect(file.name, 'Terminal');
      expect(file.spec, ThemeSpec.terminal);
      expect(file.font, isNull);
    });

    test('an imported font is embedded on export', () async {
      final path = p.join(tmp.path, 'Fancy Sans.ttf');
      await File(path).writeAsBytes(fontBytes);
      final family = (await fonts.import(path) as Ok<String>).value;
      final hash = sha256.convert(fontBytes).toString();
      final spec = ThemeSpec.fromJson({
        ...custom.toJson(),
        'fontFamily': family,
        'fontFileHash': hash,
      });

      final file = await files.fileFor(
        ThemeEntry(id: 'x', name: 'Fancy', spec: spec, builtIn: false),
      );
      expect(file.font!.family, 'Fancy Sans');
      expect(file.font!.ext, 'ttf');
      expect(file.font!.bytes, fontBytes);
    });

    test('importing saves the theme with a de-duplicated name', () async {
      await themes.save(null, 'Pink', ThemeSpec.builtInDefault);
      final file = ThemeFile(name: 'Pink', spec: custom);

      final r = await files.import(file.encode());
      final id = (r as Ok<String>).value;
      final saved = (await themes.watchAll().first).firstWhere(
        (e) => e.id == id,
      );
      expect(saved.name, 'Pink 2');
      expect(saved.spec, custom);
    });

    test('an embedded font is imported first and the theme uses it', () async {
      final file = ThemeFile(
        name: 'Fancy',
        spec: custom,
        font: ThemeFileFont(family: 'Fancy Sans', ext: 'ttf', bytes: fontBytes),
      );

      final id = (await files.import(file.encode()) as Ok<String>).value;
      final fontRows = await fonts.watchAll().first;
      expect(fontRows.single.family, 'Fancy Sans');
      final saved = (await themes.watchAll().first).firstWhere(
        (e) => e.id == id,
      );
      expect(saved.spec.fontFamily, 'Fancy Sans');
      expect(saved.spec.fontFileHash, sha256.convert(fontBytes).toString());
      expect(saved.spec.accent, custom.accent);
      // The temporary copy handed to FontService is gone.
      expect(
        Directory.systemTemp.listSync().where(
          (e) => p.basename(e.path).startsWith('songies_theme_font'),
        ),
        isEmpty,
      );
    });

    test('a font that is not a font saves nothing', () async {
      final file = ThemeFile(
        name: 'Broken',
        spec: custom,
        font: ThemeFileFont(
          family: 'Broken',
          ext: 'ttf',
          bytes: Uint8List.fromList(utf8.encode('definitely not a font')),
        ),
      );

      final r = await files.import(file.encode());
      expect(message(r), "That file isn't a font");
      expect(await fonts.watchAll().first, isEmpty);
      expect((await themes.watchAll().first).where((e) => !e.builtIn), isEmpty);
    });

    test('a bad file saves nothing', () async {
      final r = await files.import(utf8.encode('{"hello": "world"}'));
      expect(message(r), notAThemeFile);
      expect((await themes.watchAll().first).where((e) => !e.builtIn), isEmpty);
    });
  });
}
