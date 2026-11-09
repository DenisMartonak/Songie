import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/room/room_link_listener.dart';

void main() {
  test('room links call onCode with the code, others are ignored', () {
    fakeAsync((async) {
      final links = StreamController<Uri>();
      final codes = <String>[];
      RoomLinkListener(links.stream, codes.add);
      links.add(Uri.parse('songies://room/ABCD2345'));
      links.add(Uri.parse('https://x/r/wxyz-9876'));
      links.add(Uri.parse('songies://other'));
      async.flushMicrotasks();
      expect(codes, ['ABCD2345', 'WXYZ9876']);
    });
  });

  test('the same link twice within 2 s counts once, after 2 s twice', () {
    fakeAsync((async) {
      final links = StreamController<Uri>();
      final codes = <String>[];
      RoomLinkListener(links.stream, codes.add);
      final uri = Uri.parse('https://x/r/abcd-2345');
      links.add(uri);
      async.elapse(const Duration(milliseconds: 1500));
      links.add(uri);
      async.flushMicrotasks();
      expect(codes, ['ABCD2345']);
      async.elapse(const Duration(milliseconds: 600));
      links.add(uri);
      async.flushMicrotasks();
      expect(codes, ['ABCD2345', 'ABCD2345']);
    });
  });
}
