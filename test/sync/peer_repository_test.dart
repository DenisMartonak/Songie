import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/peer_repository.dart';

import '../helpers/test_db.dart';

PeerRow peer(String id, String name) => PeerRow(
  deviceId: id,
  name: name,
  certFingerprint: 'ab' * 32,
  pairKey: 'a2V5',
  lastSentSeq: 0,
  lastReceivedSeq: 0,
);

void main() {
  late AppDatabase db;
  late PeerRepository repo;
  setUp(() {
    db = testDb();
    repo = PeerRepository(db);
  });
  tearDown(() => db.close());

  test('save, byId, watch by name, remove', () async {
    await repo.save(peer('2', 'Zed'));
    await repo.save(peer('1', 'Alpha'));
    expect((await repo.byId('1'))?.name, 'Alpha');
    expect(await repo.byId('nope'), isNull);
    expect((await repo.watch().first).map((p) => p.name), ['Alpha', 'Zed']);
    await repo.save(peer('1', 'Renamed'));
    expect((await repo.byId('1'))?.name, 'Renamed');
    await repo.remove('1');
    expect(await repo.byId('1'), isNull);
    expect((await repo.watch().first).length, 1);
  });

  test('watermarks and address', () async {
    await repo.save(peer('1', 'Alpha'));
    final at = DateTime.utc(2026, 10, 30, 12);
    await repo.setWatermarks('1', sent: 7, received: 9, at: at);
    await repo.setAddress('1', '192.168.1.5', 47823);
    final p = (await repo.byId('1'))!;
    expect((p.lastSentSeq, p.lastReceivedSeq), (7, 9));
    expect(p.lastSyncAt?.toUtc(), at);
    expect((p.host, p.port), ('192.168.1.5', 47823));
  });
}
