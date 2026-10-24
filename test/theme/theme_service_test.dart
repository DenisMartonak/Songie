import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/app.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/cover_palette.dart';
import 'package:songies/theme/font_service.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_service.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/motion/motion.dart';

import '../helpers/test_db.dart';

const _red = CoverPalette(
  dominant: Color(0xFFB00020),
  vibrant: Color(0xFFE53935),
  muted: Color(0xFF8A5A5A),
);
const _blue = CoverPalette(
  dominant: Color(0xFF0D47A1),
  vibrant: Color(0xFF2979FF),
  muted: Color(0xFF5A6A8A),
);
const _grey = CoverPalette(
  dominant: Color(0xFF777777),
  vibrant: Color(0xFF888888),
  muted: Color(0xFF666666),
  isFallback: true,
);

Track _track(String id, String? artRef) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  artworkRef: artRef,
  unavailable: false,
  searchText: 'title $id',
);

PlayerState _playing(String id, String? artRef) =>
    PlayerState(queue: [_track(id, artRef)], index: 0, playing: true);

/// Palettes by art ref; each lookup waits for the ref's completer when given.
class _FakePalettes extends CoverPaletteService {
  _FakePalettes(this.palettes) : super(ArtCache(Directory.systemTemp));

  final Map<String, CoverPalette?> palettes;
  final Map<String, Completer<void>> gates = {};

  @override
  Future<CoverPalette?> paletteFor(
    String? artRef, {
    bool supersede = true,
  }) async {
    if (artRef == null) return null;
    await gates[artRef]?.future;
    return palettes[artRef];
  }
}

void main() {
  const glow = ThemeSpec.albumGlow;
  const bg = Color(0xFF121212);

  group('songiesColorsFor', () {
    test('follow cover on with a red palette takes its colours from red', () {
      final c = songiesColorsFor(glow, palette: _red);
      expect(c.accent, ensureAccentContrast(_red.vibrant, bg));
      expect(c.glow, _red.vibrant.withValues(alpha: glow.glowStrength));
      expect(
        c.miniPlayer,
        Color.alphaBlend(_red.vibrant.withValues(alpha: 0.3), glow.surface),
      );
      expect(c.nowPlayingTop, Color.lerp(_red.dominant, Colors.black, 0.55));
      expect(c.nowPlayingBottom, bg);
    });

    test('follow cover off keeps the theme accent', () {
      final c = songiesColorsFor(ThemeSpec.builtInDefault, palette: _red);
      expect(c.accent, ThemeSpec.builtInDefault.accent);
      expect(c, SongiesColors.fromSpec(ThemeSpec.builtInDefault));
    });

    test('a fallback (greyscale) palette keeps the theme accent', () {
      expect(
        songiesColorsFor(glow, palette: _grey),
        SongiesColors.fromSpec(glow),
      );
    });

    test('no palette keeps the theme accent', () {
      final c = songiesColorsFor(glow);
      expect(c.accent, glow.accent);
      expect(c.glow, glow.accent.withValues(alpha: glow.glowStrength));
      expect(c.nowPlayingTop, Color.lerp(glow.accent, Colors.black, 0.55));
    });

    test('the resolved font family is carried', () {
      expect(songiesColorsFor(glow, fontFamily: 'Inter').fontFamily, 'Inter');
      expect(songiesColorsFor(glow).fontFamily, 'Outfit');
    });
  });

  group('songiesColorsProvider', () {
    late StreamController<PlayerState> states;
    late _FakePalettes palettes;
    late ProviderContainer container;

    ProviderContainer make(ThemeSpec spec) => ProviderContainer(
      overrides: [
        themeSpecProvider.overrideWithValue(spec),
        resolvedFontFamilyProvider.overrideWithValue(spec.fontFamily),
        playerStateProvider.overrideWith((ref) => states.stream),
        coverPaletteServiceProvider.overrideWithValue(palettes),
      ],
    );

    setUp(() {
      states = StreamController<PlayerState>();
      palettes = _FakePalettes({'red.jpg': _red, 'blue.jpg': _blue});
    });

    tearDown(() {
      container.dispose();
      // Not awaited: a stream nobody listened to never finishes closing.
      unawaited(states.close());
    });

    Future<void> idle() => pumpEventQueue();

    test('follows the playing track\'s cover', () async {
      container = make(glow);
      final sub = container.listen(songiesColorsProvider, (_, _) {});
      states.add(_playing('a', 'red.jpg'));
      await idle();
      expect(sub.read().accent, ensureAccentContrast(_red.vibrant, bg));

      states.add(_playing('b', 'blue.jpg'));
      await idle();
      expect(sub.read().accent, ensureAccentContrast(_blue.vibrant, bg));

      states.add(_playing('c', null));
      await idle();
      expect(sub.read().accent, glow.accent);
    });

    test('a skipped-past song\'s colours are never applied', () async {
      container = make(glow);
      final seen = <Color>[];
      container.listen(
        songiesColorsProvider,
        (_, next) => seen.add(next.accent),
        fireImmediately: true,
      );
      palettes.gates['red.jpg'] = Completer<void>();
      states.add(_playing('a', 'red.jpg'));
      await idle();
      states.add(_playing('b', 'blue.jpg'));
      await idle();
      palettes.gates['red.jpg']!.complete();
      await idle();
      expect(seen, isNot(contains(ensureAccentContrast(_red.vibrant, bg))));
      expect(seen.last, ensureAccentContrast(_blue.vibrant, bg));
    });

    test('follow cover off never asks for a palette', () async {
      container = make(ThemeSpec.builtInDefault);
      final sub = container.listen(songiesColorsProvider, (_, _) {});
      states.add(_playing('a', 'red.jpg'));
      await idle();
      expect(sub.read().accent, ThemeSpec.builtInDefault.accent);
      expect(container.exists(coverPaletteProvider), isFalse);
    });
  });

  group('themeSpecProvider', () {
    test('shows the preloaded theme until the active one emits', () async {
      final active = StreamController<ThemeEntry>();
      addTearDown(active.close);
      final container = ProviderContainer(
        overrides: [
          initialThemeSpecProvider.overrideWithValue(ThemeSpec.terminal),
          activeThemeProvider.overrideWith((ref) => active.stream),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(themeSpecProvider, (_, _) {});
      expect(sub.read(), ThemeSpec.terminal);
      active.add(
        const ThemeEntry(
          id: kAlbumGlowThemeId,
          name: 'Album glow',
          spec: ThemeSpec.albumGlow,
          builtIn: true,
        ),
      );
      await pumpEventQueue();
      expect(sub.read(), ThemeSpec.albumGlow);
    });

    test('a missing imported font resolves to Inter', () async {
      final db = testDb();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          themeSpecProvider.overrideWithValue(
            ThemeSpec.builtInDefault.copyWith(fontFamily: 'Not Installed'),
          ),
          fontServiceProvider.overrideWithValue(
            FontService(db, await SyncStamp.load(db), Directory.systemTemp),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(resolvedFontFamilyProvider), 'Inter');
      expect(container.read(songiesColorsProvider).fontFamily, 'Inter');
    });
  });

  group('reduceMotionProvider', () {
    late AppDatabase db;
    setUp(() => db = testDb());
    tearDown(() => db.close());

    test('follows the reduce_motion setting', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(reduceMotionProvider, (_, _) {});
      await pumpEventQueue();
      expect(sub.read(), isFalse);
      await SettingsRepository(db).setBool(kReduceMotion, true);
      await pumpEventQueue();
      expect(sub.read(), isTrue);
    });
  });

  group('SongiesApp', () {
    late StreamController<PlayerState> states;
    late _FakePalettes palettes;

    setUp(() {
      states = StreamController<PlayerState>.broadcast();
      palettes = _FakePalettes({'red.jpg': _red, 'blue.jpg': _blue});
    });
    tearDown(() => states.close());

    Future<void> pumpApp(
      WidgetTester tester, {
      ThemeSpec spec = ThemeSpec.albumGlow,
      bool reduceMotion = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeSpecProvider.overrideWithValue(spec),
            resolvedFontFamilyProvider.overrideWithValue(spec.fontFamily),
            playerStateProvider.overrideWith((ref) => states.stream),
            coverPaletteServiceProvider.overrideWithValue(palettes),
            reduceMotionProvider.overrideWithValue(reduceMotion),
          ],
          child: SongiesApp(
            router: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) =>
                      const Scaffold(body: Text('probe', key: Key('probe'))),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    SongiesColors colorsNow(WidgetTester tester) =>
        Theme.of(tester.element(find.byKey(const Key('probe'))))
            .extension<SongiesColors>()!;

    Future<void> play(WidgetTester tester, String id, String ref) async {
      states.add(_playing(id, ref));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('changing track tweens the colours over 600 ms', (
      tester,
    ) async {
      await pumpApp(tester);
      await play(tester, 'a', 'red.jpg');
      await tester.pumpAndSettle();
      final red = ensureAccentContrast(_red.vibrant, bg);
      final blue = ensureAccentContrast(_blue.vibrant, bg);
      expect(colorsNow(tester).accent, red);

      await play(tester, 'b', 'blue.jpg');
      await tester.pump(Motion.colour ~/ 2);
      final mid = colorsNow(tester).accent;
      expect(mid, isNot(red));
      expect(mid, isNot(blue));
      expect(mid.r, inExclusiveRange(blue.r, red.r));

      await tester.pump(Motion.colour ~/ 2);
      expect(colorsNow(tester).accent, blue);
      // Settled: nothing keeps ticking.
      await tester.pump(Motion.quick);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with reduced motion the colours change at once', (
      tester,
    ) async {
      await pumpApp(tester, reduceMotion: true);
      await play(tester, 'a', 'red.jpg');
      await tester.pump();
      expect(colorsNow(tester).accent, ensureAccentContrast(_red.vibrant, bg));
      await play(tester, 'b', 'blue.jpg');
      await tester.pump();
      expect(colorsNow(tester).accent, ensureAccentContrast(_blue.vibrant, bg));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('fontScale 1.2 scales text by 1.2x', (tester) async {
      await pumpApp(
        tester,
        spec: ThemeSpec.builtInDefault.copyWith(fontScale: 1.2),
      );
      final scaler = MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('probe'))),
      );
      expect(scaler.scale(10), closeTo(12, 0.0001));
    });
  });
}
