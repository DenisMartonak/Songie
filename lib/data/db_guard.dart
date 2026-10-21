import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../core/result.dart';
import 'database.dart';

/// Runs [body] in one transaction on [db], turning database errors into
/// `Err(FailureKind.io)`.
Future<Result<T>> guardDb<T>(
  AppDatabase db,
  Future<Result<T>> Function() body,
) async {
  try {
    return await db.transaction(body);
  } on SqliteException catch (e) {
    return Err(
      Failure(FailureKind.io, 'Database error: ${e.message}', cause: e),
    );
  } on DriftRemoteException catch (e) {
    // The app database runs in a drift isolate (AppDatabase.open), where
    // sqlite failures arrive wrapped instead of as a SqliteException.
    final cause = e.remoteCause;
    final message = cause is SqliteException ? cause.message : '$cause';
    return Err(
      Failure(FailureKind.io, 'Database error: $message', cause: cause),
    );
  }
}
