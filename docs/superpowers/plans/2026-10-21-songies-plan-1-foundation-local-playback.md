# Songies Plan 1: Foundation + Local Library + Playback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Songies app on Android, Windows and Linux that scans local MP3 folders, lets you build and edit playlists, and plays them with system media controls (Android notification/lock screen/headset, Windows SMTC, Linux MPRIS), in the Spotify-leaning UI with the Default theme.

**Architecture:** Flutter app. Pure-Dart core (HLC clock, fractional ordering, repositories, player queue) sits on a drift/SQLite database whose synced tables already carry the sync columns later plans need. Platform specifics live only in the audio backend and media-controls adapters. Riverpod wires services to widgets, and go_router drives navigation. An adaptive shell switches between the phone layout (bottom nav) and the desktop layout (sidebar + player bar).

**Tech Stack:** Flutter (stable), Dart 3, flutter_riverpod, go_router, drift + sqlite3_flutter_libs, just_audio + just_audio_media_kit (+ media_kit_libs_windows_audio, media_kit_libs_linux), audio_session, audio_service + audio_service_mpris, smtc_windows, audio_metadata_reader, crypto, image, file_picker, permission_handler, path_provider, flutter_svg, window_manager, uuid.

**Spec:** `docs/superpowers/specs/2026-10-21-songies-design.md`

### Roadmap (one plan per subsystem; later plans are written when the previous one lands)
1. **This plan:** spec §4, §5 (core tables), §11 (shell, library, playlist, search, Now Playing, media controls), §12, §13 (core), milestones 1–2.
2. Plan 2: YouTube import, Sync with YouTube, streaming (§6), `yt_seen` table, Android Share intent.
3. Plan 3: Downloads + yt-dlp updater (§7), `playlist_device_prefs`.
4. Plan 4: Theme engine + editor + fonts + follow-cover, lyrics (§9, §10), `themes`/`fonts`/`lyrics` tables.
5. Plan 5: Device sync (§8), `peers` table, content hashing.
6. Plan 6: Packaging (§14.7), close-to-tray, Android battery-optimization prompt.

## Global Constraints

- Targets: Android (sideloaded APK, `minSdk 24`), Windows 10+, Linux (Fedora/Nobara). No iOS/macOS.
- Application id / org: `com.songies` (Android package `com.songies.songies`).
- **No idle work:** no polling, timers or background jobs except playback and the 10-minute paused-idle stop.
- Every synced row has `id` (UUID v4), `clock` (packed HLC), `origin_device`, `deleted` (tombstone, never hard-delete), `local_seq`.
- HLC pack format: `<wall_ms zero-padded to 13>-<counter zero-padded to 5>-<device_id>` (string order == clock order).
- `<appData>`: Android `getExternalFilesDir` (path_provider `getExternalStorageDirectory()`), Windows `%APPDATA%\Songies`, Linux `$XDG_DATA_HOME/songies` falling back to `~/.local/share/songies`.
- Layout: `songies.db`, `art/<sha256>.jpg` (≤ 512 px), `library/local/`, `library/yt/`, `fonts/`, `bin/`, `logs/songies.log` (rotates at 2 MB to `songies.log.1`).
- Local MP3s the user adds are referenced in place, never copied.
- Default theme: base charcoal, background `#121212`, surface `#2a2a2a`, text `#ffffff`, muted text `#a7a7a7`, accent `#1db954`, cornerRadius 6, font Inter, fontScale 1.0, glowStrength 0.4, followCover false, blurNowPlaying true.
- Phone bottom nav: icon above label (Home · Search · Library). Active tab = white label w700 + filled Home house / 3 px stroke for Search & Library. Inactive = `#a7a7a7` outline, 2 px stroke. Bar height 64 incl. 8 px top padding, icon 24, label 10.5, gap 4. Gradient fade into background.
- Mini-player: height 48, 8 px side margin, **8 px gap above the nav**, theme radius, 2 px accent progress line.
- Layout breakpoint: width < 720 logical px → phone shell, otherwise desktop shell.
- Tests never touch the network or real audio devices. Use fakes.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Messy music folders** (thousands of files, zero-byte, corrupt tags, `.MP3` uppercase, non-MP3 files, unreadable files): the scan finishes and skips bad files with a count, never aborting. Pinned in Task 6.
2. **File moved or deleted after import:** playing it skips to the next track and marks it "file missing". No crash, no infinite skip loop when every file is missing. Pinned in Task 8.
3. **Same MP3 added twice** (rescan, same file in two folders, renamed copy): one track row (dedupe by sha256), and an unchanged file isn't re-hashed. Pinned in Task 6.
4. **Editing the queue/playlist while a track plays** (remove or move the current track, shuffle a 1-track queue, repeat-one at end): playback continues on the right track. Pinned in Task 8.
5. **Missing or odd tags** (no tags, `Artist - Title.mp3` filenames, non-ASCII/very long titles, diacritics in search): sensible fallbacks, and search finds `Beyoncé` when you type `beyonce`. Pinned in Tasks 6 and 7.

---

## File Structure

```
pubspec.yaml
analysis_options.yaml
assets/icons/{home_filled,home_outline,search,library}.svg
assets/fonts/Inter-{Regular,SemiBold,Bold,ExtraBold}.ttf
lib/
  main.dart                         bootstrap: paths, log, db, media init, ProviderScope
  app.dart                          MaterialApp.router + theme
  providers.dart                    Riverpod providers for all services
  router.dart                       go_router routes
  core/result.dart                  Result / Failure
  core/log.dart                     rolling file logger
  core/paths.dart                   AppPaths
  core/ids.dart                     newId()
  core/text_normalize.dart          normalizeForSearch()
  core/hlc.dart                     Hlc, HlcClock
  core/fractional_index.dart        keyBetween, nKeysBetween
  data/tables.dart                  drift tables
  data/database.dart                AppDatabase, migrations
  data/sync_stamp.dart              SyncStamp (clock + local_seq + device id)
  library/art_cache.dart            ArtCache
  library/file_hasher.dart          sha256File
  library/tag_reader.dart           TagReader, TrackTags, AudioMetadataTagReader
  library/library_scanner.dart      LibraryScanner, ScanProgress
  library/library_repository.dart   playlists / entries CRUD, PlaylistSummary, PlaylistTrack
  library/search_repository.dart    SearchRepository
  player/audio_backend.dart         AudioBackend, AudioSourceRef, BackendState
  player/track_resolver.dart        TrackResolver, LocalTrackResolver
  player/player_service.dart        PlayerService, PlayerState, RepeatMode
  player/just_audio_backend.dart    JustAudioBackend
  player/media_controls.dart        MediaControlsBinding (+ platform impls below)
  player/audio_handler.dart         SongiesAudioHandler (Android + Linux via audio_service)
  player/smtc_binding.dart          Windows SMTC binding
  theme/theme_spec.dart             ThemeSpec + builtInDefault
  theme/app_theme.dart              SongiesColors, buildThemeData
  ui/shell/adaptive_shell.dart
  ui/shell/phone_shell.dart
  ui/shell/bottom_nav.dart
  ui/shell/mini_player.dart
  ui/shell/desktop_shell.dart       title bar, sidebar, player bar, shortcuts
  ui/widgets/artwork.dart           square art with fallback gradient
  ui/home/home_page.dart
  ui/search/search_page.dart
  ui/library/library_page.dart
  ui/library/add_songs_sheet.dart
  ui/playlist/playlist_page.dart
  ui/now_playing/now_playing_page.dart
  ui/settings/settings_page.dart
test/
  helpers/test_db.dart              in-memory AppDatabase + fixed clock
  helpers/fake_audio_backend.dart
  fixtures/audio/                   tiny MP3 fixtures (see Task 6)
  core/*_test.dart, data/*_test.dart, library/*_test.dart, player/*_test.dart, theme/*_test.dart, ui/*_test.dart
```

---

### Task 0: Toolchain (manual, the user does this)

Nothing is installed on the Windows PC yet. The agent prepares the commands, and the user runs installers and accepts licences.

- [ ] **Step 1: Install on Windows:**
  - Flutter SDK (stable), added to PATH.
  - Android Studio, then from its SDK Manager: Android SDK, Platform-Tools, Command-line Tools, and an emulator image or a USB-debugging phone.
  - Visual Studio 2022 with the "Desktop development with C++" workload.
  - Git (already present).
- [ ] **Step 2: Run** `flutter doctor --android-licenses` **then** `flutter doctor`. Expected: ✓ for Flutter, Android toolchain, Visual Studio, and a connected device or emulator.
- [ ] **Step 3 (on the Nobara machine, before Task 15):** `sudo dnf install clang cmake ninja-build gtk3-devel mpv-libs-devel libsecret-devel`. Then install Flutter and run `flutter doctor`. Expected: ✓ Linux toolchain.

---

### Task 1: Scaffold + core utilities (Result, ids, log, paths, text normalize)

**Files:**
- Create: Flutter project in repo root, `analysis_options.yaml`, `lib/core/{result,ids,log,paths,text_normalize}.dart`
- Test: `test/core/log_test.dart`, `test/core/text_normalize_test.dart`

**Interfaces:**
- Produces:
  - `sealed class Result<T>`; `final class Ok<T>(T value)`; `final class Err<T>(Failure failure)`
  - `enum FailureKind { notFound, invalidInput, io, permission, network, unsupported, unknown }`
  - `class Failure(FailureKind kind, String message, {Object? cause})`
  - `String newId()` (UUID v4)
  - `class AppLog { static Future<void> init(Directory logsDir); static Future<void> flush(); static void i(String m); static void w(String m, [Object? e, StackTrace? s]); static void e(String m, [Object? e, StackTrace? s]); }`
  - `class AppPaths { Directory root, art, libraryLocal, libraryYt, fonts, bin, logs; File db; static Future<AppPaths> resolve(); static AppPaths at(Directory root); Future<void> ensureCreated(); }`
  - `String normalizeForSearch(String s)`

- [ ] **Step 1: Create the project.** Run `flutter create --org com.songies --project-name songies --platforms android,windows,linux .` in the repo root. Set `minSdk = 24` in `android/app/build.gradle(.kts)`. Add dependencies with `flutter pub add` (latest versions): `flutter_riverpod go_router drift sqlite3_flutter_libs path_provider path uuid crypto image just_audio just_audio_media_kit media_kit_libs_windows_audio media_kit_libs_linux audio_session audio_service audio_service_mpris smtc_windows audio_metadata_reader file_picker permission_handler flutter_svg window_manager`. Dev dependencies: `drift_dev build_runner`. Use `flutter_lints` defaults in `analysis_options.yaml`.
- [ ] **Step 2: Write failing tests.**

```dart
// test/core/text_normalize_test.dart
test('lowercases and folds diacritics', () {
  expect(normalizeForSearch('Beyoncé – Ünïcødé  Song'), 'beyonce – unicode song');
});
test('collapses whitespace and trims', () {
  expect(normalizeForSearch('  A\t\nB  '), 'a b');
});

// test/core/log_test.dart
test('rotates at 2 MB', () async {
  final dir = await Directory.systemTemp.createTemp();
  await AppLog.init(dir);
  final line = 'x' * 1024;
  for (var i = 0; i < 2100; i++) { AppLog.i(line); }
  await AppLog.flush();
  expect(File('${dir.path}/songies.log.1').existsSync(), isTrue);
  expect(File('${dir.path}/songies.log').lengthSync(), lessThan(2 * 1024 * 1024));
});
```

- [ ] **Step 3: Run** `flutter test test/core`. Expected: FAIL (undefined symbols).
- [ ] **Step 4: Implement the five files.**
  - `normalizeForSearch` folds Latin-1/Latin Extended-A diacritics with a const map (`é→e`, `ü→u`, `ø→o`, `ß→ss`, …), then lowercases and collapses whitespace.
  - `AppLog` writes synchronously buffered lines with an ISO timestamp and level, rotates when the file would exceed 2 097 152 bytes, and exposes `static Future<void> flush()`.
  - `AppPaths.resolve()` follows Global Constraints `<appData>`, and `ensureCreated()` creates every directory.
- [ ] **Step 5: Run** `flutter test test/core`. Expected: PASS. Also run `flutter analyze`. Expected: no issues.
- [ ] **Step 6: Commit** `feat: scaffold Flutter app and core utilities`.

---

### Task 2: HLC clock + fractional index

**Files:**
- Create: `lib/core/hlc.dart`, `lib/core/fractional_index.dart`
- Test: `test/core/hlc_test.dart`, `test/core/fractional_index_test.dart`

**Interfaces:**
- Produces:
  - `class Hlc implements Comparable<Hlc> { final int wallMs; final int counter; final String deviceId; String pack(); static Hlc parse(String s); }`
  - `class HlcClock { HlcClock(String deviceId, {Hlc? last, int Function()? nowMs}); Hlc get last; Hlc tick(); Hlc receive(Hlc remote); }`
  - `String keyBetween(String? a, String? b)` (throws `ArgumentError` if `a != null && b != null && a.compareTo(b) >= 0`)
  - `List<String> nKeysBetween(String? a, String? b, int n)`

- [ ] **Step 1: Write failing tests.**

```dart
// hlc_test.dart
test('pack is zero padded and round-trips', () {
  final h = Hlc(wallMs: 1792607152000, counter: 7, deviceId: 'dev-a');
  expect(h.pack(), '1792607152000-00007-dev-a');
  expect(Hlc.parse(h.pack()), h);
});
test('string order equals clock order', () {
  final a = Hlc(wallMs: 999, counter: 99999, deviceId: 'z');
  final b = Hlc(wallMs: 1000, counter: 0, deviceId: 'a');
  expect(a.compareTo(b) < 0, isTrue);
  expect(a.pack().compareTo(b.pack()) < 0, isTrue);
});
test('tick is monotonic when the wall clock goes backwards', () {
  var now = 5000;
  final c = HlcClock('d', nowMs: () => now);
  final t1 = c.tick();
  now = 4000;
  final t2 = c.tick();
  expect(t2.compareTo(t1) > 0, isTrue);
  expect(t2.wallMs, 5000);
  expect(t2.counter, 1);
});
test('receive advances past a remote clock from the future', () {
  final c = HlcClock('d', nowMs: () => 1000);
  final r = c.receive(Hlc(wallMs: 9000, counter: 3, deviceId: 'x'));
  expect(r.wallMs, 9000);
  expect(r.counter, 4);
  expect(r.deviceId, 'd');
});

// fractional_index_test.dart — values from rocicorp/fractional-indexing
test('known values', () {
  expect(keyBetween(null, null), 'a0');
  expect(keyBetween(null, 'a0'), 'Zz');
  expect(keyBetween('a0', null), 'a1');
  expect(keyBetween('a1', null), 'a2');
  expect(keyBetween('a0', 'a1'), 'a0V');
  expect(keyBetween('a0V', 'a1'), 'a0l');
  expect(keyBetween('Zz', 'a0'), 'ZzV');
});
test('throws when a >= b', () {
  expect(() => keyBetween('a1', 'a0'), throwsArgumentError);
});
test('1000 appends stay ordered and short', () {
  String? last;
  final keys = <String>[];
  for (var i = 0; i < 1000; i++) { last = keyBetween(last, null); keys.add(last); }
  expect([...keys]..sort(), keys);
  expect(keys.last.length, lessThanOrEqualTo(4));
});
test('random inserts keep order', () {
  final rnd = Random(42);
  final keys = <String>[keyBetween(null, null)];
  for (var i = 0; i < 500; i++) {
    final j = rnd.nextInt(keys.length + 1);
    keys.insert(j, keyBetween(j == 0 ? null : keys[j - 1], j == keys.length ? null : keys[j]));
  }
  expect([...keys]..sort(), keys);
});
test('nKeysBetween returns n ordered keys inside the range', () {
  final ks = nKeysBetween('a0', 'a1', 5);
  expect(ks.length, 5);
  expect([...ks]..sort(), ks);
  expect(ks.first.compareTo('a0') > 0 && ks.last.compareTo('a1') < 0, isTrue);
});
```

- [ ] **Step 2: Run** `flutter test test/core/hlc_test.dart test/core/fractional_index_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `HlcClock.tick()`: `wall = max(now, last.wallMs)`, `counter = wall == last.wallMs ? last.counter + 1 : 0`.
  - `receive()`: `wall = max(now, last.wallMs, remote.wallMs)`, and the counter follows the standard HLC receive rule.
  - Fractional index: port `generateKeyBetween` / `generateNKeysBetween` from the MIT npm package `fractional-indexing` (rocicorp). Keep its base-62 digit set `0-9A-Za-z` and the integer-header scheme, and include its MIT notice in a file header comment.
- [ ] **Step 4: Run the same tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add HLC clock and fractional index`.

---

### Task 3: Database schema + SyncStamp

**Files:**
- Create: `lib/data/tables.dart`, `lib/data/database.dart`, `lib/data/sync_stamp.dart`, `test/helpers/test_db.dart`
- Test: `test/data/database_test.dart`, `test/data/sync_stamp_test.dart`

**Interfaces:**
- Consumes: `HlcClock`, `Hlc`, `newId()` (Task 2, 1)
- Produces:
  - drift tables (column names in Dart camelCase, SQL snake_case):
    - synced mixin `SyncColumns`: `id TEXT PK`, `clock TEXT`, `originDevice TEXT`, `deleted BOOL default false`, `localSeq INT`
    - `Tracks`: `source TEXT ('yt'|'local')`, `ytVideoId TEXT? UNIQUE`, `title TEXT`, `artist TEXT`, `album TEXT?`, `durationMs INT default 0`, `artworkRef TEXT?`, `fileHash TEXT? UNIQUE`, `unavailable BOOL default false`, `searchText TEXT`
    - `Playlists`: `name TEXT`, `coverRef TEXT?`, `source TEXT ('local'|'yt')`, `ytPlaylistUrl TEXT?`, `lastYtSyncAt DATETIME?`
    - `PlaylistEntries`: `playlistId TEXT`, `trackId TEXT`, `position TEXT`, `status TEXT default 'active'`, `kept BOOL default false`, `addedAt DATETIME`. Index `(playlist_id, position)`.
    - device-local: `LocalFiles(trackId TEXT PK, path TEXT, state TEXT, bytes INT, mtimeMs INT, error TEXT?)` with `state ∈ {'done','missing'}` in this plan. `LibraryFolders(path TEXT PK, lastScanAt DATETIME?)`. `Settings(key TEXT PK, value TEXT)`.
  - `class AppDatabase extends _$AppDatabase { AppDatabase(QueryExecutor e); static AppDatabase open(File f); int get schemaVersion => 1; }`
  - `class Stamp { final String id; final String clock; final String originDevice; final int localSeq; }`
  - `class SyncStamp { static Future<SyncStamp> load(AppDatabase db, {int Function()? nowMs}); String get deviceId; Future<Stamp> next({String? id}); }`. `next` must be called inside the caller's transaction and persists `local_seq` and `hlc_last` in `Settings`.
  - `AppDatabase testDb()` in `test/helpers/test_db.dart` (`NativeDatabase.memory()`)

- [ ] **Step 1: Write failing tests.**

```dart
// sync_stamp_test.dart
test('creates and persists a device id once', () async {
  final db = testDb();
  final s1 = await SyncStamp.load(db);
  final s2 = await SyncStamp.load(db);
  expect(s1.deviceId, isNotEmpty);
  expect(s2.deviceId, s1.deviceId);
});
test('next() increments local_seq and clock, survives reload', () async {
  final db = testDb();
  var s = await SyncStamp.load(db, nowMs: () => 1000);
  final a = await s.next();
  final b = await s.next();
  expect(b.localSeq, a.localSeq + 1);
  expect(b.clock.compareTo(a.clock) > 0, isTrue);
  expect(a.originDevice, s.deviceId);
  s = await SyncStamp.load(db, nowMs: () => 1000);
  final c = await s.next();
  expect(c.localSeq, b.localSeq + 1);
  expect(c.clock.compareTo(b.clock) > 0, isTrue);
});

// database_test.dart
test('fileHash is unique', () async {
  final db = testDb();
  await db.into(db.tracks).insert(trackRow(id: 't1', fileHash: 'h'));
  expect(() => db.into(db.tracks).insert(trackRow(id: 't2', fileHash: 'h')), throwsA(isA<SqliteException>()));
}); // trackRow(): a TracksCompanion builder in test_db.dart with defaults for all required columns
test('ytVideoId is unique', () async { /* same as above with ytVideoId: 'v' */ });
test('schema creates all tables', () async {
  final db = testDb();
  final names = (await db.customSelect("select name from sqlite_master where type='table'").get())
      .map((r) => r.read<String>('name')).toSet();
  expect(names, containsAll(['tracks','playlists','playlist_entries','local_files','library_folders','settings']));
});
```

- [ ] **Step 2: Run** `dart run build_runner build -d` **then** `flutter test test/data`. Expected: FAIL. If the failure is "Failed to load dynamic library 'sqlite3.dll'" (Windows host), download the precompiled x64 `sqlite3.dll` from sqlite.org into `test/native/`, and in `test_db.dart` call `open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open('test/native/sqlite3.dll'))` before opening. Add `test/native/` to `.gitignore`.
- [ ] **Step 3: Implement** tables, database (with `MigrationStrategy(onCreate: m.createAll)` and `beforeOpen` enabling `PRAGMA foreign_keys = ON`, `journal_mode = WAL`), and SyncStamp.
- [ ] **Step 4: Run** `flutter test test/data`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add drift schema with sync columns and SyncStamp`.

---

### Task 4: ArtCache + file hasher

**Files:**
- Create: `lib/library/art_cache.dart`, `lib/library/file_hasher.dart`
- Test: `test/library/art_cache_test.dart`, `test/library/file_hasher_test.dart`

**Interfaces:**
- Produces:
  - `Future<String> sha256File(File f)`: hex, streamed, runs in `Isolate.run`
  - `class ArtCache { ArtCache(Directory dir); Future<String?> put(Uint8List imageBytes); File fileFor(String ref); }`. The ref is `<sha256 of source bytes>.jpg`. Images are downscaled so the longest side is ≤ 512 and saved as JPEG quality 85. It returns `null` for undecodable bytes and never throws.

- [ ] **Step 1: Write failing tests:**
  - `sha256File` of a file containing `abc` == `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
  - `put` of a generated 1200×800 PNG (via `package:image`) returns a ref, and decoding `fileFor(ref)` gives width 512, height 341.
  - `put` of the same bytes twice returns the same ref and doesn't rewrite the file (mtime unchanged).
  - `put(Uint8List.fromList([1,2,3]))` returns `null`.
- [ ] **Step 2: Run** `flutter test test/library/art_cache_test.dart test/library/file_hasher_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Decode and resize inside `Isolate.run` so large covers don't jank the UI.
- [ ] **Step 4: Run the same tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add art cache and file hasher`.

---

### Task 5: LibraryRepository (playlists and entries)

**Files:**
- Create: `lib/library/library_repository.dart`
- Test: `test/library/library_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `SyncStamp.next()`, `keyBetween`, `Result`
- Produces:
  - `class PlaylistSummary { String id; String name; String source; int trackCount; int durationMs; String? coverRef; }`. `coverRef` falls back to the first track's `artworkRef`.
  - `class PlaylistTrack { String entryId; Track track; String position; String status; bool fileMissing; }`. `fileMissing` = `LocalFiles.state == 'missing'`.
  - `class LibraryRepository { LibraryRepository(AppDatabase db, SyncStamp stamp);`
    - `Stream<List<PlaylistSummary>> watchPlaylists();` (sorted by name, case-insensitive)
    - `Stream<List<PlaylistTrack>> watchPlaylistTracks(String playlistId);` (sorted by position, excluding deleted)
    - `Future<Result<String>> createPlaylist(String name);`
    - `Future<Result<void>> renamePlaylist(String id, String name);`
    - `Future<Result<void>> deletePlaylist(String id);`
    - `Future<Result<void>> addTracks(String playlistId, List<String> trackIds);`
    - `Future<Result<void>> moveEntry(String entryId, {String? afterEntryId, String? beforeEntryId});`
    - `Future<Result<void>> removeEntry(String entryId);`
    - `Future<Track?> trackById(String id); }`
  - Rule: every insert/update of a synced row sets `clock`, `originDevice`, `localSeq` from one `stamp.next()` per row, inside one transaction per call.

- [ ] **Step 1: Write failing tests:**
  - `createPlaylist('  Gym Mix ')` → Ok. `watchPlaylists().first` has name `Gym Mix`, trackCount 0, source `local`.
  - `createPlaylist('')` and a 101-character name → `Err` with `FailureKind.invalidInput`.
  - `addTracks(p, [t1, t2, t3])` → positions strictly ascending, order t1, t2, t3. A second `addTracks(p, [t4])` appends after t3.
  - `addTracks` with the same track twice is allowed, giving two entries (playlists may contain duplicates).
  - `moveEntry(e3, afterEntryId: null, beforeEntryId: e1)` → order t3, t1, t2. Only e3's row changed (`localSeq` of e1 and e2 unchanged).
  - `removeEntry(e2)` → row still exists with `deleted = true` and is gone from `watchPlaylistTracks`.
  - `deletePlaylist(p)` → the playlist and all its entries have `deleted = true`, and it's absent from `watchPlaylists`.
  - Every mutated row has `originDevice == stamp.deviceId`, and its `localSeq` is greater than before the call.
  - An unknown id passed to `renamePlaylist`/`moveEntry`/`removeEntry` → `Err(notFound)`.
- [ ] **Step 2: Run** `flutter test test/library/library_repository_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Name rule: trimmed, 1–100 characters. `moveEntry` computes `keyBetween(positionOf(after), positionOf(before))`, where after/before are the neighbours at the target slot.
- [ ] **Step 4: Run the same test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add library repository for playlists and entries`.

---

### Task 6: Tag reader + LibraryScanner

**Files:**
- Create: `lib/library/tag_reader.dart`, `lib/library/library_scanner.dart`, `test/fixtures/audio/` (see Step 1)
- Test: `test/library/library_scanner_test.dart`

**Interfaces:**
- Consumes: `ArtCache.put`, `sha256File`, `SyncStamp`, `LibraryRepository.createPlaylist/addTracks`, `normalizeForSearch`
- Produces:
  - `class TrackTags { String? title; String? artist; String? album; Duration? duration; Uint8List? picture; }`
  - `abstract class TagReader { Future<TrackTags> read(File f); }`. `AudioMetadataTagReader implements TagReader` uses `audio_metadata_reader`'s `readMetadata(file, getImage: true)`.
  - `class ScanProgress { int found; int processed; int added; int unchanged; int skipped; bool done; }`
  - `class LibraryScanner { LibraryScanner(AppDatabase db, SyncStamp stamp, TagReader tags, ArtCache art, LibraryRepository repo, {Future<String> Function(File) hasher = sha256File});`
    - `Stream<ScanProgress> scanFolder(String folderPath, {String? createPlaylistNamed});`
    - `Future<Result<String>> importFile(String path);` (returns the trackId)
    - `Future<void> markMissing(String trackId); }`
- Rules:
  - The scan is recursive and matches `.mp3` case-insensitively.
  - Files of 0 bytes are skipped.
  - An existing `LocalFiles` row with the same path, `bytes` and `mtimeMs` counts as unchanged, with no hash and no tag read.
  - If another track already has the same `fileHash`, its `LocalFiles` row is pointed at this path (or the existing row kept if that path still exists) and no new track is created.
  - A tag read that throws falls back to the filename.
  - A file that can't be read (IO error) is skipped, logged, and counted in `skipped`.
  - The folder is upserted into `LibraryFolders` with `lastScanAt`.
  - With `createPlaylistNamed`, a playlist with that name is created containing every scanned track (new and unchanged) in path order.
  - Library files that were in this folder and no longer exist get `state = 'missing'`.
  - Filename fallback: strip the extension. If it matches `^(.+?)\s+-\s+(.+)$`, it becomes artist = group 1 and title = group 2. Otherwise title = filename and artist = `Unknown artist`.
  - `searchText` = `normalizeForSearch('$title $artist ${album ?? ''}')`.

- Cancellation: cancelling the `scanFolder` stream subscription stops the scan after the file in progress. Rows already written stay, and `lastScanAt` isn't updated.

- [ ] **Step 1: Write failing tests using a `FakeTagReader`** (keyed by filename, with the option to throw) **and a temp folder of fixture files** generated at runtime (bytes content doesn't matter for the fake reader). Tests:
  - Folder with `a.mp3`, `B.MP3`, `notes.txt`, `empty.mp3` (0 bytes), `sub/c.mp3` → final progress `found 4, added 3, skipped 1`. `tracks` has 3 rows.
  - Tags `{title: 'Song', artist: 'Band', album: 'LP', duration: 200s, picture: <png bytes>}` → track has those values, `durationMs 200000`, and `artworkRef != null`.
  - Tag reader throws for `Daft Punk - One More Time.mp3` → artist `Daft Punk`, title `One More Time`. For `weird_名前.mp3` → title `weird_名前`, artist `Unknown artist`.
  - Rescanning the same folder → `unchanged 3, added 0`, and the hasher call count stays the same (spy hasher).
  - The same bytes copied to a second folder and scanned → still 3 tracks, with no duplicate `fileHash`.
  - A file deleted, then a rescan → its `LocalFiles.state == 'missing'`.
  - `createPlaylistNamed: 'My Folder'` → `watchPlaylists` contains `My Folder` with trackCount 3.
  - A file the hasher throws `FileSystemException` on → `skipped` +1, and the scan still reaches `done: true`.
  - Cancelling the subscription after the first progress event on a 100-file folder → fewer than 100 tracks, and `LibraryFolders.lastScanAt` is null.
  - Plus one integration test with the real `AudioMetadataTagReader` on `test/fixtures/audio/tagged.mp3`: a ~1 s silent MP3 with ID3v2 title `Fixture`, artist `Songies`, generated once with any tag editor and committed (< 20 KB). It asserts title and artist.
- [ ] **Step 2: Run** `flutter test test/library/library_scanner_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Hash with at most 2 files in flight. Yield a progress event at most every 25 files plus the final one.
- [ ] **Step 4: Run the same test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add tag reader and library scanner`.

---

### Task 7: SearchRepository

**Files:**
- Create: `lib/library/search_repository.dart`
- Test: `test/library/search_repository_test.dart`

**Interfaces:**
- Produces: `class SearchRepository { SearchRepository(AppDatabase db); Stream<List<Track>> searchTracks(String query, {int limit = 50}); Stream<List<PlaylistSummary>> searchPlaylists(String query); Stream<List<Track>> allTracks(); }`
- Matching: `normalizeForSearch(query)` is split on spaces, and every token must match `searchText LIKE '%token%'` (AND). Tracks are ordered by title. Deleted rows are excluded. An empty query returns `[]` for the search functions. `allTracks` returns every non-deleted local track, ordered by title.
- **Spec deviation (intentional):** spec §11 says FTS5. For a personal library (≤ tens of thousands of rows), a `LIKE` over the normalized `search_text` column is fast enough and avoids FTS triggers. Revisit only if search feels slow.

- [ ] **Step 1: Write failing tests:**
  - A track `Halo / Beyoncé` is found by `beyonce`, `HALO bey`, and `é`.
  - `halo zzz` → empty.
  - A deleted track isn't returned.
  - `searchPlaylists('gym')` finds `Gym Mix`.
  - An empty or whitespace query → `[]`.
- [ ] **Step 2: Run** `flutter test test/library/search_repository_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add library search`.

---

### Task 8: AudioBackend interface + PlayerService (queue logic)

**Files:**
- Create: `lib/player/audio_backend.dart`, `lib/player/track_resolver.dart`, `lib/player/player_service.dart`, `test/helpers/fake_audio_backend.dart`
- Test: `test/player/player_service_test.dart`

**Interfaces:**
- Consumes: `Track` (drift), `LibraryScanner.markMissing`, `Result`
- Produces:
  - `sealed class AudioSourceRef`; `FileSource(String path)`; `UrlSource(Uri url)` (used by Plan 2)
  - `class BackendState { bool playing; bool buffering; bool completed; Duration position; Duration? duration; }`
  - `abstract class AudioBackend { Future<void> setSource(AudioSourceRef s); Future<void> play(); Future<void> pause(); Future<void> seek(Duration d); Future<void> stop(); Stream<BackendState> get states; Future<void> dispose(); }`
  - `abstract class TrackResolver { Future<Result<AudioSourceRef>> resolve(Track t); }`. `LocalTrackResolver(AppDatabase db)` returns `Ok(FileSource(path))` if the `LocalFiles` path exists, otherwise `Err(notFound)`.
  - `enum RepeatMode { off, all, one }`
  - `class PlayerState { List<Track> queue; int index; bool playing; bool buffering; Duration position; Duration? duration; bool shuffle; RepeatMode repeat; String? sourcePlaylistId; String? error; Track? get current; }`
  - `class PlayerService { PlayerService(AudioBackend backend, TrackResolver resolver, {Future<void> Function(String trackId)? onMissing, Future<void> Function(Track track, String? playlistId)? onTrackStarted, Random? random});`. `onTrackStarted` fires once each time a track's playback actually begins.
    - `Stream<PlayerState> get states; PlayerState get state;`
    - `Future<void> playQueue(List<Track> tracks, {int startIndex = 0, String? sourcePlaylistId});`
    - `Future<void> togglePlay(); Future<void> play(); Future<void> pause(); Future<void> next(); Future<void> previous(); Future<void> seek(Duration d); Future<void> playAt(int index);`
    - `void setShuffle(bool on); void cycleRepeat();` (off → all → one → off)
    - `Future<void> removeAt(int index); void move(int from, int to);`
    - `Future<void> dispose(); }`

- [ ] **Step 1: Write `FakeAudioBackend`.** It records calls, lets a test emit `completed`, and sets position.
- [ ] **Step 2: Write failing tests:**
  - `playQueue([a,b,c], startIndex: 1)` → backend `setSource(File b)`, then `play`. `state.current == b`.
  - Completion of b → c plays. Completion of c with `repeat off` → `playing false`, index stays 2, backend `stop` called.
  - `repeat all` at end of queue → wraps to a. `repeat one` → completion re-plays the same track (`seek(0)` + `play`).
  - `previous()` at position 5 s → `seek(Duration.zero)` and the same index. At position 2 s → previous track. At index 0 at 2 s → seek 0.
  - `setShuffle(true)` on `[a..e]` while c plays → c stays current at index 0, and the queue is a permutation of a..e. `setShuffle(false)` → original order restored with c current (index 2). Shuffle on a 1-track queue → no error, same track.
  - The resolver returns `Err(notFound)` for b during `next()` from a → `onMissing('b')` called, c plays.
  - All tracks missing → after trying each once, `playing false`, `error == 'No playable files in queue'`, and no infinite loop (resolver called exactly `queue.length` times).
  - `removeAt(current)` while playing → the next track starts. Removing the last remaining track → stop with an empty queue.
  - `move(0, 2)` while index 0 plays → current track unchanged, index becomes 2.
  - A queue mutation never restarts the current track (no extra `setSource`).
- [ ] **Step 3: Run** `flutter test test/player/player_service_test.dart`. Expected: FAIL.
- [ ] **Step 4: Implement.** Keep `_originalOrder` alongside the playing order for shuffle. Use the injected `random` (default `Random()`) so tests are deterministic.
- [ ] **Step 5: Run the same test.** Expected: PASS.
- [ ] **Step 6: Commit** `feat: add player service with queue, shuffle, repeat`.

---

### Task 9: JustAudioBackend + audio session

**Files:**
- Create: `lib/player/just_audio_backend.dart`
- Modify: `lib/main.dart` (initialisation)
- Test: manual (real audio device)

**Interfaces:**
- Consumes: `AudioBackend` (Task 8)
- Produces:
  - `class JustAudioBackend implements AudioBackend { JustAudioBackend(); Stream<void> get becomingNoisy; }`
  - `Future<void> initAudioPlatform()`: calls `JustAudioMediaKit.ensureInitialized(linux: true, windows: true)` on desktop, and configures `AudioSession` with `AudioSessionConfiguration.music()`.

- [ ] **Step 1: Implement.**
  - Map just_audio's `playerStateStream` + `positionStream` + `durationStream` to `BackendState`, with `completed` = `ProcessingState.completed`.
  - `FileSource` → `AudioSource.file(path)`, `UrlSource` → `AudioSource.uri(url)`.
  - Forward `AudioSession.becomingNoisyEventStream` as `becomingNoisy`. `providers.dart` (Task 11) subscribes it to `PlayerService.pause()`.
  - Handle `AudioSession.interruptionEventStream`: pause on interruption begin, and resume only if the interruption type is `pause` and the app was playing.
- [ ] **Step 2: Temporary manual check.** Add a debug button in `main.dart` that plays `test/fixtures/audio/tagged.mp3` copied to `<appData>`. Run it on Windows (`flutter run -d windows`) and on the Android device (`flutter run -d <id>`). Expected: audible playback. On Android, unplugging headphones pauses it. Remove the debug button afterwards.
- [ ] **Step 3: Run** `flutter analyze`. Expected: no issues.
- [ ] **Step 4: Commit** `feat: add just_audio backend with audio session handling`.

---

### Task 10: System media controls (Android notification, Linux MPRIS, Windows SMTC)

**Files:**
- Create: `lib/player/media_controls.dart`, `lib/player/audio_handler.dart`, `lib/player/smtc_binding.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/songies/songies/MainActivity.kt`, `android/app/src/main/res/drawable/` (shuffle/repeat icons)
- Test: `test/player/audio_handler_test.dart` + manual checklist

**Interfaces:**
- Consumes: `PlayerService.states` and its control methods, `ArtCache.fileFor`
- Produces:
  - `abstract class MediaControlsBinding { static Future<MediaControlsBinding> create(PlayerService p, ArtCache art); Future<void> dispose(); }`. On Android/Linux it returns the audio_service binding, on Windows the SMTC binding.
  - `class SongiesAudioHandler extends BaseAudioHandler with SeekHandler { SongiesAudioHandler(PlayerService p, ArtCache art, {Duration idleStop = const Duration(minutes: 10)}); }`
- Values (spec §11, System media controls):
  - `AudioServiceConfig(androidNotificationChannelId: 'com.songies.playback', androidNotificationChannelName: 'Playback', androidNotificationOngoing: false, androidStopForegroundOnPause: false, androidNotificationIcon: 'drawable/ic_stat_songies')`
  - Controls: `[skipToPrevious, play|pause, skipToNext, custom shuffle, custom repeat]`, compact view indices `[0,1,2]`
  - `systemActions: {MediaAction.seek}`
  - `MediaItem` with `artUri: Uri.file(art.fileFor(ref).path)`, `duration`, `title`, `artist`, `album`
  - Paused for `idleStop` → `stop()`, which ends the foreground service so the notification becomes dismissible.
  - Tapping the notification opens the app on Now Playing (`/now-playing` deep link through `AudioService.notificationClicked`).

- [ ] **Step 1: Write failing tests for `SongiesAudioHandler` with a FakeAudioBackend-backed PlayerService:**
  - A state change emits a `playbackState` with `playing`, `updatePosition`, `queueIndex`, and controls in the order above (the pause control when playing, play when paused).
  - The current track emits a `mediaItem` with title/artist/duration and a file `artUri`.
  - `customAction('shuffle')` toggles `PlayerService.state.shuffle`. `customAction('repeat')` cycles repeat.
  - `skipToNext`/`skipToPrevious`/`seek` delegate.
  - With `idleStop: Duration(milliseconds: 50)`: pause, wait 80 ms → `processingState == AudioProcessingState.idle` and the service is stopped. Play within the window → not stopped. Use `fake_async`.
- [ ] **Step 2: Run** `flutter test test/player/audio_handler_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the handler and bindings.**
  - Android: `MainActivity` extends `AudioServiceActivity`. The manifest gets `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, the `com.ryanheise.audioservice.AudioService` service with `foregroundServiceType="mediaPlayback"`, and the `MediaButtonReceiver`, as the audio_service README specifies. Request `POST_NOTIFICATIONS` at first playback on API 33+.
  - Shuffle/repeat custom controls use `MediaControl.custom(androidIcon: 'drawable/ic_shuffle', label: 'Shuffle', name: 'shuffle')` (and likewise for repeat).
  - Windows `SmtcBinding`: `SMTCWindows` with `SMTCConfig(playEnabled, pauseEnabled, nextEnabled, prevEnabled: true)`. Update metadata (title, artist, album, thumbnail file path) and playback status on each state, and map `buttonPressStream` to PlayerService.
  - Linux: `audio_service_mpris` registers automatically once it's a dependency. Pass `AudioServiceConfig` as on Android.
- [ ] **Step 4: Run** `flutter test test/player`. Expected: PASS.
- [ ] **Step 5: Manual checklist** (after Task 12 makes playback reachable from the UI; tick here then):
  - Android notification shows art/title/artist, a seek bar, and prev/play/next + shuffle/repeat.
  - Lock screen controls work.
  - A Bluetooth headset play/pause works.
  - Paused for 10 min → swipe-dismissible.
  - Windows media flyout shows art and controls, and keyboard media keys work.
  - KDE/GNOME media applet shows it on Nobara.
- [ ] **Step 6: Commit** `feat: add system media controls for Android, Linux, Windows`.

---

### Task 11: Theme model + app bootstrap + providers + router

**Files:**
- Create: `lib/theme/theme_spec.dart`, `lib/theme/app_theme.dart`, `lib/providers.dart`, `lib/router.dart`, `lib/app.dart`, `assets/fonts/Inter-*.ttf` (OFL, from the official Inter release), `assets/fonts/OFL.txt`
- Modify: `lib/main.dart`, `pubspec.yaml` (fonts, assets)
- Test: `test/theme/theme_spec_test.dart`, `test/theme/app_theme_test.dart`

**Interfaces:**
- Produces:
  - `class ThemeSpec { String base; Color background; Color surface; Color text; Color mutedText; Color accent; bool followCover; double glowStrength; double cornerRadius; String fontFamily; String? fontFileHash; double fontScale; bool blurNowPlaying; Map<String,dynamic> toJson(); factory ThemeSpec.fromJson(Map<String,dynamic>); static const ThemeSpec builtInDefault; }`. JSON keys match spec §9, plus `mutedText`.
  - `class SongiesColors extends ThemeExtension<SongiesColors> { Color background, surface, text, mutedText, accent, glow, miniPlayer; double radius; bool blurNowPlaying; }`
  - `ThemeData buildThemeData(ThemeSpec spec)`: dark brightness, `fontFamily` = spec font, text scaled by `fontScale`, plus the `SongiesColors` extension. `glow` = accent at opacity `glowStrength`, and `miniPlayer` = `Color.alphaBlend(accent.withOpacity(0.25), surface)`.
  - Providers: `appPathsProvider`, `databaseProvider`, `syncStampProvider`, `libraryRepositoryProvider`, `searchRepositoryProvider`, `libraryScannerProvider`, `artCacheProvider`, `playerServiceProvider`, `playerStateProvider` (StreamProvider), `themeSpecProvider` (returns `builtInDefault` in this plan).
  - Routes: `/home`, `/search`, `/library`, `/playlist/:id`, `/now-playing`, `/settings`, inside a `StatefulShellRoute` hosted by `AdaptiveShell` (Task 12).
  - `main()`: `WidgetsFlutterBinding.ensureInitialized()` → `AppPaths.resolve()` + `ensureCreated()` → `AppLog.init` → `AppDatabase.open` → `SyncStamp.load` → `initAudioPlatform()` → on desktop `windowManager.ensureInitialized()` with `TitleBarStyle.hidden`, minimum size 900×600 → `MediaControlsBinding.create` → `runApp(ProviderScope(overrides: [...], child: SongiesApp()))`. `FlutterError.onError` and `PlatformDispatcher.instance.onError` log through `AppLog.e`.

- [ ] **Step 1: Write failing tests:**
  - `ThemeSpec.builtInDefault` has exactly the Global Constraints values.
  - `fromJson(toJson(x)) == x`.
  - `fromJson` with a missing `accent` throws `FormatException`.
  - `buildThemeData(default).extension<SongiesColors>()!.radius == 6`, and the scaffold background is `#121212`.
- [ ] **Step 2: Run** `flutter test test/theme`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/theme`. Expected: PASS. Then `flutter run -d windows`. Expected: the app opens with an empty shell route and no errors in the log.
- [ ] **Step 5: Commit** `feat: add theme model, providers, router and bootstrap`.

---

### Task 12: Adaptive shell (phone bottom nav + mini-player, desktop sidebar + player bar)

**Files:**
- Create: `lib/ui/shell/{adaptive_shell,phone_shell,bottom_nav,mini_player,desktop_shell}.dart`, `lib/ui/widgets/artwork.dart`, `assets/icons/{home_filled,home_outline,search,library}.svg`
- Test: `test/ui/shell_test.dart`

**Interfaces:**
- Consumes: `playerStateProvider`, `playerServiceProvider`, `SongiesColors`, routes
- Produces:
  - `AdaptiveShell(StatefulNavigationShell shell)`: phone if width < 720, otherwise desktop.
  - `BottomNav(int index, ValueChanged<int> onTap)`
  - `MiniPlayer()`: hidden when the queue is empty.
  - `DesktopShell`:
    - title bar 36 px with `DragToMoveArea`, the search field (Ctrl+K focuses it), and window buttons
    - sidebar 260 px (collapses to 72 px icon rail via a chevron): Home, Search, Sync devices (disabled, tooltip "Coming soon"), then the library list from `watchPlaylists`
    - player bar 72 px: art + title/artist on the left; shuffle, prev, play/pause, next, repeat and a scrubber in the centre; queue and volume on the right
  - `Artwork(String? ref, {double size, double? radius})`: shows a gradient placeholder derived from `ref.hashCode` when null.
- SVG paths (from the approved mockup, viewBox 0 0 24 24):
  - `home_filled`: `<path fill="currentColor" d="M12 2.6 1.9 10.4l1.2 1.6L4.5 11v10.4h6v-6.2h3v6.2h6V11l1.4 1 1.2-1.6z"/>`
  - `home_outline`: `<path fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" d="M12 3.5 3 10.5V20.5h6v-6h6v6h6V10.5z"/>`
  - `search`: `<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/>` (stroke, round caps; width 2 inactive / 3 active)
  - `library`: `<path d="M4 4v16M9 4v16"/><path d="m13.5 4.5 5.5 15"/>` (same stroke rules)
- Keyboard shortcuts (desktop, ignored while a text field has focus): Space → `togglePlay`, Ctrl+→ → `next`, Ctrl+← → `previous`, Ctrl+K → focus search.

- [ ] **Step 1: Write failing widget tests** (FakeAudioBackend-backed player, provider overrides):
  - At 400×800: `BottomNav` is visible, Home is active and uses the `home_filled` asset with a white label. Tapping Search → Home uses `home_outline`, and the Search label is white with w700.
  - At 400×800 with an empty queue → no `MiniPlayer`. After `playQueue([t])` → `MiniPlayer` shows the title, and the vertical gap between the bottom of the `MiniPlayer` and the top of the `BottomNav` == 8.
  - Tapping the mini-player play button calls `togglePlay`.
  - At 1280×800: sidebar and player bar visible, no `BottomNav`.
  - Pressing Space with no text focus toggles play. Pressing Space while the search field is focused types a space and doesn't toggle.
- [ ] **Step 2: Run** `flutter test test/ui/shell_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Use the Global Constraints nav and mini-player values. Tapping the mini-player opens `/now-playing`.
- [ ] **Step 4: Run the same test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add adaptive phone and desktop shells`.

---

### Task 13: Library, Playlist and Add-songs screens

**Files:**
- Create: `lib/ui/library/library_page.dart`, `lib/ui/library/add_songs_sheet.dart`, `lib/ui/playlist/playlist_page.dart`
- Test: `test/ui/playlist_page_test.dart`, `test/ui/library_page_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository`, `SearchRepository.allTracks/searchTracks`, `LibraryScanner.scanFolder`, `PlayerService.playQueue`, `Artwork`
- Produces:
  - `LibraryPage`:
    - filter chips `All · Local` (YouTube/Downloaded chips arrive in Plans 2/3) and the playlist list
    - "+" menu: **New playlist** (name dialog) and **Add music folder**, which opens the `FilePicker.platform.getDirectoryPath()` folder picker, then a dialog with a "Also create playlist '<folder name>'" checkbox (default on), then `scanFolder` with a progress snackbar
    - On Android, request `Permission.audio` (API 33+) or `Permission.storage` (≤ 32) first. If denied, show an explanation with an "Open settings" action.
  - `PlaylistPage(id)`:
    - hero: cover, name, `Local playlist`, "N songs · H h M min"
    - actions: Play, Shuffle, ⋯ (Rename, Delete with confirm, Add songs)
    - track rows: art, title, artist, duration, drag handle
    - `ReorderableListView` → `moveEntry`, swipe-to-remove → `removeEntry` with an Undo snackbar (Undo re-adds the track at the same position via `addTracks` + `moveEntry`)
    - rows with `fileMissing` are greyed with a "File missing" tag and a **Locate** action (file picker → `importFile` → replace the entry's track)
  - `AddSongsSheet(playlistId)`: a searchable multi-select list over `allTracks`/`searchTracks`, with a "Add (N)" button → `addTracks`.
  - Empty states:
    - no playlists → "Add a music folder" button
    - empty playlist → "Add songs" button

- [ ] **Step 1: Write failing widget tests** (in-memory db, seeded tracks):
  - A playlist with 3 tracks renders 3 rows in position order, with the header "3 songs · 0 h 10 min" for 200 s each.
  - Dragging row 3 above row 1 → `watchPlaylistTracks` order t3, t1, t2.
  - Swipe-removing t2 then tapping Undo → order restored to t1, t2, t3.
  - Tapping row 2 → `PlayerService.state.queue` == [t1, t2, t3] with index 1 and `sourcePlaylistId == id`.
  - A missing-file row shows "File missing", and tapping it doesn't start playback.
  - New playlist dialog with an empty name → Save disabled.
  - Very long title (300 characters) → a single line with ellipsis and no overflow error.
- [ ] **Step 2: Run** `flutter test test/ui/playlist_page_test.dart test/ui/library_page_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add library, playlist and add-songs screens`.

---

### Task 14: Home, Search and Now Playing screens

**Files:**
- Create: `lib/ui/home/home_page.dart`, `lib/ui/search/search_page.dart`, `lib/ui/now_playing/now_playing_page.dart`
- Modify: `lib/data/tables.dart` (+ migration to schemaVersion 2): add device-local `PlayHistory(trackId TEXT, playlistId TEXT?, playedAt DATETIME)`. Wire `PlayerService.onTrackStarted` (Task 8) → `PlayHistoryRepository.record`, keeping the newest 200 rows.
- Test: `test/ui/home_search_test.dart`, `test/ui/now_playing_test.dart`, `test/data/migration_test.dart`

**Interfaces:**
- Consumes: repositories, `playerStateProvider`, `SongiesColors`
- Produces:
  - `HomePage`:
    - time-based greeting: 05–12 "Good morning", 12–18 "Good afternoon", otherwise "Good evening"
    - header glow from `SongiesColors.glow`
    - a 2-column grid of up to 6 quick tiles (most recently played distinct playlists, falling back to alphabetical)
    - "Your playlists" horizontal cards, then "Recently played" (last 10 distinct tracks)
  - `SearchPage`: a search field with sections "Songs" and "Playlists" (debounce 150 ms). Tapping a song plays it alone in the queue.
  - `NowPlayingPage`:
    - background = artwork blurred (`ImageFiltered` σ 40) when `blurNowPlaying`, otherwise a `glow` gradient
    - art max 360 px square with theme radius
    - title/artist, a scrubber with elapsed/total, and shuffle (accent when on), prev, a 64 px play/pause circle, next, and repeat (icon `repeat_one` when one)
    - a Queue tab: reorderable list → `PlayerService.move`, swipe → `removeAt`
    - phone: swipe down to close; desktop: a modal overlay with a close button
  - `class PlayHistoryRepository { Future<void> record(String trackId, String? playlistId); Stream<List<Track>> recentTracks(int n); Stream<List<String>> recentPlaylistIds(int n); }` in `lib/library/play_history_repository.dart`.

- [ ] **Step 1: Write failing tests:**
  - Migration test: a v1 database opened with v2 code has a `play_history` table, and existing tracks are preserved.
  - Home at 09:00 (injected clock provider) shows "Good morning". After playing 2 tracks, "Recently played" lists them newest first. Quick tiles ≤ 6.
  - Search `bey` shows `Halo` under Songs, and an empty query shows a hint "Search your songs and playlists".
  - Now Playing: shuffle tap → `state.shuffle` true and the icon colour == accent. Repeat taps cycle off → all → one with the matching icons. Dragging the scrubber to 50 % calls `seek` with half the duration (±1 s).
  - Now Playing with `blurNowPlaying: false` → no `ImageFiltered` in the tree.
- [ ] **Step 2: Run** `flutter test test/ui test/data`. Expected: FAIL.
- [ ] **Step 3: Implement**, including the drift migration `from1To2: m.createTable(playHistory)`.
- [ ] **Step 4: Run** `flutter test`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat: add home, search and now playing screens`.

---

### Task 15: Settings + cross-platform verification

**Files:**
- Create: `lib/ui/settings/settings_page.dart`
- Test: `test/ui/settings_test.dart`

**Interfaces:**
- Produces: `SettingsPage`:
  - **Music folders** list (from `LibraryFolders`) with **Rescan**, **Remove**, and **Add folder** actions. Removing a folder only removes the folder record; tracks stay.
  - **Rescan all**
  - **Storage:** sizes of `art/` and the database
  - **Logs:** "Export log" (save via `FilePicker.platform.saveFile` on desktop, share sheet not required; on Android save to Downloads using `saveFile`)
  - **About:** version and device id (first 8 characters)
  - Reached from the gear icon in the Home header (phone) and from the sidebar footer (desktop).

- [ ] **Step 1: Write failing tests:**
  - Seeded with 2 folders → 2 rows shown. Tapping Rescan on row 1 calls `scanFolder` with that path (spy scanner).
  - Remove asks for confirmation, then the row disappears.
- [ ] **Step 2: Run** `flutter test test/ui/settings_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all PASS, no issues.
- [ ] **Step 5: Manual verification on all three platforms.**
  - Build: `flutter run -d windows`, `flutter run --release -d <android>`, and `flutter run -d linux` on Nobara.
  - On each, check:
    1. Add a real music folder with "create playlist" → the playlist appears with art.
    2. Reorder, remove + undo, rename.
    3. Play, then next/previous, shuffle and repeat-one.
    4. Search with an accented artist.
    5. Delete one MP3 on disk, rescan → "File missing", and playback skips it.
    6. Tick the Task 10 Step 5 media-controls checklist.
    7. On Android, screen off for 5 minutes → still playing.
    8. Idle Windows RAM (Task Manager, paused, window open) — record the number in the commit message. Target ≤ 150 MB.
- [ ] **Step 6: Commit** `feat: add settings page; verify plan 1 on Android, Windows, Linux`.
