import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart' as bonsoir;

import '../core/log.dart';

/// The mDNS service type Songies advertises and browses for.
const syncServiceType = '_songies._tcp';

/// Another Songies device seen on the network.
class FoundDevice {
  const FoundDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.pairing,
  });

  final String id;
  final String name;
  final String host;
  final int port;

  /// Whether it shows a pairing code right now.
  final bool pairing;

  @override
  String toString() =>
      'FoundDevice($name, $host:$port${pairing ? ', pairing' : ''})';
}

/// Advertises this device and browses for others (while Sync devices is
/// open). TXT record: `id`, `name`, `port`, `pairing` (`"1"` or `"0"`). The
/// pairing code itself is never advertised.
abstract class Discovery {
  /// Advertises this device, replacing any earlier advertisement (so a
  /// changed [pairing] re-advertises).
  Future<void> advertise({
    required String id,
    required String name,
    required int port,
    required bool pairing,
  });

  Future<void> stopAdvertising();

  /// Every device seen, as a whole list each time it changes. This device's
  /// own advertisement is left out.
  Stream<List<FoundDevice>> get found;

  Future<void> startBrowsing();

  /// Stops advertising and browsing and closes [found].
  Future<void> dispose();
}

/// [Discovery] over the platform's mDNS (Android NSD, Avahi, Bonjour, DNS-SD
/// on Windows), through bonsoir. The service instance name is the device id,
/// so it is unique and a lost event names the device it removes.
class BonsoirDiscovery implements Discovery {
  BonsoirDiscovery();

  final _found = StreamController<List<FoundDevice>>.broadcast();
  final _devices = <String, FoundDevice>{};
  bonsoir.BonsoirBroadcast? _broadcast;
  bonsoir.BonsoirDiscovery? _browser;
  StreamSubscription<bonsoir.BonsoirDiscoveryEvent>? _events;
  String? _ownId;

  /// Serialises broadcast changes: one platform broadcast at a time.
  Future<void> _queue = Future.value();

  @override
  Stream<List<FoundDevice>> get found => _found.stream;

  @override
  Future<void> advertise({
    required String id,
    required String name,
    required int port,
    required bool pairing,
  }) => _serial(() async {
    _ownId = id;
    await _stopBroadcast();
    final b = bonsoir.BonsoirBroadcast(
      printLogs: false,
      service: bonsoir.BonsoirService(
        name: id,
        type: syncServiceType,
        port: port,
        attributes: {
          'id': id,
          'name': name,
          'port': '$port',
          'pairing': pairing ? '1' : '0',
        },
      ),
    );
    // Kept only once initialised: stopping one that failed to initialise
    // throws on some platforms (Linux without Avahi).
    await b.initialize();
    _broadcast = b;
    await b.start();
  });

  @override
  Future<void> stopAdvertising() => _serial(_stopBroadcast);

  Future<void> _stopBroadcast() async {
    final b = _broadcast;
    _broadcast = null;
    if (b == null || b.isStopped) return;
    try {
      await b.stop();
    } catch (e) {
      AppLog.w('Stopping the mDNS broadcast failed', e);
    }
  }

  @override
  Future<void> startBrowsing() async {
    if (_browser != null) return;
    final d = bonsoir.BonsoirDiscovery(printLogs: false, type: syncServiceType);
    await d.initialize();
    _browser = d;
    _events = d.eventStream?.listen(
      (e) => _onEvent(d, e),
      onError: (Object e) => AppLog.w('mDNS browsing failed', e),
    );
    await d.start();
  }

  void _onEvent(bonsoir.BonsoirDiscovery d, bonsoir.BonsoirDiscoveryEvent e) {
    switch (e) {
      case bonsoir.BonsoirDiscoveryServiceFoundEvent(:final service):
        // Addresses and TXT come with the resolved event.
        d.serviceResolver.resolveService(service);
      case bonsoir.BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          bonsoir.BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final f = _parse(service);
        _devices.remove(service.name);
        if (f != null) {
          // One entry per device: a renamed instance replaces the old one.
          _devices.removeWhere((_, d) => d.id == f.id);
          _devices[service.name] = f;
        }
        _publish();
      case bonsoir.BonsoirDiscoveryServiceLostEvent(:final service):
        if (_devices.remove(service.name) != null) _publish();
      default:
        break;
    }
  }

  /// The device a resolved service describes, or null when it is not a
  /// usable Songies advertisement (or is this device's own).
  FoundDevice? _parse(bonsoir.BonsoirService s) {
    final a = s.attributes;
    final id = a['id'];
    if (id == null || id.isEmpty || id == _ownId) return null;
    final host = _ipv4(s.hostAddresses);
    if (host == null) return null;
    return FoundDevice(
      id: id,
      name: a['name'] ?? id,
      host: host,
      port: s.port,
      pairing: a['pairing'] == '1',
    );
  }

  /// The first IPv4 address: [SyncClient] builds `https://host:port` URLs,
  /// which a bare IPv6 address would break.
  static String? _ipv4(List<String> addresses) {
    for (final a in addresses) {
      final ip = InternetAddress.tryParse(a);
      if (ip != null && ip.type == InternetAddressType.IPv4) return a;
    }
    return null;
  }

  void _publish() {
    if (!_found.isClosed) _found.add(List.unmodifiable(_devices.values));
  }

  Future<void> _serial(Future<void> Function() step) {
    final next = _queue.then((_) => step());
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// Each step runs even when an earlier one fails.
  @override
  Future<void> dispose() async {
    try {
      await stopAdvertising();
    } catch (e) {
      AppLog.w('Stopping the mDNS advertisement failed', e);
    }
    try {
      await _events?.cancel();
    } catch (e) {
      AppLog.w('Cancelling mDNS events failed', e);
    }
    _events = null;
    final d = _browser;
    _browser = null;
    if (d != null && !d.isStopped) {
      try {
        await d.stop();
      } catch (e) {
        AppLog.w('Stopping mDNS browsing failed', e);
      }
    }
    _devices.clear();
    await _found.close();
  }
}
