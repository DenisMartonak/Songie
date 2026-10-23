import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';

void main() {
  test('maps connectivity results to a kind', () {
    NetworkKind k(List<ConnectivityResult> r) => networkKindOf(r);
    expect(k([ConnectivityResult.wifi]), NetworkKind.wifi);
    expect(k([ConnectivityResult.mobile]), NetworkKind.mobile);
    expect(k([ConnectivityResult.ethernet]), NetworkKind.other);
    expect(k([ConnectivityResult.vpn]), NetworkKind.other);
    expect(k([ConnectivityResult.other]), NetworkKind.other);
    expect(k([ConnectivityResult.none]), NetworkKind.offline);
    expect(k([]), NetworkKind.offline);
    expect(
      k([ConnectivityResult.vpn, ConnectivityResult.mobile]),
      NetworkKind.mobile,
    );
    expect(
      k([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      NetworkKind.wifi,
    );
  });
}
