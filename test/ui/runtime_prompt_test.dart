import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/ui/shell/runtime_prompt.dart';

void main() {
  late Future<bool> answer;
  late Completer<Result<String>> install;
  late List<void Function(int, int?)> progress;

  Future<void> open(WidgetTester tester) async {
    install = Completer();
    progress = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = showRuntimePrompt(
              context,
              install: (onProgress) {
                progress.add(onProgress);
                return install.future;
              },
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the copy; Not now answers false', (tester) async {
    await open(tester);
    expect(
      find.text(
        'This song is age-restricted. To play it, Songies needs to download '
        'a small helper (about 45 MB, once).',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets('Download shows progress, then answers true', (tester) async {
    await open(tester);
    await tester.tap(find.text('Download'));
    await tester.pump();
    progress.single(50, 100);
    await tester.pump();
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    install.complete(const Ok('deno 2.5.6 (stable)'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('a failed install shows it, with Retry', (tester) async {
    await open(tester);
    await tester.tap(find.text('Download'));
    await tester.pump();
    install.complete(
      const Err(Failure(FailureKind.network, 'Could not download Deno')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not download Deno'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    install = Completer();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    install.complete(const Ok('deno 2.5.6'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });
}
