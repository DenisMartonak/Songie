import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/runtime_prompter.dart';

void main() {
  test('no handler answers false', () async {
    expect(await RuntimePrompter().ask(), isFalse);
  });

  test('two asks while one is open share it', () async {
    final answer = Completer<bool>();
    var shown = 0;
    final p = RuntimePrompter()
      ..handler = () {
        shown++;
        return answer.future;
      };
    final first = p.ask();
    final second = p.ask();
    answer.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(shown, 1);
  });

  test('a later ask shows it again', () async {
    var shown = 0;
    final p = RuntimePrompter()
      ..handler = () async {
        shown++;
        return false;
      };
    await p.ask();
    await p.ask();
    expect(shown, 2);
  });
}
