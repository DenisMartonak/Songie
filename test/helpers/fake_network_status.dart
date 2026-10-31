import 'dart:async';

import 'package:songies/core/connectivity.dart';

/// Controllable [NetworkStatus] for tests.
class FakeNetworkStatus implements NetworkStatus {
  FakeNetworkStatus([this.kind = NetworkKind.wifi]);

  NetworkKind kind;

  /// When set, [current] throws it (a platform channel that failed).
  Object? currentError;
  final StreamController<NetworkKind> _changes =
      StreamController<NetworkKind>.broadcast(sync: true);

  @override
  Future<NetworkKind> current() async {
    final e = currentError;
    if (e != null) throw e;
    return kind;
  }

  @override
  Stream<NetworkKind> get changes => _changes.stream;

  /// Changes the network and notifies listeners.
  void set(NetworkKind k) {
    kind = k;
    _changes.add(k);
  }

  bool get hasListeners => _changes.hasListener;
}
