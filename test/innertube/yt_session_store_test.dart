import 'package:flutter_test/flutter_test.dart';
import 'package:songies/innertube/yt_session.dart';

void main() {
  test('sapisid falls back to __Secure-3PAPISID', () {
    expect(YtSession({'SAPISID': 'a', '__Secure-3PAPISID': 'b'}).sapisid, 'a');
    expect(YtSession({'__Secure-3PAPISID': 'b'}).sapisid, 'b');
    expect(YtSession({'X': '1'}).sapisid, isNull);
  });

  test('toString has no cookie values; json round-trips', () {
    final s = YtSession({'SAPISID': 'SECRETVAL', 'SID': 'OTHERSECRET'});
    expect(s.toString(), 'YtSession(2 cookies)');
    expect(s.toString(), isNot(contains('SECRETVAL')));
    final back = YtSession.fromJson(s.toJson());
    expect(back.cookies, s.cookies);
    expect(back.cookieHeader(), 'SAPISID=SECRETVAL; SID=OTHERSECRET');
  });
}
