import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/username.dart';

void main() {
  test('usernameProblem accepts den_cho.1 and rejects ab, .abc, abc., ABC!, 21+ chars', () {
    expect(usernameProblem('den_cho.1'), isNull);
    expect(usernameProblem('abc'), isNull);
    expect(usernameProblem('a' * 20), isNull);
    for (final bad in ['ab', '.abc', 'abc.', 'ABC!', 'a' * 21, '', 'a b c']) {
      expect(usernameProblem(bad), kUsernameHint, reason: bad);
    }
    expect(kUsernameHint, '3–20 letters, numbers, _ or .');
  });

  test('normalizeUsername trims and lowercases', () {
    expect(normalizeUsername('  Den_Cho '), 'den_cho');
  });

  test('passwordProblem wants at least 8 characters', () {
    expect(passwordProblem('1234567'), kPasswordHint);
    expect(passwordProblem('12345678'), isNull);
    expect(kPasswordHint, 'At least 8 characters');
  });
}
