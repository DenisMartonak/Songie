import 'package:flutter_test/flutter_test.dart';
import 'package:songies/stats/main_artist.dart';

void main() {
  String yt(String a) => mainArtist(a, youtube: true);
  String local(String a) => mainArtist(a, youtube: false);

  test('YouTube artists split on the first comma only', () {
    expect(yt('Daft Punk, Pharrell Williams'), 'Daft Punk');
    expect(yt('Simon & Garfunkel'), 'Simon & Garfunkel');
    expect(yt('Daft Punk feat. Pharrell'), 'Daft Punk feat. Pharrell');
  });

  test('local artists split on the listed separators', () {
    expect(local('Daft Punk feat. Pharrell'), 'Daft Punk');
    expect(local('A ft B'), 'A');
    expect(local('A ft. B'), 'A');
    expect(local('A feat B'), 'A');
    expect(local('A FEATURING B'), 'A');
    expect(local('A; B'), 'A');
    expect(local('A / B'), 'A');
    expect(local('A, B'), 'A');
  });

  test('bracketed featuring forms cut at the bracket', () {
    expect(local('A (feat. B)'), 'A');
    expect(local('A [feat. B]'), 'A');
    expect(local('A (ft. B)'), 'A');
    expect(local('A (featuring B)'), 'A');
  });

  test('ampersand, plus and x are never separators', () {
    expect(local('Florence + the Machine'), 'Florence + the Machine');
    expect(local('A & B'), 'A & B');
    expect(local('A x B'), 'A x B');
  });

  test('a comma inside a band name splits (documented trade-off)', () {
    expect(local('Earth, Wind & Fire'), 'Earth');
  });

  test('blank input gives an empty string', () {
    expect(local('  '), '');
    expect(yt(''), '');
  });
}
