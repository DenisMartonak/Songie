import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/island/island_controller.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  test('show sets current and dismisses after its duration', () {
    fakeAsync((async) {
      final c = IslandController();
      c.show(const IslandMessage(text: 'Hi'));
      async.elapse(const Duration(milliseconds: 3999));
      expect(c.current?.text, 'Hi');
      async.elapse(ms);
      expect(c.current, isNull);
      c.dispose();
    });
  });

  test('a new message replaces the current one and restarts the timer', () {
    fakeAsync((async) {
      final c = IslandController();
      c.show(const IslandMessage(text: 'A'));
      final before = c.serial;
      async.elapse(const Duration(seconds: 3));
      c.show(const IslandMessage(text: 'B'));
      expect(c.serial, greaterThan(before));
      async.elapse(const Duration(seconds: 3));
      expect(c.current?.text, 'B');
      async.elapse(const Duration(seconds: 1));
      expect(c.current, isNull);
      c.dispose();
    });
  });

  test('a custom duration is kept', () {
    fakeAsync((async) {
      final c = IslandController();
      c.show(
        const IslandMessage(text: 'Hi', duration: Duration(seconds: 2)),
      );
      async.elapse(const Duration(milliseconds: 1999));
      expect(c.current, isNotNull);
      async.elapse(ms);
      expect(c.current, isNull);
      c.dispose();
    });
  });

  test('pause holds the message; resume restarts the full duration', () {
    fakeAsync((async) {
      final c = IslandController();
      c.show(const IslandMessage(text: 'Hi'));
      async.elapse(const Duration(seconds: 3));
      c.pause();
      async.elapse(const Duration(seconds: 10));
      expect(c.current, isNotNull);
      c.resume();
      async.elapse(const Duration(milliseconds: 3999));
      expect(c.current, isNotNull);
      async.elapse(ms);
      expect(c.current, isNull);
      c.dispose();
    });
  });

  test('runAction calls the action then dismisses', () {
    fakeAsync((async) {
      final c = IslandController();
      var calls = 0;
      c.show(
        IslandMessage(
          text: 'Hi',
          action: IslandAction(label: 'Undo', onPressed: () => calls++),
        ),
      );
      c.runAction();
      expect(calls, 1);
      expect(c.current, isNull);
      c.dispose();
    });
  });

  test('dismiss clears and notifies listeners', () {
    fakeAsync((async) {
      final c = IslandController();
      c.show(const IslandMessage(text: 'Hi'));
      var notified = 0;
      c.addListener(() => notified++);
      c.dismiss();
      expect(c.current, isNull);
      expect(notified, 1);
      c.dispose();
    });
  });

  test('five messages in a row leave only the last', () {
    fakeAsync((async) {
      final c = IslandController();
      for (var i = 1; i <= 5; i++) {
        c.show(IslandMessage(text: 'm$i'));
      }
      expect(c.current?.text, 'm5');
      async.elapse(const Duration(seconds: 4));
      expect(c.current, isNull);
      c.dispose();
    });
  });
}
