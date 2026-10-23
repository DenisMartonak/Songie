import 'package:songies/core/result.dart';
import 'package:songies/youtube/yt_import_service.dart';

/// A [YtImportService] whose results the test controls.
class FakeImportService implements YtImportService {
  final List<String> imported = [];
  final List<String> synced = [];

  Future<Result<ImportResult>> Function(String input)? onImport;
  Future<Result<SyncResult>> Function(String playlistId)? onSync;

  @override
  Future<Result<ImportResult>> importPlaylist(String input) {
    imported.add(input);
    return onImport?.call(input) ??
        Future.value(
          const Err(Failure(FailureKind.unknown, 'importPlaylist not faked')),
        );
  }

  @override
  Future<Result<SyncResult>> syncPlaylist(String playlistId) {
    synced.add(playlistId);
    return onSync?.call(playlistId) ??
        Future.value(
          const Err(Failure(FailureKind.unknown, 'syncPlaylist not faked')),
        );
  }

  @override
  Future<void> get thumbnailsSettled => Future.value();
}
