// The EU consent sheet: shown once when YouTube asks; Not now keeps search
// and playback working; Accept is remembered on this device for good.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/ytm/consent_sheet.dart';
import 'package:songies/ui/ytm/ytm_song_row.dart';

import '../../helpers/ui_harness.dart';

const _song = YtmSong(videoId: 'vid1', title: 'A song');
const _title = 'YouTube needs you to accept its terms';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/page',
        routes: [
          GoRoute(
            path: '/page',
            builder: (_, _) => const Scaffold(
              body: ConsentListener(child: YtmSongRow(song: _song)),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(YtmSongRow)));

  Future<void> ask(WidgetTester tester) async {
    h.innertube.askForConsent();
    await settle(tester);
  }

  uiTest('YouTube asking shows the sheet once, with Accept and Not now', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text(_title), findsNothing);

    h.innertube
      ..askForConsent()
      ..askForConsent();
    await settle(tester);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  uiTest('Not now closes it; search and playback still work', (tester) async {
    await pumpPage(tester);
    await ask(tester);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(find.text(_title), findsNothing);
    expect(h.innertube.accepts, 0);

    // Not asked again this session.
    await ask(tester);
    expect(find.text(_title), findsNothing);

    // Playback: a song still plays with its radio.
    await tester.tap(find.byKey(const Key('ytm.song.vid1')));
    await settle(tester);
    expect(h.radio.played.map((s) => s.videoId), ['vid1']);

    // Search: still asks YouTube Music.
    h.ytm.answer('daft punk', YtmSearchKind.songs, const [_song]);
    final page = await real(
      tester,
      () => container(tester)
          .read(ytmSearchProvider(('daft punk', YtmSearchKind.songs)).future),
    );
    expect(page.items, hasLength(1));
    expect(h.ytm.calls, [('daft punk', YtmSearchKind.songs)]);
  });

  uiTest('Accept is recorded, reloads the feed and is never asked again', (
    tester,
  ) async {
    await pumpPage(tester);
    await real(tester, () => container(tester).read(ytmHomeProvider.future));
    expect(h.ytm.homeCalls, hasLength(1));

    await ask(tester);
    await tester.tap(find.text('Accept'));
    await settle(tester);
    expect(find.text(_title), findsNothing);
    expect(h.innertube.accepts, 1);
    expect(h.innertube.given, isTrue);
    // The feed is fetched again (now with the consent cookie).
    await real(tester, () => container(tester).read(ytmHomeProvider.future));
    expect(h.ytm.homeCalls, hasLength(2));

    await ask(tester);
    expect(find.text(_title), findsNothing);

    // A fresh app on the same device: still never asked.
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    await ask(tester);
    expect(find.text(_title), findsNothing);
  });
}
