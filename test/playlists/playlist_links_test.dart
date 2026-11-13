import 'package:flutter_test/flutter_test.dart';
import 'package:songies/playlists/playlist_links.dart';
import 'package:songies/room/room_links.dart' show kRoomSiteBase;

void main() {
  const code = 'ABCDEFGH2345';

  test('a link round-trips', () {
    expect(playlistLink(code), '$kRoomSiteBase/p/$code');
    expect(parsePlaylistCode(playlistLink(code)), code);
  });

  test('app links, site links and bare codes parse', () {
    expect(parsePlaylistCode('songies://playlist/$code'), code);
    expect(
      parsePlaylistCode('https://denismartonak.github.io/Songie/p/$code'),
      code,
    );
    expect(parsePlaylistCode(' abcdefgh2345 '), code);
  });

  test('bad codes and room links give null', () {
    expect(parsePlaylistCode('songies://playlist/ABCDEFGH234I'), isNull);
    expect(parsePlaylistCode('songies://playlist/ABC'), isNull);
    expect(parsePlaylistCode('songies://room/ABCD2345'), isNull);
    expect(parsePlaylistCode('$kRoomSiteBase/r/ABCD2345'), isNull);
    expect(parsePlaylistCode('ABCD2345'), isNull);
    expect(parsePlaylistCode('$kRoomSiteBase/p/$code/extra'), isNull);
  });
}
