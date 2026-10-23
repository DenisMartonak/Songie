import 'dart:async';

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

  test('changes emits on every event, even with an unchanged kind', () async {
    final events = StreamController<List<ConnectivityResult>>();
    final status = ConnectivityPlusStatus(_FakeConnectivity(events.stream));
    final seen = <NetworkKind>[];
    final sub = status.changes.listen(seen.add);
    events
      ..add([ConnectivityResult.wifi])
      ..add([ConnectivityResult.wifi])
      ..add([ConnectivityResult.wifi, ConnectivityResult.vpn]);
    await pumpEventQueue();
    await sub.cancel();
    await events.close();
    expect(seen, [NetworkKind.wifi, NetworkKind.wifi, NetworkKind.wifi]);
  });
}

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this._stream);
  final Stream<List<ConnectivityResult>> _stream;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [];
}
