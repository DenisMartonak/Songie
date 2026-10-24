import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/theme/theme_spec.dart';

const _terminal = ThemeEntry(
  id: kTerminalThemeId,
  name: 'Terminal',
  spec: ThemeSpec.terminal,
  builtIn: true,
);

void main() {
  test('returns the active theme\'s spec', () async {
    expect(
      await loadInitialThemeSpec(Stream.value(_terminal)),
      ThemeSpec.terminal,
    );
  });

  test('an error falls back to Default', () async {
    expect(
      await loadInitialThemeSpec(Stream.error(StateError('db closed'))),
      ThemeSpec.builtInDefault,
    );
  });

  test('a stream that closes without a value falls back to Default', () async {
    expect(
      await loadInitialThemeSpec(const Stream.empty()),
      ThemeSpec.builtInDefault,
    );
  });

  test('a stream that never emits falls back to Default after 2 s', () {
    fakeAsync((async) {
      final never = StreamController<ThemeEntry>();
      ThemeSpec? result;
      loadInitialThemeSpec(never.stream).then((s) => result = s);
      async.elapse(const Duration(milliseconds: 1999));
      expect(result, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(result, ThemeSpec.builtInDefault);
      never.close();
    });
  });
}
