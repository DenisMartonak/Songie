import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/youtube/share_intents.dart';

class FakeShareSource implements ShareSource {
  FakeShareSource(this.initial);
  final String? initial;
  final controller = StreamController<String>();
  @override
  Future<String?> initialText() async => initial;
  @override
  Stream<String> get texts => controller.stream;
}

void main() {
  test('emits canonical link from initial and later shares', () async {
    final src = FakeShareSource(
      'Check this https://music.youtube.com/playlist?list=PLabc&si=zz',
    );
    final out = <String>[];
    final sub = sharedPlaylistLinks(src).listen(out.add);
    await Future<void>.delayed(Duration.zero);
    src.controller.add('hey https://youtube.com/playlist?list=PLdef');
    await Future<void>.delayed(Duration.zero);
    expect(out, [
      'https://music.youtube.com/playlist?list=PLabc',
      'https://music.youtube.com/playlist?list=PLdef',
    ]);
    await sub.cancel();
  });

  test('text without a playlist link emits nothing', () async {
    final src = FakeShareSource('just words');
    final out = <String>[];
    final sub = sharedPlaylistLinks(src).listen(out.add);
    src.controller.add('https://youtube.com/watch?v=abc');
    await Future<void>.delayed(Duration.zero);
    expect(out, isEmpty);
    await sub.cancel();
  });

  test('null source on non-Android is an empty stream', () async {
    expect(await sharedPlaylistLinks(null).toList(), isEmpty);
  });
}
