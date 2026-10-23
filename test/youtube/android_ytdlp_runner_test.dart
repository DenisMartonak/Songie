import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/android_ytdlp_runner.dart';
import 'package:songies/youtube/ytdlp_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('songies/ytdlp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Future<Object?> Function(MethodCall) h) =>
      messenger.setMockMethodCallHandler(channel, h);

  const lines = EventChannel('songies/ytdlp_lines');

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(lines, null);
  });

  test('onLine gets only its own process lines, in order', () async {
    MockStreamHandlerEventSink? sink;
    bool? streamed;
    messenger.setMockStreamHandler(
      lines,
      MockStreamHandler.inline(onListen: (args, s) => sink = s),
    );
    handle((c) async {
      final id = (c.arguments as Map)['processId'];
      streamed = (c.arguments as Map)['streamLines'] as bool;
      sink!.success({'processId': id, 'line': 'one'});
      sink!.success({'processId': 'other', 'line': 'nope'});
      sink!.success({'processId': id, 'line': 'two'});
      await pumpEventQueue();
      return {'exitCode': 0, 'out': 'one\ntwo\n', 'err': ''};
    });
    final got = <String>[];
    final r = await AndroidYtDlpRunner().run(
      ['x'],
      onLine: got.add,
      processId: 'dl-7',
    );
    expect(got, ['one', 'two']);
    expect(streamed, isTrue);
    expect(r.stdout, 'one\ntwo\n');
  });

  test('uses the given processId and cancel sends it', () async {
    final seen = <MethodCall>[];
    handle((c) async {
      seen.add(c);
      return c.method == 'run' ? {'exitCode': 0, 'out': '', 'err': ''} : null;
    });
    final runner = AndroidYtDlpRunner();
    await runner.run(['x'], processId: 'dl-3');
    await runner.cancel('dl-3');
    expect((seen[0].arguments as Map)['processId'], 'dl-3');
    expect((seen[0].arguments as Map)['streamLines'], isFalse);
    expect(seen[1].method, 'cancel');
    expect((seen[1].arguments as Map)['processId'], 'dl-3');
  });

  test('maps channel result to YtDlpRun and sends args', () async {
    MethodCall? seen;
    handle((c) async {
      seen = c;
      return {'exitCode': 0, 'out': '{"a":1}', 'err': 'WARNING: x'};
    });
    final r = await AndroidYtDlpRunner().run(['-J', 'https://x']);
    expect(r.exitCode, 0);
    expect(r.stdout, '{"a":1}');
    expect(r.stderr, 'WARNING: x');
    expect(seen!.method, 'run');
    expect((seen!.arguments as Map)['args'], ['-J', 'https://x']);
    expect((seen!.arguments as Map)['processId'], isA<String>());
  });

  test(
    'PlatformException becomes exit code -1 with message as stderr',
    () async {
      handle(
        (c) async => throw PlatformException(code: 'boom', message: 'bad'),
      );
      final r = await AndroidYtDlpRunner().run(['-J']);
      expect(r.exitCode, -1);
      expect(r.stderr, contains('bad'));
    },
  );

  test('init failure throws YtDlpMissing', () async {
    handle(
      (c) async =>
          throw PlatformException(code: 'init_failed', message: 'no python'),
    );
    expect(AndroidYtDlpRunner().run(['-J']), throwsA(isA<YtDlpMissing>()));
  });

  test('timeout throws TimeoutException and cancels the process', () async {
    final calls = <String>[];
    handle((c) {
      calls.add(c.method);
      if (c.method == 'run') return Completer<Object?>().future;
      return Future.value(null);
    });
    await expectLater(
      AndroidYtDlpRunner().run([
        '-J',
      ], timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, containsAllInOrder(['run', 'cancel']));
  });

  test('version returns string or null', () async {
    handle((c) async => '2025.10.22');
    expect(await AndroidYtDlpRunner().version(), '2025.10.22');
    handle((c) async => throw PlatformException(code: 'x'));
    expect(await AndroidYtDlpRunner().version(), isNull);
  });

  test('update maps success and failure', () async {
    handle((c) async => 'DONE');
    expect(await AndroidYtDlpRunner().update(), isA<Ok<void>>());
    handle(
      (c) async =>
          throw PlatformException(code: 'update_failed', message: 'offline'),
    );
    final r = await AndroidYtDlpRunner().update();
    expect(r, isA<Err<void>>());
  });
}
