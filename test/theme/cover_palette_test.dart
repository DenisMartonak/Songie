import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/theme/cover_palette.dart';

Uint8List png(int w, int h, int Function(int x, int y) rgb) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = rgb(x, y);
      im.setPixelRgb(x, y, (c >> 16) & 255, (c >> 8) & 255, c & 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

double deltaHue(Color a, Color b) {
  final ha = Hct.fromInt(a.toARGB32()), hb = Hct.fromInt(b.toARGB32());
  return (ha.hue - hb.hue).abs() + (ha.tone - hb.tone).abs() / 2;
}

void main() {
  late Directory dir;
  late ArtCache art;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('palette');
    art = ArtCache(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void putArt(String ref, [Uint8List? bytes]) =>
      art.fileFor(ref).writeAsBytesSync(bytes ?? png(8, 8, (x, y) => 0x336699));

  CoverPalette pal(int v) =>
      CoverPalette(dominant: Color(v), vibrant: Color(v), muted: Color(v));

  group('extractCoverPalette', () {
    test('red 70% / dark 30% gives a red vibrant, not fallback', () async {
      final bytes = png(100, 100, (x, y) => x < 70 ? 0xd03030 : 0x202020);
      final p = (await extractCoverPalette(bytes))!;
      expect(p.isFallback, isFalse);
      expect(deltaHue(p.vibrant, const Color(0xFFD03030)), lessThan(8));
      expect(p.dominant.toARGB32() & 0xFFFFFF, isNot(0));
    });

    test('pure grey is a fallback', () async {
      final p = (await extractCoverPalette(png(50, 50, (x, y) => 0x808080)))!;
      expect(p.isFallback, isTrue);
    });

    test('pure black and pure white are fallbacks', () async {
      for (final c in [0x000000, 0xffffff]) {
        final p = (await extractCoverPalette(png(50, 50, (x, y) => c)))!;
        expect(p.isFallback, isTrue, reason: c.toRadixString(16));
      }
    });

    test('undecodable bytes give null', () async {
      expect(await extractCoverPalette(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('muted has 40% of the dominant chroma', () async {
      final p = (await extractCoverPalette(png(50, 50, (x, y) => 0xd03030)))!;
      final d = Hct.fromInt(p.dominant.toARGB32());
      final m = Hct.fromInt(p.muted.toARGB32());
      expect(m.chroma, lessThan(d.chroma * 0.6));
    });
  });

  group('JSON', () {
    test('round trips', () {
      final p = CoverPalette(
          dominant: const Color(0xFF112233),
          vibrant: const Color(0xFF445566),
          muted: const Color(0xFF778899),
          isFallback: true);
      expect(CoverPalette.fromJson(p.toJson()), p);
    });
  });

  group('CoverPaletteService', () {
    test('null ref gives null', () async {
      final s = CoverPaletteService(art, extract: (_) async => pal(0xFF000001));
      expect(await s.paletteFor(null), isNull);
    });

    test('second call uses memory; new service reads JSON', () async {
      putArt('a.jpg');
      var calls = 0;
      Future<CoverPalette?> ex(Uint8List _) async {
        calls++;
        return pal(0xFF123456);
      }

      final s = CoverPaletteService(art, extract: ex);
      final first = await s.paletteFor('a.jpg');
      final second = await s.paletteFor('a.jpg');
      expect(calls, 1);
      expect(second, first);
      expect(File('${art.fileFor('a.jpg').path}.palette.json').existsSync(),
          isTrue);

      final s2 = CoverPaletteService(art, extract: ex);
      expect(await s2.paletteFor('a.jpg'), first);
      expect(calls, 1);
    });

    test('missing art file gives null and caches nothing', () async {
      final s = CoverPaletteService(art, extract: (_) async => pal(0xFF000001));
      expect(await s.paletteFor('nope.jpg'), isNull);
      expect(File('${art.fileFor('nope.jpg').path}.palette.json').existsSync(),
          isFalse);
    });

    test('corrupt palette json is re-extracted', () async {
      putArt('a.jpg');
      File('${art.fileFor('a.jpg').path}.palette.json')
          .writeAsStringSync('{bad');
      final s = CoverPaletteService(art, extract: (_) async => pal(0xFF123456));
      expect(await s.paletteFor('a.jpg'), pal(0xFF123456));
    });

    test('extractor returning null caches nothing', () async {
      putArt('a.jpg');
      final s = CoverPaletteService(art, extract: (_) async => null);
      expect(await s.paletteFor('a.jpg'), isNull);
      expect(File('${art.fileFor('a.jpg').path}.palette.json').existsSync(),
          isFalse);
    });

    test('at most one extraction in flight', () async {
      putArt('a.jpg');
      putArt('b.jpg');
      var running = 0, maxRunning = 0;
      final s = CoverPaletteService(art, extract: (_) async {
        maxRunning = ++running > maxRunning ? running : maxRunning;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        running--;
        return pal(0xFF010203);
      });
      await Future.wait([s.paletteFor('a.jpg'), s.paletteFor('b.jpg')]);
      expect(maxRunning, 1);
    });

    test('newest pending request runs next; stale pending ones skip',
        () async {
      for (final r in ['a', 'b', 'c', 'd']) {
        putArt('$r.jpg', png(8, 8, (x, y) => 0x010101 * (r.codeUnitAt(0) - 90)));
      }
      final gate = Completer<void>();
      final started = <int>[];
      final s = CoverPaletteService(art, extract: (bytes) async {
        started.add(bytes.length);
        if (started.length == 1) await gate.future;
        return pal(0xFF010203);
      });
      final fa = s.paletteFor('a.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final fb = s.paletteFor('b.jpg');
      final fc = s.paletteFor('c.jpg');
      final fd = s.paletteFor('d.jpg');
      gate.complete();
      expect(await fa, isNotNull);
      expect(await fd, isNotNull);
      expect(await fb, isNull);
      expect(await fc, isNull);
      expect(started.length, 2);
      // A later request for a stale ref extracts then.
      expect(await s.paletteFor('b.jpg'), isNotNull);
      expect(started.length, 3);
    });

    test('paletteStream: slow A superseded by B emits only B', () async {
      putArt('a.jpg', png(8, 8, (x, y) => 0x111111));
      putArt('b.jpg', png(8, 8, (x, y) => 0x222222));
      final gate = Completer<void>();
      final s = CoverPaletteService(art, extract: (bytes) async {
        final isA = bytes.length == art.fileFor('a.jpg').lengthSync() &&
            _same(bytes, art.fileFor('a.jpg').readAsBytesSync());
        if (isA) await gate.future;
        return pal(isA ? 0xFFAA0000 : 0xFF00BB00);
      });
      final refs = StreamController<String?>();
      final out = <CoverPalette?>[];
      final sub = s.paletteStream(refs.stream).listen(out.add);
      refs.add('a.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      refs.add('b.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(out, [pal(0xFF00BB00)]);
      refs.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(out, [pal(0xFF00BB00), null]);
      await sub.cancel();
      await refs.close();
    });
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
