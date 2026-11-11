// Records the website's showcase clips from the real Linux app.
// Run it with tool/showcase.sh, never directly: the script points the app at
// a throwaway data folder, and this test refuses to start without one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/innertube/yt_session_store.dart';
import 'package:songies/main.dart' show runSongies;
import 'package:songies/providers.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/ui/library/pickers.dart';
import 'package:window_manager/window_manager.dart';

import 'demo_library.dart';
import 'isolation.dart';
import 'recorder.dart';

const _allScenes = ['themes', 'playlists', 'downloads', 'search'];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final env = Platform.environment;
  final scenes = (env['SHOWCASE_SCENES'] ?? _allScenes.join(','))
      .split(',')
      .where(_allScenes.contains)
      .toList();

  testWidgets('showcase', (tester) async {
    final problem = isolationProblem(env);
    if (problem != null) fail('Not recording: $problem');
    final out = Directory(env['SHOWCASE_OUT']!);
    final covers = Directory(env['SHOWCASE_COVERS']!);
    final roadTrip = await File('${covers.path}/road-trip.jpg').readAsBytes();

    final c = await runSongies(
      checkForUpdates: false,
      extraOverrides: [
        // "Change cover" gets a picture without a file dialog.
        imagePickerProvider.overrideWithValue(() async => roadTrip),
      ],
    );
    await windowManager.setSize(const Size(1280, 800));
    await windowManager.center();
    await idle(tester, 3);

    // Signed out of everything: nothing can sync into a real account.
    expect(c.read(accountServiceProvider).state, isNot(isA<SignedIn>()));
    expect(c.read(ytAuthProvider), isA<YtSignedOut>());

    final demo = await seedDemoLibrary(c, covers: covers);
    await idle(tester, 4); // covers download and settle
    final rec = FrameRecorder(out);

    for (final scene in scenes) {
      await _goHome(tester);
      switch (scene) {
        case 'themes':
          await themesScene(tester, c, demo, rec);
        case 'playlists':
          await playlistsScene(tester, rec);
        case 'downloads':
          await downloadsScene(tester, rec);
        case 'search':
          await searchScene(tester, rec);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// Lets the app run for [seconds] of real time, drawing as it goes.
Future<void> idle(WidgetTester tester, num seconds) async {
  final end = DateTime.now().add(
    Duration(milliseconds: (seconds * 1000).round()),
  );
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

/// Taps [finder] (the last match, which is the one on top) and waits.
Future<void> tapAndWait(
  WidgetTester tester,
  Finder finder, {
  num seconds = 1.2,
}) async {
  await waitFor(tester, finder);
  await tester.tap(finder.last);
  await idle(tester, seconds);
}

/// Waits up to [timeout] seconds for [finder] to show up.
Future<void> waitFor(WidgetTester tester, Finder finder, {int timeout = 20}) async {
  final end = DateTime.now().add(Duration(seconds: timeout));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await idle(tester, 0.1);
  }
}

Future<void> _goHome(WidgetTester tester) async {
  await tapAndWait(tester, find.text('Home'), seconds: 1.5);
}

/// Themes: a song with a bright cover plays; switch through themes,
/// ending on Album glow, whose colours follow the cover.
Future<void> themesScene(
  WidgetTester tester,
  ProviderContainer c,
  DemoLibrary demo,
  FrameRecorder rec,
) async {
  final song = (await c
      .read(libraryRepositoryProvider)
      .trackById(demo.trackIds['h-zuG75Ds-w']!))!;
  await c.read(playerServiceProvider).playQueue([song]);
  await tapAndWait(tester, find.text('Settings'));
  await tapAndWait(tester, find.text('Themes'), seconds: 2);

  rec.start('themes');
  await idle(tester, 1.5);
  for (final id in [
    demo.themeIds['Songies']!,
    kTerminalThemeId,
    demo.themeIds['Ocean']!,
    kAlbumGlowThemeId,
  ]) {
    await tapAndWait(tester, find.byKey(Key('themes.card.$id')), seconds: 2.2);
  }
  await rec.stop();
}

/// Types [text] into [field] one letter at a time, like a person.
Future<void> typeSlowly(WidgetTester tester, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await idle(tester, 0.09);
  }
}

/// Playlists & covers: make a playlist, add songs, give it a cover.
Future<void> playlistsScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Library'), seconds: 1.5);
  rec.start('playlists');
  await idle(tester, 1);
  await tapAndWait(tester, find.byTooltip('Add'), seconds: 0.8);
  await tapAndWait(tester, find.text('New playlist'), seconds: 0.8);
  await typeSlowly(tester, find.byType(TextField).last, 'Road trip');
  await idle(tester, 0.5);
  await tapAndWait(tester, find.text('Save'), seconds: 1.2);
  await tapAndWait(tester, find.text('Road trip'), seconds: 1.5);
  await tapAndWait(tester, find.byTooltip('More'), seconds: 0.8);
  await tapAndWait(tester, find.text('Add songs'), seconds: 1.2);
  for (final title in ['Blinding Lights', 'Espresso', 'APT.', 'Flowers']) {
    await tapAndWait(tester, find.text(title), seconds: 0.5);
  }
  await tapAndWait(tester, find.textContaining('Add ('), seconds: 1.5);
  await tapAndWait(tester, find.byTooltip('More'), seconds: 0.8);
  await tapAndWait(tester, find.text('Change cover'), seconds: 3);
  await rec.stop();
}

/// Downloads: download a playlist and watch the songs come in.
Future<void> downloadsScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Library'), seconds: 1.5);
  await tapAndWait(tester, find.text('Sunday'), seconds: 2);
  rec.start('downloads');
  await idle(tester, 1.2);
  await tapAndWait(tester, find.byKey(const Key('playlist.download')), seconds: 12);
  await rec.stop();
  // Still frames in case the clip comes out choppy.
  await rec.shot('downloads', 'done');
}

/// Search: type a query and look through the results.
Future<void> searchScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Search'), seconds: 1.2);
  rec.start('search');
  await idle(tester, 0.8);
  final field = find.byKey(const Key('search.field'));
  await tester.tap(field);
  await typeSlowly(tester, field, 'Sabrina Carpenter');
  await idle(tester, 4);
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -350));
  await idle(tester, 2.5);
  await rec.stop();
}
