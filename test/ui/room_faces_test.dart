import 'package:flutter_test/flutter_test.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/ui/room/room_button.dart';

void main() {
  const host = RoomFace(name: 'denis');
  const ann = RoomFace(name: 'ann');

  test("while hosting, a tag the room doesn't know is the host's", () {
    const f = RoomFaces({'u9': host, 'ua': ann}, untagged: 'u9');
    expect(f.of('ua'), ann);
    expect(f.of(null), host);
    // Left over from an earlier room.
    expect(f.of('old'), host);
  });

  test('as a guest an unknown tag shows no face', () {
    const f = RoomFaces({'u9': host});
    expect(f.of('old'), isNull);
    expect(f.of(null), isNull);
  });
}
