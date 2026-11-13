import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/ui/widgets/artist_link.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    String? browseId = 'UCdaft',
    Track? track,
  }) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              body: ArtistLink(
                text: 'Daft Punk & Pharrell',
                browseId: browseId,
                track: track,
                enabled: enabled,
              ),
            ),
          ),
          GoRoute(
            path: '/home/ytm/artist/:id',
            builder: (_, s) =>
                Scaffold(body: Text('artist ${s.pathParameters['id']}')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('ArtistLink tap with a browseId navigates to the artist', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Daft Punk & Pharrell'));
    await settle(tester);
    expect(find.text('artist UCdaft'), findsOneWidget);
  });

  uiTest('ArtistLink disabled does nothing on tap', (tester) async {
    await pump(tester, enabled: false);
    await tester.tap(find.text('Daft Punk & Pharrell'));
    await settle(tester);
    expect(find.text('artist UCdaft'), findsNothing);
  });

  uiTest('two quick taps during a pending lookup open one artist page', (
    tester,
  ) async {
    final gate = h.ytm.radioGate = Completer();
    final track = Track(
      id: 'y1',
      clock: '0000000000001-00000-dev',
      originDevice: 'dev',
      deleted: false,
      unavailable: false,
      localSeq: 1,
      source: 'yt',
      title: 'T',
      artist: 'Daft Punk',
      durationMs: 0,
      searchText: 't',
      ytVideoId: 'vy1',
    );
    await pump(tester, browseId: null, track: track);
    await tester.tap(find.text('Daft Punk & Pharrell'));
    await tester.pump();
    await tester.tap(find.text('Daft Punk & Pharrell'));
    await tester.pump();
    gate.complete(
      Ok(
        const YtmRadio(
          [],
          null,
          current: YtmSong(
            videoId: 'vy1',
            title: 'T',
            artists: [YtmArtistRef(browseId: 'UCdaft', name: 'Daft Punk')],
            durationMs: 1000,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('artist UCdaft'), findsOneWidget);
    // One page was pushed: one Back returns to the link.
    GoRouter.of(tester.element(find.text('artist UCdaft'))).pop();
    await settle(tester);
    expect(find.text('Daft Punk & Pharrell'), findsOneWidget);
    expect(h.ytm.radioCalls, hasLength(1));
  });

  test('firstArtistName splits on the usual separators', () {
    expect(firstArtistName('A, B'), 'A');
    expect(firstArtistName('A & B'), 'A');
    expect(firstArtistName('A feat. B'), 'A');
    expect(firstArtistName('Simon & Garfunkel Band'), 'Simon');
    expect(firstArtistName('Solo'), 'Solo');
  });
}
