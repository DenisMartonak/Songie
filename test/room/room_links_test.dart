import 'package:flutter_test/flutter_test.dart';
import 'package:songies/room/room_links.dart';

void main() {
  test('parses the accepted forms', () {
    expect(
      parseRoomCode('https://denismartonak.github.io/Songie/r/ABCD2345'),
      'ABCD2345',
    );
    expect(
      parseRoomCode('https://denismartonak.github.io/Songie/r/abcd-2345/'),
      'ABCD2345',
    );
    expect(
      parseRoomCode('https://denismartonak.github.io/Songie/r/ABCD2345?utm=x'),
      'ABCD2345',
    );
    expect(parseRoomCode('https://songies.app/r/ABCD2345'), 'ABCD2345');
    expect(parseRoomCode('songies://room/ABCD2345'), 'ABCD2345');
    expect(parseRoomCode('ABCD-2345'), 'ABCD2345');
    expect(parseRoomCode('abcd 2345'), 'ABCD2345');
  });
  test('rejects the rest', () {
    expect(
      parseRoomCode('https://denismartonak.github.io/Songie/r/ABCD2345/extra'),
      isNull,
    );
    expect(
      parseRoomCode('https://denismartonak.github.io/Songie/x/ABCD2345'),
      isNull,
    );
    expect(parseRoomCode('https://x/y'), isNull);
    expect(parseRoomCode('ABC'), isNull);
    expect(parseRoomCode('songies://other/ABCD2345'), isNull);
  });
  test('formats and links', () {
    expect(formatRoomCode('ABCD2345'), 'ABCD-2345');
    expect(
      roomLink('ABCD2345'),
      'https://denismartonak.github.io/Songie/r/ABCD2345',
    );
  });
}
