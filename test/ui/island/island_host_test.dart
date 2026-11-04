import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/island/island_controller.dart';
import 'package:songies/ui/island/island_host.dart';
import 'package:songies/ui/widgets/artwork.dart';

import '../../helpers/ui_harness.dart';

const _island = Key('island');
const _bar = Key('bar');

/// A page with a Go button at the top and a 72 px bar (the anchor) at the
/// bottom, inside an [IslandHost].
Widget _app({
  required void Function(Islands islands) onGo,
  double barHeight = 72,
  bool anchor = true,
  Key? anchorKey,
  bool reduceMotion = false,
  ThemeSpec theme = ThemeSpec.builtInDefault,
}) {
  final sizedBar = SizedBox(key: _bar, height: barHeight);
  return MaterialApp(
    theme: buildThemeData(theme),
    builder: (context, child) {
      final host = IslandHost(child: child!);
      if (!reduceMotion) return host;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: host,
      );
    },
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => onGo(Islands.of(context)),
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
          if (anchor)
            IslandAnchor(key: anchorKey, child: sizedBar)
          else
            sizedBar,
        ],
      ),
    ),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _go(WidgetTester tester) async {
  await tester.tap(find.text('Go'));
  await tester.pumpAndSettle();
}

void main() {
  uiTest('an island appears centred just above the anchor', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await _go(tester);

    final island = tester.getRect(find.byKey(_island));
    final bar = tester.getRect(find.byKey(_bar));
    expect(island.bottom, closeTo(bar.top - 10, 1));
    expect(island.center.dx, closeTo(640, 1));
    expect(island.height, closeTo(38, 1));
    expect(find.text('Hi'), findsOneWidget);
    // The page around it still takes taps.
    expect(find.text('Go').hitTestable(), findsOneWidget);
  });

  uiTest('it pops up from behind the bar', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final island = find.byKey(_island);
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: island, matching: find.byType(ScaleTransition)),
    );
    expect(scale.scale.value, lessThan(1));
    expect(scale.alignment, Alignment.bottomCenter);
    final midway = tester.getRect(island);
    final bar = tester.getRect(find.byKey(_bar));
    expect(midway.bottom, greaterThan(bar.top - 10));

    // Drawn clipped to the area above the bar, so it comes out from behind.
    final clip = find.ancestor(of: island, matching: find.byType(ClipRect));
    expect(clip, findsWidgets);
    expect(tester.getRect(clip.first).bottom, closeTo(bar.top, 1));

    await tester.pumpAndSettle();
    expect(tester.getRect(island).bottom, closeTo(bar.top - 10, 1));
  });

  uiTest('it is black with white text in a light theme too', (tester) async {
    _desktop(tester);
    final light = ThemeSpec.builtInDefault.copyWith(
      base: 'light',
      background: const Color(0xFFFFFFFF),
      surface: const Color(0xFFF0F0F0),
      text: const Color(0xFF111111),
    );
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi'), theme: light));
    await _go(tester);

    final box = tester.widget<Container>(find.byKey(_island));
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF000000));
    final text = tester.widget<Text>(find.text('Hi'));
    expect(text.style?.color, const Color(0xFFFFFFFF));
  });

  uiTest('a song message shows the cover; a failure shows a warning icon', (
    tester,
  ) async {
    _desktop(tester);
    final h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    final song = await real(tester, () async {
      await h.addTrack('t1', title: 'Song one');
      return (h.db.select(h.db.tracks)).getSingle();
    });
    late Islands islands;
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: _app(onGo: (i) => islands = i),
      ),
    );
    await tester.tap(find.text('Go'));
    islands.show('Added to queue', song: song);
    await settle(tester);
    final island = find.byKey(_island);
    expect(
      find.descendant(of: island, matching: find.byType(Artwork)),
      findsOneWidget,
    );

    islands.show('Could not play', kind: IslandKind.failure);
    await settle(tester);
    expect(
      find.descendant(of: island, matching: find.byType(Artwork)),
      findsNothing,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    islands.show('Saved', kind: IslandKind.success);
    await settle(tester);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    islands.show('Note');
    await settle(tester);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
  });

  uiTest('it goes away after 4 s', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await _go(tester);
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.byKey(_island), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsNothing);
  });

  uiTest('tapping it dismisses it; tapping its action runs it and dismisses', (
    tester,
  ) async {
    _desktop(tester);
    var undos = 0;
    await tester.pumpWidget(
      _app(
        onGo: (i) => i.show(
          'Removed',
          action: IslandAction(label: 'Undo', onPressed: () => undos++),
        ),
      ),
    );
    await _go(tester);
    await tester.tap(find.text('Removed'));
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsNothing);
    expect(undos, 0);

    await _go(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undos, 1);
    expect(find.byKey(_island), findsNothing);
  });

  uiTest('swiping it down dismisses it', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await _go(tester);
    await tester.drag(find.byKey(_island), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsNothing);
  });

  uiTest('hovering pauses the countdown', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await _go(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(_island)));
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_island), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.byKey(_island), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsNothing);
    await mouse.removePointer();
  });

  uiTest('a long message wraps to two lines and keeps its action', (
    tester,
  ) async {
    _desktop(tester);
    var signIns = 0;
    await tester.pumpWidget(
      _app(
        onGo: (i) => i.show(
          "Stopped — 3 songs in a row couldn't play. " * 4,
          kind: IslandKind.failure,
          action: IslandAction(label: 'Sign in', onPressed: () => signIns++),
        ),
      ),
    );
    await _go(tester);
    final island = tester.getRect(find.byKey(_island));
    expect(island.height, greaterThan(38));
    expect(island.height, lessThan(70));
    expect(island.width, lessThanOrEqualTo(420));
    final action = tester.getRect(find.text('Sign in'));
    expect(island.contains(action.center), isTrue);
    expect(find.text('Sign in').hitTestable(), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(signIns, 1);
  });

  uiTest('on a phone it is the screen width less 32 at most', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Long words ' * 20)));
    await _go(tester);
    final island = tester.getRect(find.byKey(_island));
    expect(island.width, closeTo(400 - 32, 1));
    expect(island.center.dx, closeTo(200, 1));
  });

  uiTest('three quick messages show only the last', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(
      _app(
        onGo: (i) => i
          ..show('A')
          ..show('B')
          ..show('C'),
      ),
    );
    await _go(tester);
    expect(find.byKey(_island), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
  });

  uiTest('a new message morphs the island in place', (tester) async {
    _desktop(tester);
    late Islands islands;
    await tester.pumpWidget(_app(onGo: (i) => islands = i));
    await tester.tap(find.text('Go'));
    islands.show('Hi');
    await tester.pumpAndSettle();
    final short = tester.getRect(find.byKey(_island));

    islands.show('A much longer message than before');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Still one island, not sinking: it grows towards the new size.
    expect(find.byKey(_island), findsOneWidget);
    final midway = tester.getRect(find.byKey(_island));
    expect(midway.bottom, closeTo(short.bottom, 1));
    await tester.pumpAndSettle();
    final long = tester.getRect(find.byKey(_island));
    expect(midway.width, greaterThan(short.width));
    expect(midway.width, lessThan(long.width));
  });

  uiTest('it stays above the anchor when the anchor moves', (tester) async {
    _desktop(tester);
    void go(Islands i) => i.show('Hi');
    await tester.pumpWidget(_app(onGo: go));
    await _go(tester);
    await tester.pumpWidget(_app(onGo: go, barHeight: 140));
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byKey(_bar));
    expect(bar.top, closeTo(800 - 140, 1));
    expect(
      tester.getRect(find.byKey(_island)).bottom,
      closeTo(bar.top - 10, 1),
    );
  });

  uiTest('with no anchor it rises from the screen bottom', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi'), anchor: false));
    await _go(tester);
    expect(tester.getRect(find.byKey(_island)).bottom, closeTo(800 - 16, 1));
  });

  uiTest('over a dialog it rises from the screen bottom, on top', (
    tester,
  ) async {
    _desktop(tester);
    late BuildContext page;
    await tester.pumpWidget(
      _app(
        onGo: (i) {
          showDialog<void>(
            context: page,
            builder: (_) => const AlertDialog(content: Text('Dialog')),
          );
        },
      ),
    );
    page = tester.element(find.text('Go'));
    await _go(tester);
    expect(find.text('Dialog'), findsOneWidget);
    Islands.of(tester.element(find.text('Dialog'))).show('Hi');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_island)).bottom, closeTo(800 - 16, 1));
    expect(find.text('Hi').hitTestable(), findsOneWidget);
  });

  uiTest('a message survives the page that sent it being popped', (
    tester,
  ) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (_) {}));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Page B')),
      ),
    );
    await tester.pumpAndSettle();
    final islands = Islands.of(tester.element(find.text('Page B')));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page B'), findsNothing);

    islands.show('Hi');
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsOneWidget);
    final bar = tester.getRect(find.byKey(_bar));
    expect(
      tester.getRect(find.byKey(_island)).bottom,
      closeTo(bar.top - 10, 1),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(_island), findsNothing);
  });

  uiTest('an anchor remounted under another route does not take the island', (
    tester,
  ) async {
    _desktop(tester);
    await tester.pumpWidget(_app(onGo: (_) {}, anchorKey: const Key('a')));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Column(
            children: [
              const Expanded(child: Text('Page B')),
              IslandAnchor(child: SizedBox(key: const Key('top'), height: 200)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The page below builds its anchor afresh, so it registers last.
    await tester.pumpWidget(_app(onGo: (_) {}, anchorKey: const Key('b')));
    await tester.pumpAndSettle();
    Islands.of(tester.element(find.text('Page B'))).show('Hi');
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(_island)).bottom,
      closeTo(800 - 200 - 10, 1),
    );
  });

  uiTest('reduced motion fades without scaling', (tester) async {
    _desktop(tester);
    await tester.pumpWidget(
      _app(onGo: (i) => i.show('Hi'), reduceMotion: true),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final island = find.byKey(_island);
    expect(
      find.ancestor(of: island, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.ancestor(of: island, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: island, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byKey(_bar));
    expect(tester.getRect(island).bottom, closeTo(bar.top - 10, 1));
  });

  uiTest('the message is a live region for screen readers', (tester) async {
    _desktop(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(onGo: (i) => i.show('Hi')));
    await _go(tester);
    expect(
      tester.getSemantics(find.text('Hi')),
      isSemantics(label: 'Hi', isLiveRegion: true),
    );
    semantics.dispose();
  });

  uiTest('Islands.of without a host throws a FlutterError naming IslandHost', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      () => Islands.of(context),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.toString(),
          'message',
          contains('IslandHost'),
        ),
      ),
    );
  });
}
