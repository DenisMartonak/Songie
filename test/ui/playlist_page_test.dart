import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/cover_palette.dart';
import 'package:songies/ui/downloads/download_toggle.dart';
import 'package:songies/ui/motion/equalizer_bars.dart';
import 'package:songies/ui/motion/pressable.dart';
import 'package:songies/ui/motion/shimmer.dart';
import 'package:songies/ui/library/pickers.dart';
import 'package:songies/ui/library/add_songs_sheet.dart';
import 'package:songies/ui/playlist/playlist_page.dart';

import '../helpers/test_db.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(
    WidgetTester tester,
    String playlistId, {
    Size size = const Size(800, 900),
    List<Override> extraOverrides = const [],
    MediaQueryData Function(MediaQueryData)? media,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/playlist/$playlistId',
        routes: [
          GoRoute(
            path: '/playlist/:id',
            builder: (context, state) {
              final page = Scaffold(
                body: PlaylistPage(id: state.pathParameters['id']!),
              );
              if (media == null) return page;
              return MediaQuery(
                data: media(MediaQuery.of(context)),
                child: page,
              );
            },
          ),
          GoRoute(
            path: '/library',
            builder: (_, _) => const Scaffold(body: Text('Library stub')),
          ),
        ],
        extraOverrides: extraOverrides,
      ),
    );
    await settle(tester);
  }

  Future<List<String>> order(WidgetTester tester, String id) =>
      real(tester, () => h.orderOf(id));

  /// Three 200 s songs in a playlist called "Road trip".
  Future<String> threeSongs(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1');
    await h.addTrack('t2');
    await h.addTrack('t3');
    return h.addPlaylist('Road trip', ['t1', 't2', 't3']);
  });

  List<String?> shownTitles(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.textContaining('Song t')))
      t.data,
  ];

  uiTest('shows the header and the rows in position order', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Local playlist'), findsOneWidget);
    expect(find.text('3 songs · 0 h 10 min'), findsOneWidget);
    expect(shownTitles(tester), ['Song t1', 'Song t2', 'Song t3']);
    expect(find.text('3:20'), findsNWidgets(3));
  });

  uiTest('dragging row 3 above row 1 reorders the playlist', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.timedDrag(
      find.byIcon(Icons.drag_handle).at(2),
      const Offset(0, -150),
      const Duration(milliseconds: 600),
    );
    await settle(tester);

    expect(await order(tester, id), ['t3', 't1', 't2']);
    expect(shownTitles(tester), ['Song t3', 'Song t1', 'Song t2']);
  });

  uiTest('swipe-removing a row can be undone to the same place', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t2'), const Offset(-700, 0));
    await settle(tester);
    expect(find.text('Song t2'), findsNothing);
    expect(await order(tester, id), ['t1', 't3']);
    expect(find.text('2 songs · 0 h 6 min'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);
    expect(find.text('Song t2'), findsOneWidget);
  });

  uiTest('swiping a row right adds it to the queue and keeps it', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t2'), const Offset(700, 0));
    await settle(tester);
    expect(find.text('Song t2'), findsOneWidget);
    expect(await order(tester, id), ['t1', 't2', 't3']);
    expect(find.text('Added to queue'), findsOneWidget);
    expect([for (final t in h.player.state.queue) t.id], ['t2']);
  });

  group('cover', () {
    const picked =
        'yt2-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.jpg';

    Future<String?> coverOf(WidgetTester tester, String id) => real(
      tester,
      () async => (await (h.db.select(
        h.db.playlists,
      )..where((p) => p.id.equals(id))).getSingle()).coverRef,
    );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
    }

    uiTest('Change cover stores the picked picture as the cover', (
      tester,
    ) async {
      final id = await threeSongs(tester);
      final art = _FixedArtCache(picked);
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          artCacheProvider.overrideWithValue(art),
          imagePickerProvider.overrideWithValue(
            () async => Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );
      await openMenu(tester);
      expect(find.byKey(const Key('playlist.removeCover')), findsNothing);
      await tester.tap(find.byKey(const Key('playlist.changeCover')));
      await settle(tester);

      expect(art.squareCropped, isTrue);
      expect(await coverOf(tester, id), picked);
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('playlist.removeCover')));
      await settle(tester);
      expect(await coverOf(tester, id), isNull);
    });

    uiTest('a picture that cannot be read says so and keeps the cover', (
      tester,
    ) async {
      final id = await threeSongs(tester);
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          artCacheProvider.overrideWithValue(_FixedArtCache(null)),
          imagePickerProvider.overrideWithValue(
            () async => Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('playlist.changeCover')));
      await settle(tester);
      expect(find.text("Couldn't use that picture"), findsOneWidget);
      expect(await coverOf(tester, id), isNull);
    });

    uiTest('cancelling the picker changes nothing', (tester) async {
      final id = await threeSongs(tester);
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          artCacheProvider.overrideWithValue(_FixedArtCache(picked)),
          imagePickerProvider.overrideWithValue(() async => null),
        ],
      );
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('playlist.changeCover')));
      await settle(tester);
      expect(await coverOf(tester, id), isNull);
    });
  });

  uiTest('undo restores the first and the last row too', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t1'), const Offset(-700, 0));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);

    await tester.drag(find.text('Song t3'), const Offset(-700, 0));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);
  });

  uiTest('tapping a row plays the playlist from that row', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.text('Song t2'));
    // Playing, the row's equalizer keeps animating: no settling.
    await flush(tester);

    final state = h.player.state;
    expect([for (final t in state.queue) t.id], ['t1', 't2', 't3']);
    expect(state.index, 1);
    expect(state.sourcePlaylistId, id);
  });

  uiTest('Play starts at the top unshuffled; Shuffle turns shuffle on', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    h.player.setShuffle(true);
    await pumpPage(tester, id);

    await tester.tap(find.byKey(const Key('playlist.play')));
    await flush(tester);
    expect(h.player.state.shuffle, isFalse);
    expect([for (final t in h.player.state.queue) t.id], ['t1', 't2', 't3']);
    expect(h.player.state.index, 0);
    expect(h.player.state.sourcePlaylistId, id);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Shuffle'));
    await flush(tester);
    expect(h.player.state.shuffle, isTrue);
    expect(h.player.state.queue, hasLength(3));
    expect(h.player.state.sourcePlaylistId, id);
  });

  uiTest('a missing file is tagged, and tapping it still tries to play it', (
    tester,
  ) async {
    final id = await real(tester, () async {
      await h.addTrack('t1');
      await h.addTrack('t2', missing: true);
      return h.addPlaylist('P', ['t1', 't2']);
    });
    await pumpPage(tester, id);

    expect(find.text('File missing'), findsOneWidget);
    expect(find.text('Locate'), findsOneWidget);

    // The player (not the page) decides: it skips a file that is really gone
    // and reports it, and plays one that came back.
    await tester.tap(find.text('Song t2'));
    // Playing, the row's equalizer keeps animating: no settling.
    await flush(tester);
    expect(h.player.state.queue.map((t) => t.id), ['t1', 't2']);
    expect(h.player.state.current?.id, 't2');
    expect(h.backend.sources, ['/music/t2.mp3']);
  });

  uiTest('Locate with the same file only re-imports it', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async => const Ok('t1');
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    expect(h.scanner.imported, ['/new/place.mp3']);
    expect(await order(tester, id), ['t1']);
  });

  uiTest('Locate with a different file swaps the entry track', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      await h.addTrack('t2');
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async => const Ok('t2');
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    expect(await order(tester, id), ['t2']);
    expect(find.text('File missing'), findsNothing);
    expect(find.text('Song t2'), findsOneWidget);
  });

  uiTest('Locate shows a message when the file cannot be imported', (
    tester,
  ) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async =>
        const Err(Failure(FailureKind.invalidInput, 'Empty file'));
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    debugPrint = originalDebugPrint;
    expect(find.text("Couldn't use that file"), findsOneWidget);
    expect(await order(tester, id), ['t1']);
  });

  uiTest('Locate does nothing when the picker is cancelled', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);
    expect(h.scanner.imported, isEmpty);
  });

  uiTest('undo still places the song after its old neighbour when the '
      'neighbours were reordered meanwhile', (tester) async {
    final id = await real(tester, () async {
      for (final t in ['t1', 't2', 't3', 't4']) {
        await h.addTrack(t);
      }
      return h.addPlaylist('P', ['t1', 't2', 't3', 't4']);
    });
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t2'), const Offset(-700, 0));
    await settle(tester);
    // t3 jumps in front of t1: the removed song's neighbours are now out of
    // order (t1 is after t3).
    await real(tester, () async {
      final entries = await h.repo.watchPlaylistTracks(id).first;
      final t1 = entries.firstWhere((e) => e.track.id == 't1').entryId;
      final t3 = entries.firstWhere((e) => e.track.id == 't3').entryId;
      await h.repo.moveEntry(t3, beforeEntryId: t1);
    });
    await settle(tester);
    expect(await order(tester, id), ['t3', 't1', 't4']);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t3', 't1', 't2', 't4']);
    expect(find.text("Couldn't restore the song's position"), findsNothing);
  });

  group('Locate on Android (folder based)', () {
    uiTest('scans the chosen folder and stays quiet when the song is found', (
      tester,
    ) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => FolderPicked('/storage/Music');
      h.scanner.onScan = (folder, name) async* {
        // The scan finds the file by content and repairs its local file row.
        await (h.db.update(h.db.localFiles)
              ..where((f) => f.trackId.equals('t1')))
            .write(const LocalFilesCompanion(state: Value('done')));
        yield const ScanProgress(
          found: 1,
          processed: 1,
          added: 0,
          unchanged: 1,
          skipped: 0,
          done: true,
        );
      };
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);

      expect(h.scanner.scannedFolders, ['/storage/Music']);
      expect(h.scanner.playlistNames, [null]);
      // The folder is only searched: it must not become a library folder.
      expect(h.scanner.registerFolderFlags, [false]);
      expect(h.scanner.imported, isEmpty, reason: 'no single-file import');
      expect(find.text('File missing'), findsNothing);
      expect(find.textContaining("Couldn't find"), findsNothing);
      expect(await order(tester, id), ['t1']);
    });

    uiTest('says so when the song is not in the folder', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => FolderPicked('/storage/Music');
      h.scanner.onScan = (folder, name) => Stream.value(
        const ScanProgress(
          found: 3,
          processed: 3,
          added: 3,
          unchanged: 0,
          skipped: 0,
          done: true,
        ),
      );
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);

      expect(find.text("Couldn't find that song in Music"), findsOneWidget);
      expect(find.text('File missing'), findsOneWidget);
    });

    uiTest('does nothing when the folder picker is cancelled', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);
      expect(h.scanner.scannedFolders, isEmpty);
      expect(h.scanner.imported, isEmpty);
    });

    uiTest('reports a scan that fails', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => FolderPicked('/storage/Music');
      h.scanner.onScan = (folder, name) => Stream.error(StateError('gone'));
      await pumpPage(tester, id);

      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
      await tester.tap(find.text('Locate'));
      await settle(tester);
      debugPrint = originalDebugPrint;

      expect(find.text("Couldn't scan Music"), findsOneWidget);
    });
  });

  uiTest('the playing row shows equalizer bars instead of its number', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);
    expect(find.byType(EqualizerBars), findsNothing);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Song t2'));
    await flush(tester);

    final bars = find.byType(EqualizerBars);
    expect(bars, findsOneWidget);
    expect(tester.widget<EqualizerBars>(bars).playing, isTrue);
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final accent = Theme.of(tester.element(bars))
        .extension<SongiesColors>()!
        .accent;
    expect(tester.widget<Text>(find.text('Song t2')).style!.color, accent);
    expect(
      tester.widget<Text>(find.text('Song t1')).style!.color,
      isNot(accent),
    );

    await real(tester, () => h.player.pause());
    await settle(tester);
    expect(tester.widget<EqualizerBars>(bars).playing, isFalse);
  });

  uiTest('rows are pressable', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);
    expect(
      find.ancestor(of: find.text('Song t1'), matching: find.byType(Pressable)),
      findsOneWidget,
    );
  });

  group('collapsing hero', () {
    Future<String> manySongs(WidgetTester tester) => real(tester, () async {
      final ids = [for (var i = 1; i <= 20; i++) 't$i'];
      for (final t in ids) {
        await h.addTrack(t);
      }
      return h.addPlaylist('Road trip', ids);
    });

    double barTitleOpacity(WidgetTester tester) {
      final title = find.byKey(const Key('playlist.barTitle'));
      if (title.evaluate().isEmpty) return 0;
      return tester
          .widget<Opacity>(
            find.ancestor(of: title, matching: find.byType(Opacity)).first,
          )
          .opacity;
    }

    uiTest('scrolling 300 px pins the title and the Play button in the bar', (
      tester,
    ) async {
      final id = await manySongs(tester);
      await pumpPage(tester, id);
      expect(barTitleOpacity(tester), 0);
      final bar = tester.getRect(find.byKey(const Key('playlist.topBar')));
      final playBefore = tester.getRect(find.byKey(const Key('playlist.play')));
      expect(playBefore.top, greaterThan(bar.bottom));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await settle(tester);

      expect(barTitleOpacity(tester), 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('playlist.barTitle'))).data,
        'Road trip',
      );
      final pinned = tester.getRect(find.byKey(const Key('playlist.play')));
      expect(pinned.center.dy, inInclusiveRange(bar.top, bar.bottom));
      // Still a working Play button.
      await tester.tap(find.byKey(const Key('playlist.play')));
      await flush(tester);
      expect(h.player.state.sourcePlaylistId, id);
      expect(h.player.state.index, 0);
      await real(tester, () => h.player.pause());
    });

    void scrollTo(WidgetTester tester, double offset) => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(offset);

    uiTest('the title stays hidden in the bar until 60 % collapse', (
      tester,
    ) async {
      final id = await manySongs(tester);
      await pumpPage(tester, id);
      const range = playlistHeroCollapseRange;
      scrollTo(tester, range * 0.55);
      await settle(tester);
      expect(barTitleOpacity(tester), 0);

      scrollTo(tester, range * 0.8);
      await settle(tester);
      expect(barTitleOpacity(tester), closeTo(0.5, 0.01));
    });

    uiTest('the cover shrinks and fades as the hero collapses', (tester) async {
      final id = await manySongs(tester);
      await pumpPage(tester, id);
      final cover = find.byKey(const Key('playlist.cover'));
      final before = tester.getSize(cover);
      scrollTo(tester, playlistHeroCollapseRange * 0.3);
      await settle(tester);
      expect(tester.getSize(cover).width, lessThan(before.width));
      final fade = tester.widget<Opacity>(
        find.ancestor(of: cover, matching: find.byType(Opacity)).first,
      );
      expect(fade.opacity, lessThan(1));
    });

    Future<String> coveredPlaylist(WidgetTester tester) =>
        real(tester, () async {
          await h.addTrack('t1');
          final id = await h.addPlaylist('Road trip', ['t1']);
          await (h.db.update(h.db.playlists)..where((p) => p.id.equals(id)))
              .write(const PlaylistsCompanion(coverRef: Value('cover.jpg')));
          return id;
        });

    List<Override> paletteOverrides(CoverPalette palette) => [
      artCacheProvider.overrideWithValue(
        ArtCache(Directory('/nonexistent/songies-art')),
      ),
      artPaletteProvider.overrideWith(
        (ref, art) async => art == 'cover.jpg' ? palette : null,
      ),
    ];

    LinearGradient heroGradient(WidgetTester tester) {
      final hero = tester.widget<DecoratedBox>(
        find.byKey(const Key('playlist.heroBackground')),
      );
      return (hero.decoration as BoxDecoration).gradient! as LinearGradient;
    }

    SongiesColors themeColors(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(PlaylistPage)))
            .extension<SongiesColors>()!;

    uiTest('the hero is a gradient from the cover\'s dominant colour', (
      tester,
    ) async {
      const palette = CoverPalette(
        dominant: Color(0xFF335577),
        vibrant: Color(0xFFE02060),
        muted: Color(0xFF404040),
      );
      final id = await coveredPlaylist(tester);
      await pumpPage(tester, id, extraOverrides: paletteOverrides(palette));
      final gradient = heroGradient(tester);
      final colors = themeColors(tester);
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, [
        playlistHeroTop(palette.dominant, colors),
        colors.background,
      ]);
      // A dark cover colour that already keeps the text readable is used
      // as it is.
      expect(
        playlistHeroTop(const Color(0xFF102030), colors),
        const Color(0xFF102030),
      );
    });

    uiTest('a near-white cover still leaves the hero text readable', (
      tester,
    ) async {
      const palette = CoverPalette(
        dominant: Color(0xFFF6F4EE),
        vibrant: Color(0xFFE02060),
        muted: Color(0xFFDDDDDD),
      );
      final id = await real(tester, () async {
        final ids = [for (var i = 1; i <= 20; i++) 't$i'];
        for (final t in ids) {
          await h.addTrack(t);
        }
        final id = await h.addPlaylist('Road trip', ids);
        await (h.db.update(h.db.playlists)..where((p) => p.id.equals(id)))
            .write(const PlaylistsCompanion(coverRef: Value('cover.jpg')));
        return id;
      });
      await pumpPage(tester, id, extraOverrides: paletteOverrides(palette));
      final top = heroGradient(tester).colors.first;
      final colors = themeColors(tester);
      Color colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.color!;
      expect(
        contrastRatio(colorOf('Road trip'), top),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colorOf('Local playlist'), top),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colorOf('20 songs · 1 h 6 min'), top),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrastRatio(colors.text, top), greaterThanOrEqualTo(4.5));

      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(300);
      await settle(tester);
      final bar = tester.widget<Text>(
        find.byKey(const Key('playlist.barTitle')),
      );
      expect(contrastRatio(bar.style!.color!, top), greaterThanOrEqualTo(4.5));
    });

    uiTest('large text (1.3x) fits a two-line title on a 400 px phone', (
      tester,
    ) async {
      final id = await real(tester, () async {
        await h.db
            .into(h.db.tracks)
            .insert(trackRow(id: 'y1', source: 'yt', ytVideoId: 'vy1'));
        final id = await h.addPlaylist(
          'A very long YouTube playlist name that wraps',
          ['y1'],
        );
        await (h.db.update(
          h.db.playlists,
        )..where((p) => p.id.equals(id))).write(
          const PlaylistsCompanion(
            source: Value('yt'),
            ytPlaylistUrl: Value('https://music.youtube.com/playlist?list=PLx'),
          ),
        );
        return id;
      });
      await pumpPage(
        tester,
        id,
        size: const Size(400, 800),
        media: (m) => m.copyWith(textScaler: const TextScaler.linear(1.3)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1 song · 0 h 0 min'), findsOneWidget);
    });

    uiTest('keeps clear of landscape side insets', (tester) async {
      final id = await threeSongs(tester);
      await pumpPage(
        tester,
        id,
        size: const Size(900, 500),
        media: (m) => m.copyWith(
          padding: const EdgeInsets.only(left: 48, right: 48),
          viewPadding: const EdgeInsets.only(left: 48, right: 48),
        ),
      );
      expect(tester.takeException(), isNull);
      for (final f in [
        find.byKey(const Key('playlist.play')),
        find.byTooltip('More'),
        find.widgetWithText(OutlinedButton, 'Shuffle'),
        find.byKey(const Key('playlist.cover')),
        find.text('3:20').first,
        find.byIcon(Icons.drag_handle).first,
        find.text('1'),
      ]) {
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(48), reason: '$f');
        expect(r.right, lessThanOrEqualTo(900 - 48), reason: '$f');
      }
    });

    uiTest('a 400 px phone fits every hero action without overflow', (
      tester,
    ) async {
      final id = await real(tester, () async {
        await h.db
            .into(h.db.tracks)
            .insert(trackRow(id: 'y1', source: 'yt', ytVideoId: 'vy1'));
        final id = await h.addPlaylist('A long YouTube mix name', ['y1']);
        await (h.db.update(
          h.db.playlists,
        )..where((p) => p.id.equals(id))).write(
          const PlaylistsCompanion(
            source: Value('yt'),
            ytPlaylistUrl: Value('https://music.youtube.com/playlist?list=PLx'),
          ),
        );
        return id;
      });
      await pumpPage(tester, id, size: const Size(400, 800));
      expect(tester.takeException(), isNull);
      for (final f in [
        find.byKey(const Key('playlist.play')),
        find.widgetWithText(OutlinedButton, 'Shuffle'),
        find.byTooltip('More').first,
        find.text('Sync with YouTube'),
        find.byType(DownloadToggle),
      ]) {
        expect(f, findsOneWidget);
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(400));
      }
    });
  });

  group('download switch', () {
    uiTest('a Songies playlist with YouTube songs offers Download, not '
        'Sync', (tester) async {
      final id = await real(tester, () async {
        await h.db
            .into(h.db.tracks)
            .insert(trackRow(id: 'y1', source: 'yt', ytVideoId: 'vy1'));
        return h.addPlaylist('Mine', ['y1']);
      });
      await pumpPage(tester, id);
      expect(find.byType(DownloadToggle), findsOneWidget);
      expect(find.text('Sync with YouTube'), findsNothing);
    });

    uiTest('a playlist of only local files has no Download', (tester) async {
      final id = await real(tester, () async {
        await h.db.into(h.db.tracks).insert(trackRow(id: 'l1'));
        return h.addPlaylist('Files', ['l1']);
      });
      await pumpPage(tester, id);
      expect(find.byType(DownloadToggle), findsNothing);
    });
  });

  group('skeleton rows', () {
    uiTest('a failing entries stream shows a message, not a shimmer', (
      tester,
    ) async {
      final id = await real(tester, () => h.addPlaylist('Broken', []));
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          playlistTracksProvider.overrideWith(
            (ref, _) => Stream<List<PlaylistTrack>>.error(StateError('db')),
          ),
        ],
      );
      // settle() returned: nothing is animating forever.
      expect(find.byType(Shimmer), findsNothing);
      expect(find.text("Couldn't load this playlist"), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    uiTest('an error clears a pending import', (tester) async {
      final id = await real(tester, () => h.addPlaylist('Broken', []));
      final errors = StreamController<List<PlaylistTrack>>()..add(const []);
      addTearDown(errors.close);
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          playlistTracksProvider.overrideWith((ref, _) => errors.stream),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistPage)),
      );
      container.read(pendingImportsProvider.notifier).add(id);
      await tester.pump();
      errors.addError(StateError('db'));
      await flush(tester);
      await settle(tester);
      expect(container.read(pendingImportsProvider), isEmpty);
      expect(find.byType(Shimmer), findsNothing);
    });

    uiTest('an import that brought no entries ends in the empty state', (
      tester,
    ) async {
      final id = await real(tester, () => h.addPlaylist('All unavailable', []));
      // Opened by the import dialog with the id already pending.
      await pumpPage(
        tester,
        id,
        extraOverrides: [
          pendingImportsProvider.overrideWith(() => _SeededPending({id})),
        ],
      );
      expect(find.byType(Shimmer), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('Add songs to get started'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistPage)),
      );
      expect(container.read(pendingImportsProvider), isEmpty);
    });

    uiTest('leaving the page clears its pending import', (tester) async {
      final id = await real(tester, () => h.addPlaylist('Importing', []));
      await pumpPage(tester, id);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistPage)),
      );
      container.read(pendingImportsProvider.notifier).add(id);
      await tester.pump();
      GoRouter.of(tester.element(find.byType(PlaylistPage))).go('/library');
      await flush(tester);
      await settle(tester);
      expect(find.text('Library stub'), findsOneWidget);
      expect(container.read(pendingImportsProvider), isEmpty);
    });

    uiTest('show while an import is pending and the entries are empty', (
      tester,
    ) async {
      final id = await real(tester, () => h.addPlaylist('Importing', []));
      await pumpPage(tester, id);
      expect(find.byKey(const Key('playlist.skeleton')), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistPage)),
      );
      container.read(pendingImportsProvider.notifier).add(id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('playlist.skeleton')), findsNWidgets(8));
      expect(find.text('Add songs to get started'), findsNothing);

      // The entries arrive: rows replace the skeletons, and it is no longer
      // pending.
      // Written from the test clock and pumped along (from the real clock it
      // would wait on database work queued on the test clock).
      final write = h.addTrack('t1').then((_) => h.repo.addTracks(id, ['t1']));
      // The shimmer loops until the rows arrive, so let them arrive first.
      await flush(tester);
      await write;
      await flush(tester);
      await settle(tester);
      expect(find.byKey(const Key('playlist.skeleton')), findsNothing);
      expect(find.text('Song t1'), findsOneWidget);
      expect(container.read(pendingImportsProvider), isEmpty);
    });
  });

  uiTest('a 300 character title stays on one line without overflow', (
    tester,
  ) async {
    final long = 'x' * 300;
    final id = await real(tester, () async {
      await h.addTrack('t1', title: long, artist: 'y' * 300);
      return h.addPlaylist('P', ['t1']);
    });
    await pumpPage(tester, id, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text(long));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  uiTest('rename changes the name; an empty name cannot be saved', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' Holiday ');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Road trip'), findsNothing);
  });

  uiTest('delete asks first, then removes the playlist', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(
      await real(tester, () => h.repo.watchPlaylists().first),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(await real(tester, () => h.repo.watchPlaylists().first), isEmpty);
    expect(find.text('Library stub'), findsOneWidget);
  });

  uiTest('an empty playlist offers Add songs', (tester) async {
    final id = await real(tester, () async {
      return h.addPlaylist('Empty', []);
    });
    await pumpPage(tester, id);

    expect(find.text('0 songs · 0 h 0 min'), findsOneWidget);
    expect(find.text('Add songs to get started'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add songs'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add songs'));
    await settle(tester);
    expect(find.byType(AddSongsSheet), findsOneWidget);
  });

  group('AddSongsSheet', () {
    uiTest('adds the selected songs to the playlist', (tester) async {
      final id = await real(tester, () async {
        await h.addTrack('t1', title: 'Alpha');
        await h.addTrack('t2', title: 'Bravo');
        await h.addTrack('t3', title: 'Charlie');
        return h.addPlaylist('P', ['t1']);
      });
      await pumpPage(tester, id);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Add songs'));
      await settle(tester);

      final none = find.widgetWithText(FilledButton, 'Add (0)');
      expect(tester.widget<FilledButton>(none).onPressed, isNull);
      await tester.tap(find.text('Charlie'));
      await tester.tap(find.text('Bravo'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Add (2)'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add (2)'));
      await settle(tester);

      expect(find.byType(AddSongsSheet), findsNothing);
      expect(await order(tester, id), ['t1', 't3', 't2']);
    });

    uiTest('searching narrows the list and keeps the selection', (
      tester,
    ) async {
      final id = await real(tester, () async {
        await h.addTrack('t1', title: 'Alpha', artist: 'Beyonce');
        await h.addTrack('t2', title: 'Bravo');
        return h.addPlaylist('P', []);
      });
      await pumpPage(tester, id);

      await tester.tap(find.widgetWithText(FilledButton, 'Add songs'));
      await settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);

      await tester.tap(find.text('Bravo'));
      await tester.enterText(find.byType(TextField), 'beyonce');
      await settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Add (1)'), findsOneWidget);
    });
  });
}

/// Pending imports that start with [initial].
class _SeededPending extends PendingImports {
  _SeededPending(this.initial);

  final Set<String> initial;

  @override
  Set<String> build() => initial;
}

/// Stores nothing; answers every put with [ref] (null: undecodable).
class _FixedArtCache extends ArtCache {
  _FixedArtCache(this.ref) : super(Directory('/nonexistent/songies-art'));

  final String? ref;
  bool squareCropped = false;

  @override
  Future<String?> put(Uint8List imageBytes, {bool squareCrop = false}) async {
    squareCropped = squareCrop;
    return ref;
  }
}
