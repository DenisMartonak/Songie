import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/ui/widgets/artist_link.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              body: ArtistLink(
                text: 'Daft Punk & Pharrell',
                browseId: 'UCdaft',
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

  test('firstArtistName splits on the usual separators', () {
    expect(firstArtistName('A, B'), 'A');
    expect(firstArtistName('A & B'), 'A');
    expect(firstArtistName('A feat. B'), 'A');
    expect(firstArtistName('Simon & Garfunkel Band'), 'Simon');
    expect(firstArtistName('Solo'), 'Solo');
  });
}
