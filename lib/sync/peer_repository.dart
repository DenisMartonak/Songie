import 'package:drift/drift.dart';

import '../data/database.dart';

/// Paired devices (device-local `Peers` table; never synced).
class PeerRepository {
  PeerRepository(this._db);

  final AppDatabase _db;

  Stream<List<PeerRow>> watch() => (_db.select(
    _db.peers,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();

  Future<PeerRow?> byId(String deviceId) => (_db.select(
    _db.peers,
  )..where((p) => p.deviceId.equals(deviceId))).getSingleOrNull();

  Future<void> save(PeerRow p) => _db.into(_db.peers).insertOnConflictUpdate(p);

  Future<void> setWatermarks(
    String deviceId, {
    required int sent,
    required int received,
    required DateTime at,
  }) => _update(
    deviceId,
    PeersCompanion(
      lastSentSeq: Value(sent),
      lastReceivedSeq: Value(received),
      lastSyncAt: Value(at),
    ),
  );

  Future<void> setAddress(String deviceId, String host, int port) =>
      _update(deviceId, PeersCompanion(host: Value(host), port: Value(port)));

  Future<void> remove(String deviceId) =>
      (_db.delete(_db.peers)..where((p) => p.deviceId.equals(deviceId))).go();

  Future<void> _update(String deviceId, PeersCompanion c) => (_db.update(
    _db.peers,
  )..where((p) => p.deviceId.equals(deviceId))).write(c);
}
