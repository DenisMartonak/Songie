import 'package:flutter_test/flutter_test.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/youtube/ytdlp_cookies.dart';

void main() {
  test('netscapeCookies writes one .youtube.com line per cookie', () {
    final text = netscapeCookies(
      YtSession({'SID': 'a', 'SAPISID': 'b'}),
      DateTime.utc(2026, 11, 1),
    );
    expect(
      text,
      '# Netscape HTTP Cookie File\n'
      '.youtube.com\tTRUE\t/\tTRUE\t1825027200\tSID\ta\n'
      '.youtube.com\tTRUE\t/\tTRUE\t1825027200\tSAPISID\tb\n',
    );
  });

  test('an invalid cookie throws without naming it or its value', () {
    expect(
      () => netscapeCookies(
        YtSession({'SECRETNAME': 'secret;value'}),
        DateTime.utc(2026, 11, 1),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => '$e',
          'text',
          allOf(isNot(contains('SECRETNAME')), isNot(contains('secret'))),
        ),
      ),
    );
  });
}
