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
import 'package:supabase_flutter/supabase_flutter.dart' show EmptyLocalStorage;
import 'package:window_manager/window_manager.dart';

import 'demo_library.dart';
import 'isolation.dart';
import 'recorder.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final env = Platform.environment;
  final scenes = showcaseScenes(env['SHOWCASE_SCENES']);

  testWidgets('showcase', (tester) async {
    final problem = isolationProblem(env);
    if (problem != null) fail('Not recording: $problem');
    final out = Directory(env['SHOWCASE_OUT']!);
    final covers = Directory(env['SHOWCASE_COVERS']!);
    final roadTrip = await File('${covers.path}/road-trip.jpg').readAsBytes();

    final c = await runSongies(
      checkForUpdates: false,
      // Neither session may come from the keyring, which the test build
      // shares with the real app.
      accountStorage: const EmptyLocalStorage(),
      ytSessionStore: NoYtSessionStore(),
      extraOverrides: [
        // "Change cover" gets a picture without a file dialog.
        imagePickerProvider.overrideWithValue(() async => roadTrip),
      ],
    );
    // A Flutter semantics null check (seen 2026-11-11) would fail the whole
    // run; note it and carry on. The run prints how many there were.
    final semanticsErrors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.stack}'.contains('_RenderObjectSemantics')) {
        semanticsErrors.add('${details.exception}');
        debugPrint('showcase: semantics error ignored: ${details.exception}');
        return;
      }
      previous?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previous;
      debugPrint('showcase: ${semanticsErrors.length} semantics error(s)');
    });
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
      debugPrint('showcase: scene $scene');
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
  await quietTap(tester, finder.last);
  await idle(tester, seconds);
}

/// Waits up to [timeout] seconds for [finder] to show up.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int timeout = 20,
}) async {
  final end = DateTime.now().add(Duration(seconds: timeout));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await idle(tester, 0.1);
  }
}

Future<void> _goHome(WidgetTester tester) async {
  await tapAndWait(tester, find.text('Home'), seconds: 1.5);
}

/// Themes: a song with a bright cover is loaded; three themes, ending on
/// Album glow, whose colours follow the cover.
Future<void> themesScene(
  WidgetTester tester,
  ProviderContainer c,
  DemoLibrary demo,
  FrameRecorder rec,
) async {
  final song = (await c
      .read(libraryRepositoryProvider)
      .trackById(demo.trackIds['h-zuG75Ds-w']!))!;
  final player = c.read(playerServiceProvider);
  await player.playQueue([song]);
  await idle(tester, 3);
  await player.pause();
  await tapAndWait(tester, find.text('Settings'));
  await tapAndWait(tester, find.text('Themes'), seconds: 2);
  var n = 0;
  for (final id in [
    demo.themeIds['Songies']!,
    demo.themeIds['Ocean']!,
    kAlbumGlowThemeId,
  ]) {
    await tapAndWait(tester, find.byKey(Key('themes.card.$id')), seconds: 2);
    await rec.shot('themes', '${++n}');
  }
}

/// Types [text] into [field] one letter at a time, like a person.
Future<void> typeSlowly(WidgetTester tester, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await idle(tester, 0.09);
  }
}

/// Playlists & covers: the library with covers, picking songs for a new
/// playlist, and the playlist with its own cover.
Future<void> playlistsScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Library'), seconds: 1.5);
  await rec.shot('playlists', '1');
  await tapAndWait(tester, find.byTooltip('Add'), seconds: 0.8);
  await tapAndWait(tester, find.text('New playlist'), seconds: 0.8);
  await typeSlowly(tester, find.byType(TextField).last, 'Road trip');
  await tapAndWait(tester, find.text('Save'), seconds: 1.2);
  await tapAndWait(tester, find.text('Road trip'), seconds: 1.5);
  await tapAndWait(tester, find.byTooltip('More'), seconds: 0.8);
  await tapAndWait(tester, find.text('Add songs'), seconds: 1.2);
  for (final title in ['Blinding Lights', 'Espresso', 'APT.', 'Flowers']) {
    await tapAndWait(tester, find.text(title), seconds: 0.4);
  }
  await idle(tester, 0.6);
  await rec.shot('playlists', '2');
  await tapAndWait(tester, find.textContaining('Add ('), seconds: 1.5);
  await tapAndWait(tester, find.byTooltip('More'), seconds: 0.8);
  await tapAndWait(tester, find.text('Change cover'), seconds: 3);
  await rec.shot('playlists', '3');
}

/// Downloads: a playlist downloading, then done.
Future<void> downloadsScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Library'), seconds: 1.5);
  await tapAndWait(tester, find.text('Sunday'), seconds: 2);
  await tapAndWait(
    tester,
    find.byKey(const Key('playlist.download')),
    seconds: 5,
  );
  await rec.shot('downloads', '1');
  // Done when the sidebar no longer says "Downloading".
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (find.textContaining('Downloading').evaluate().isNotEmpty &&
      DateTime.now().isBefore(end)) {
    await idle(tester, 1);
  }
  await idle(tester, 1.5);
  await rec.shot('downloads', '2');
}

/// Search: songs for a query, then its albums.
Future<void> searchScene(WidgetTester tester, FrameRecorder rec) async {
  await tapAndWait(tester, find.text('Search'), seconds: 1.2);
  // Desktop searches from the title bar.
  final field = find.byKey(const Key('shell.search'));
  await waitFor(tester, field);
  await quietTap(tester, field);
  await typeSlowly(tester, field, 'Sabrina Carpenter');
  await idle(tester, 5);
  await rec.shot('search', '1');
  await tapAndWait(tester, find.text('Albums'), seconds: 4);
  await rec.shot('search', '2');
}

// Taps and drags go in as device input. Taps made the usual way
// (tester.tap) make the live test binding paint a crosshair where they
// land, into the app's frames, which would show in the clips.
var _nextPointer = 1000;

Future<void> _asDevice(
  WidgetTester tester,
  Future<void> Function(void Function(PointerEvent)) run,
) async {
  final binding = tester.binding;
  final propagate = binding.shouldPropagateDevicePointerEvents;
  binding.shouldPropagateDevicePointerEvents = true;
  try {
    await run(
      (e) => binding.handlePointerEventForSource(
        e,
        source: TestBindingEventSource.device,
      ),
    );
  } finally {
    binding.shouldPropagateDevicePointerEvents = propagate;
  }
}

/// Taps the middle of [finder] without a tap marker.
Future<void> quietTap(WidgetTester tester, Finder finder) async {
  final at = tester.getCenter(finder);
  final pointer = _nextPointer++;
  await _asDevice(tester, (send) async {
    send(PointerDownEvent(pointer: pointer, position: at));
    await tester.pump(const Duration(milliseconds: 50));
    send(PointerUpEvent(pointer: pointer, position: at));
    await tester.pump();
  });
}

/// Drags from [from] by [by] over about half a second, without a marker.
Future<void> quietDrag(WidgetTester tester, Offset from, Offset by) async {
  final pointer = _nextPointer++;
  const steps = 20;
  await _asDevice(tester, (send) async {
    send(PointerDownEvent(pointer: pointer, position: from));
    for (var i = 1; i <= steps; i++) {
      await idle(tester, 0.025);
      send(
        PointerMoveEvent(
          pointer: pointer,
          position: from + by * (i / steps),
          delta: by / steps.toDouble(),
        ),
      );
    }
    send(PointerUpEvent(pointer: pointer, position: from + by));
    await tester.pump();
  });
}
