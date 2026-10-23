import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/shell/window_controls.dart';
import 'package:songies/ui/widgets/page_surface.dart';

import '../helpers/fake_audio_backend.dart';

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

const _playlists = [
  PlaylistSummary(
    id: 'p1',
    name: 'Gym Mix',
    source: 'local',
    trackCount: 12,
    durationMs: 0,
    coverRef: null,
  ),
];

/// Whether the nearest Material above [of] sits below the nearest Navigator,
/// i.e. ink painted by [of] lands on the page's own surface, not on the
/// shell's, so it goes away with the page.
bool _inkIsOnThePage(Finder of) {
  final element = of.evaluate().first;
  var sawMaterial = false;
  var sawNavigator = false;
  element.visitAncestorElements((e) {
    if (e.widget is Material && !sawNavigator) sawMaterial = true;
    if (e.widget is Navigator) {
      sawNavigator = true;
      return false;
    }
    return true;
  });
  return sawMaterial && sawNavigator;
}

void main() {
  testWidgets('pages paint ink on their own surface, not the shell\'s', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerServiceProvider.overrideWithValue(
            PlayerService(FakeAudioBackend(), _Resolver()),
          ),
          playlistsProvider.overrideWith((ref) => Stream.value(_playlists)),
          recentPlaylistIdsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          recentTracksProvider.overrideWith((ref) => Stream.value(const [])),
          libraryFoldersProvider.overrideWith((ref) => Stream.value(const [])),
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          deviceIdProvider.overrideWithValue('0123456789abcdef'),
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          windowControlsProvider.overrideWithValue(_NoWindow()),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_inkIsOnThePage(find.byType(HomePage)), isTrue);
    expect(
      _inkIsOnThePage(
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(InkWell),
            )
            .first,
      ),
      isTrue,
    );
    expect(find.byType(PageSurface), findsOneWidget);

    router.push('/home/playlist/p1');
    await tester.pumpAndSettle();
    expect(_inkIsOnThePage(find.byType(PlaylistPage)), isTrue);

    router.go('/settings');
    await tester.pumpAndSettle();
    expect(_inkIsOnThePage(find.byType(SettingsPage)), isTrue);
  });

  testWidgets('PageSurface paints the theme background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(ThemeSpec.builtInDefault),
        home: const PageSurface(child: SizedBox()),
      ),
    );
    final colors = Theme.of(tester.element(find.byType(PageSurface)))
        .extension<SongiesColors>()!;
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(PageSurface),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, colors.background);
  });
}

class _NoWindow implements WindowControls {
  @override
  Future<void> minimize() async {}
  @override
  Future<void> maximizeOrRestore() async {}
  @override
  Future<void> close() async {}
  @override
  Future<bool> isMaximized() async => false;
  @override
  Stream<bool> get maximizedChanges => const Stream.empty();
}
