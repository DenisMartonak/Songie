import 'dart:async';

import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/sync/cloud/cloud_sync.dart';
import 'package:songies/sync/cloud/sync_status.dart';

import '../sync/cloud/fake_cloud.dart';

/// Cloud sync whose status, unsent changes and Sync now the test controls.
/// Never signed in, so it makes no remote calls of its own.
class FakeCloudSync extends CloudSync {
  FakeCloudSync(AppDatabase db, SyncStamp stamp)
    : super(
        db: db,
        stamp: stamp,
        remote: FakeRemote(FakeServer()),
        settings: SettingsRepository(db),
      );

  final _fakeStatuses = StreamController<SyncStatus>.broadcast();
  SyncStatus _fake = const SyncStatus(SyncPhase.idle);

  /// Shows [status] as the current one.
  void emit(SyncStatus status) {
    _fake = status;
    _fakeStatuses.add(status);
  }

  /// What [hasUnsent] answers.
  bool unsent = false;

  /// Run by [syncNow] (e.g. to upload: set [unsent] false).
  FutureOr<void> Function()? onSyncNow;
  int syncNowCalls = 0;
  int hasUnsentCalls = 0;

  @override
  Stream<SyncStatus> get status async* {
    yield _fake;
    yield* _fakeStatuses.stream;
  }

  @override
  SyncStatus get current => _fake;

  @override
  Future<bool> hasUnsent() async {
    hasUnsentCalls++;
    return unsent;
  }

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
    await onSyncNow?.call();
  }

  @override
  Future<void> dispose() async {
    await _fakeStatuses.close();
    await super.dispose();
  }
}
