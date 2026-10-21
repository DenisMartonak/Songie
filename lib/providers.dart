import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/paths.dart';
import 'data/database.dart';
import 'data/sync_stamp.dart';
import 'library/art_cache.dart';
import 'library/library_repository.dart';
import 'library/library_scanner.dart';
import 'library/search_repository.dart';
import 'player/player_service.dart';
import 'theme/theme_spec.dart';

/// Singletons are created in `main()` and injected with
/// `ProviderScope.overrides`; reading one without an override is a wiring bug.
Never _unwired(String name) =>
    throw UnimplementedError('$name must be overridden in ProviderScope');

final appPathsProvider = Provider<AppPaths>(
  (ref) => _unwired('appPathsProvider'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => _unwired('databaseProvider'),
);

final syncStampProvider = Provider<SyncStamp>(
  (ref) => _unwired('syncStampProvider'),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => _unwired('libraryRepositoryProvider'),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => _unwired('searchRepositoryProvider'),
);

final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => _unwired('libraryScannerProvider'),
);

final artCacheProvider = Provider<ArtCache>(
  (ref) => _unwired('artCacheProvider'),
);

final playerServiceProvider = Provider<PlayerService>(
  (ref) => _unwired('playerServiceProvider'),
);

/// The player's state, starting with its current value (the service's own
/// stream only emits changes).
final playerStateProvider = StreamProvider<PlayerState>((ref) async* {
  final player = ref.watch(playerServiceProvider);
  yield player.state;
  yield* player.states;
});

/// The active theme. Always the built-in Default in this plan.
final themeSpecProvider = Provider<ThemeSpec>(
  (ref) => ThemeSpec.builtInDefault,
);
