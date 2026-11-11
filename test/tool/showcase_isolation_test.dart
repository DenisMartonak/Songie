import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/showcase/isolation.dart';

void main() {
  const home = '/home/me';

  test('a throwaway showcase data folder is fine', () {
    expect(
      isolationProblem({'HOME': home, 'XDG_DATA_HOME': '/tmp/showcase-Ab12'}),
      isNull,
    );
  });

  test('no XDG_DATA_HOME would use the real library', () {
    expect(isolationProblem({'HOME': home}), contains('XDG_DATA_HOME'));
    expect(
      isolationProblem({'HOME': home, 'XDG_DATA_HOME': ''}),
      contains('XDG_DATA_HOME'),
    );
  });

  test('the real data folder is refused', () {
    expect(
      isolationProblem({'HOME': home, 'XDG_DATA_HOME': '$home/.local/share'}),
      isNotNull,
    );
  });

  test('a folder not made by tool/showcase.sh is refused', () {
    expect(
      isolationProblem({'HOME': home, 'XDG_DATA_HOME': '/tmp/whatever'}),
      contains('showcase-'),
    );
    expect(
      isolationProblem({'HOME': home, 'XDG_DATA_HOME': 'showcase-rel'}),
      isNotNull,
    );
  });
}
