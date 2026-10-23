import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkKind { wifi, mobile, other, offline }

/// What kind of network the device is on right now.
abstract class NetworkStatus {
  Future<NetworkKind> current();

  /// Emits whenever the connection changes (event-driven, no polling).
  Stream<NetworkKind> get changes;
}

/// Maps connectivity_plus results (a device can report several) to one kind:
/// Wi-Fi wins, then ethernet (unmetered, `other`), then mobile; VPN and the
/// rest are `other`; nothing is `offline`.
NetworkKind networkKindOf(List<ConnectivityResult> r) {
  if (r.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
  if (r.contains(ConnectivityResult.ethernet)) return NetworkKind.other;
  if (r.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
  final connected = r.any((c) => c != ConnectivityResult.none);
  return connected ? NetworkKind.other : NetworkKind.offline;
}

class ConnectivityPlusStatus implements NetworkStatus {
  ConnectivityPlusStatus([Connectivity? connectivity])
    : _c = connectivity ?? Connectivity();

  final Connectivity _c;

  @override
  Future<NetworkKind> current() async =>
      networkKindOf(await _c.checkConnectivity());

  @override
  // No distinct on the kind: a Wi-Fi to Wi-Fi switch or a VPN toggle changes
  // the IP (which stream URLs are bound to) without changing the kind.
  Stream<NetworkKind> get changes =>
      _c.onConnectivityChanged.map(networkKindOf);
}
