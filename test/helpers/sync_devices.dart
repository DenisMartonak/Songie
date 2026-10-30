import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/sync/device_identity.dart';
import 'package:songies/sync/sync_server.dart';

/// For tests that run several simulated devices: allows several in-memory
/// databases at once, silences AppLog's console echo, and keeps device
/// identities under a temp directory. Call from `main()`; the returned
/// function gives that directory once `setUpAll` has run.
Directory Function() setUpSyncDevices(String prefix) {
  late Directory root;
  final previousWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  final previousPrint = debugPrint;
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    debugPrint = (message, {wrapWidth}) {};
    root = Directory.systemTemp.createTempSync(prefix);
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarn;
    debugPrint = previousPrint;
    root.deleteSync(recursive: true);
  });
  return () => root;
}

/// A device identity (certificate and key) for [name] under [root].
Future<DeviceIdentity> testIdentity(Directory root, String name) =>
    DeviceIdentity.loadOrCreate(Directory('${root.path}/$name'));

/// Starts [server] on a free loopback port and returns the port.
Future<int> serveLoopback(SyncServer server) =>
    server.start(preferredPort: 0, address: InternetAddress.loopbackIPv4);
