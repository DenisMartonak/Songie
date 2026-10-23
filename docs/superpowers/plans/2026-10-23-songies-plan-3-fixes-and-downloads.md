# Songies Plan 3: Bug Fixes and Downloads — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First fix the bugs the user hit on Android after Plan 2:
- Home and Library open a stale page.
- The music-folder picker never opens.
- Playback shows the wrong song and keeps skipping.
- Covers are pixelated.

Then add YouTube downloads (spec §7) with visible progress everywhere: per song, per playlist, an app-wide indicator, and an Android notification.

**Architecture:**
- **Bug fixes (Tasks 1–4)** are each a small change to code that already exists.
- **Downloads data:** queue state lives in the device-local `local_files` table. Two new columns record the request time and whether the user asked for that song directly. A new `playlist_device_prefs` table stores the per-device "Download" switch.
- **DownloadService** is a pure-Dart queue that calls yt-dlp through `YtDlpClient.download`, which reads yt-dlp's progress lines as they arrive. It publishes `DownloadSnapshot`s that the UI and the Android notification watch.
- **Android:** a small foreground service keeps the app process alive while the queue runs and shows the progress notification.

**Tech Stack:** Flutter 3.47 / Dart 3.13, drift (schema **v4**), Riverpod, go_router, just_audio, yt-dlp (desktop binary) / `youtubedl-android` 0.18.1 (Kotlin), `connectivity_plus`, `permission_handler`.

**Spec:** `docs/superpowers/specs/2026-10-21-songies-design.md`, sections §4 (storage layout), §5 (`local_files`, `playlist_device_prefs`), §6.2 (queueing new songs on sync), §7 (downloads), §11 (download badge/ring, Downloaded chip, Now Playing indicator) and §12. Plans 1–2 are complete. Their rulings (R1–R38) are in `docs/PROGRESS.md`, and Plan 2's open items are listed under "Parked" in its ledger.

## Decisions this plan makes beyond the spec

- **D1:** the user asked to download single songs as well as whole playlists. A track's ⋯ menu gets **Download** / **Remove download**, which sets `local_files.manual = true`. Turning off a playlist's download never deletes a manual song's file.
- **D2:** YouTube artwork is fetched at up to 720 px, and `ArtCache.maxSide` becomes **720** (the spec says ≤ 512). The current 336×188 thumbnails, square-cropped to 188 px, look pixelated on Now Playing.
- **D3:** on Android the folder picker is our own Kotlin channel. `file_picker`'s `getDirectoryPath` swallows every native error and returns null, which is the "picker won't open" bug. Desktop keeps `file_picker`.
- **D4:** Android downloads run under a `dataSync` foreground service with an ongoing progress notification. Desktop shows progress only inside the app.
- **D5:** playback gives up after **3 tracks in a row** fail to start, with the real reason. It no longer silently tries the whole queue.

## Global Constraints

- **Targets:**
  - Android: sideloaded APK, `minSdk 24`, `compileSdk 37`
  - Windows 10+
  - Linux (Fedora/Nobara)
- **Writes:**
  - Every synced row write takes its own `SyncStamp.next()` (or `nextMany`) inside one `guardDb` transaction.
  - `local_files` and `playlist_device_prefs` are device-local and get no stamp.
- **Database:** `schemaVersion` becomes **4**, with a migration test from v3.
- **Download format selector:** `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`. No post-processing and no ffmpeg.
- **Download output:** `<appData>/library/yt/<videoId>.<ext>` (`AppPaths.libraryYt`). yt-dlp writes `.part` and renames on completion, and `--continue` resumes.
- **Queue concurrency:** **2** on Android, **3** on desktop. FIFO by request time.
- **Wi-Fi only** (existing `kWifiOnly`, default on for Android): the queue pauses on `NetworkKind.mobile`. `wifi` and `other` count as unmetered.
- **Failure handling** (spec §7 table, verbatim behaviours):
  - Private/removed/region-blocked: mark the track `unavailable`, skip it and continue the queue.
  - HTTP 429: pause the queue with exponential backoff (**30 s → 10 min**), then resume.
  - Network lost: pause, and resume on connectivity change.
  - Extractor error: mark the song failed and show the banner **"Downloads failing — update yt-dlp?"**
  - Disk full: pause the queue and show an error.
- **No idle work:** timers exist only while the queue has work (backoff) or a song is playing. Nothing polls.
- **Tests:** they never touch the network, YouTube or real audio. Use `FakeYtDlpRunner`, fixtures, `FakeNetworkStatus` and `fake_async`.
- **Commits:** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Turning a playlist's download off while its songs are downloading:** the running yt-dlp processes are cancelled, their `.part` files deleted, and no row later flips to `done`. Pinned in Task 7.
2. **The same song in two downloaded playlists (or downloaded by hand):** it's downloaded once, and disabling one playlist keeps the file. Pinned in Tasks 5 and 9.
3. **The app is killed mid-download:** on the next launch, `downloading` rows go back to `queued` and resume with `--continue`. A `done` row whose file is gone is re-queued if still wanted, or dropped otherwise. Pinned in Task 7.
4. **Wi-Fi drops to mobile data mid-download with Wi-Fi only on:** active downloads are cancelled (not failed) and the queue pauses with "Waiting for Wi-Fi". It resumes on its own when Wi-Fi returns. Pinned in Task 7.
5. **Playing a song that is still downloading:** it streams, never plays the partial file, and plays the file once it's done. Pinned in Task 5 (resolver test).

---

## File Structure

```
lib/router.dart / lib/ui/shell/{phone_shell,sidebar}.dart   tabs always open their root page (Task 1)
lib/player/player_service.dart                              honest track switching, skip cap (Task 2)
lib/ui/shell/player_error_snacks.dart                       skip / give-up messages (Task 2)
lib/youtube/yt_json.dart, lib/library/art_cache.dart        sharp artwork (Task 3)
android/.../FolderPickerPlugin.kt, lib/ui/library/pickers.dart   Android folder picker (Task 4)
lib/data/tables.dart, lib/data/database.dart                v4: playlist_device_prefs, local_files columns (Task 5)
lib/downloads/download_repository.dart                      download rows + prefs + watchers (Task 5)
lib/youtube/ytdlp_runner.dart (+ desktop/android runners)   onLine streaming + cancel (Task 6)
lib/youtube/ytdlp_client.dart, lib/youtube/yt_models.dart   download(), YtDownload, new error kinds (Task 6)
android/.../YtDlpPlugin.kt                                  line events (Task 6)
lib/downloads/download_service.dart                         queue engine, DownloadSnapshot (Task 7)
lib/downloads/download_notifier.dart                        notifier interface + noop (Task 7); android_download_notifier.dart (Task 8)
android/.../DownloadService.kt, DownloadNotifierPlugin.kt   foreground service + notification (Task 8)
lib/ui/downloads/*.dart                                     toggle, badges, rings, banner, sheet (Task 9)
lib/ui/settings/downloads_settings.dart                     storage readout, Wi-Fi only (Task 9)
```

---

### Task 1: Home, Search and Library always open their root page

**Root cause:**
- `StatefulShellRoute.indexedStack` keeps each branch's stack.
- The desktop sidebar calls `shell.goBranch(i)` without `initialLocation`, so Home and Library reopen whatever playlist was last open in that branch.
- The phone bottom nav resets only when the tab is already selected (`initialLocation: i == shell.currentIndex`).
- Sidebar playlist rows `context.go('/library/playlist/<id>')`, so clicking Library afterwards shows that playlist.

**Files:**
- Modify: `lib/ui/shell/phone_shell.dart`, `lib/ui/shell/sidebar.dart`, `lib/ui/shell/desktop_shell.dart` (its Ctrl+K `goBranch`)
- Create: `lib/ui/shell/go_tab.dart`
- Test: `test/ui/shell/navigation_roots_test.dart`

**Interfaces:**
- Produces: `void goTab(StatefulNavigationShell shell, int index)`, which always calls `shell.goBranch(index, initialLocation: true)`. Every Home / Search / Library tap (bottom nav, sidebar, Ctrl+K) goes through it.

- [ ] **Step 1: Write failing widget tests** (use the existing `ui_harness.dart` with the real router):
  - Phone: open a playlist from Home (`/home/playlist/<id>`), tap Library, then tap Home → the Home page is shown (find its greeting) and no `PlaylistPage` is in the tree.
  - Phone: open a playlist from Library, tap Home, tap Library → `LibraryPage` is shown.
  - Desktop: tap a sidebar playlist row, then `sidebar.library` → `LibraryPage`. Then `sidebar.home` → `HomePage`.
  - Back still works inside a branch: Home → playlist → system back → Home.
- [ ] **Step 2: Run** `flutter test test/ui/shell/navigation_roots_test.dart`. Expected: FAIL. The playlist is still shown.
- [ ] **Step 3: Implement `goTab`** and use it at every tab call site.
- [ ] **Step 4: Run** the new test plus `flutter test test/router_test.dart test/ui/shell`. Expected: PASS.
- [ ] **Step 5: Commit** `fix: Home, Search and Library tabs always open their root page`.

---

### Task 2: Playback shows the song that is actually playing, and stops skipping

**Root cause (from reading `player_service.dart`):**
- **Wrong song shown:** `_tryStart` emits the *new* YouTube track as current (`index`, `buffering: true`) before resolving its stream. Meanwhile the old track keeps playing audio, so the UI shows the next song while the previous one is still heard.
- **Endless skipping:** if the start fails, `_startFirstPlayable` silently tries every later entry in the queue. Each one is shown in turn ("it started changing the songs"). When all fail, the player reports `noPlayableFilesError` ("the song files are missing"), which is wrong for YouTube.
- **Parked from Plan 2:** `_onBackendError` doesn't check `_generation`. A late error from the previous source is blamed on the new song, which then gets re-resolved or skipped.
- **Early completion:** a stream that dies mid-song can report `completed` from the engine, which skips the song with no message.

**Files:**
- Modify: `lib/player/player_service.dart`, `lib/ui/shell/player_error_snacks.dart`
- Test: `test/player/player_service_test.dart`, `test/ui/shell/player_error_snacks_test.dart`

**Interfaces:**
- Produces:
  - `PlayerState.notice`, a `PlayerNotice?` with `PlayerNotice({required String trackTitle, required String reason})`. It's set each time a song is skipped because it can't be played, and cleared on the next successful start.
  - The constant `PlayerService.maxConsecutiveSkips = 3`.
  - A new error constant, `PlayerService.tooManyFailuresError = 'Too many songs failed in a row'`.

- [ ] **Step 1: Write failing tests** (`FakeAudioBackend`, fake resolver):
  - `switching to a YouTube track pauses the old audio before resolving`: while the resolve future is pending, `backend.pauseCalls == 1` (or `stopCalls`, whichever the impl uses) and `state.index` is the new entry.
  - `a failed start skips at most 3 tracks`: a queue of 6 YouTube tracks whose resolves all fail with `notFound` → exactly 3 resolve calls, then `state.playing == false` and `state.error == tooManyFailuresError`.
  - `each skip publishes a notice`: track 1 fails (`ytFailure(unavailable…)`) and track 2 plays → `state.notice!.trackTitle == track1.title`. The notice is null after the next successful start of a third track.
  - `a late engine error from the previous source is ignored`: start A, start B, then `backend.emitError()` tagged with A's generation (emit it before B's `setSource` completes) → B is neither re-resolved nor skipped.
  - `completed well before the end is treated as an engine error`: duration 200 s, position 30 s, `completed` → one fresh-stream retry of the same entry, not `_advance`.
  - `completed within 5 s of the end advances normally`: position 197 s.
  - The existing tests for network halt, retry once and "halts queue on extractor" still pass.
- [ ] **Step 2: Run** `flutter test test/player/player_service_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement**:
  - In `_tryStart`, when the entry differs from the one loaded in the backend, `await _backend.pause()` before showing the target, and mark `_loaded = false`.
  - In `_startFirstPlayable`, count consecutive failed starts across the call. Reset the count on a successful start. At 3, stop with `tooManyFailuresError`. A single explicitly chosen song that fails still reports its own reason, not `noPlayableFilesError`, when it is a YouTube track.
  - Capture `_generation` when an error arrives and drop it if it changed (the parked fix).
  - Early completion: `position < duration - 5 s` with a known duration counts as an engine error.
  - Log every skip with the reason (`AppLog.w('Skipping <id>: <reason>')`), so an exported log explains it.
- [ ] **Step 4: Snack copy** (`player_error_snacks.dart`): a notice shows **"Skipped '<title>' — <reason>"**, where `<reason>` is the `ytErrorUserMessage` copy for YouTube failures and "file is missing" for local ones. The new error shows **"Stopped — 3 songs in a row couldn't play. <last reason>"**. Add widget tests for both.
- [ ] **Step 5: Run** `flutter test test/player test/ui/shell`. Expected: PASS.
- [ ] **Step 6: Commit** `fix: show the song that is really playing and stop after 3 failed songs`.

---

### Task 3: Sharp YouTube artwork, and no download time cap on slow links

**Root cause:**
- The flat-playlist JSON offers thumbnails of at most 336×188 px.
- `pickThumbnail` takes the largest of those, so `squareCrop` leaves a 188 px cover that Now Playing stretches to about 1000 px.
- **Parked from Plan 2:** `httpDownload` has a 10-minute total cap, so the yt-dlp install fails below about 0.5 Mbit/s.

**Files:**
- Modify:
  - `lib/youtube/yt_json.dart`
  - `lib/youtube/thumbnail_fetcher.dart`
  - `lib/library/art_cache.dart`
  - `lib/youtube/yt_import_service.dart`
  - `lib/youtube/ytdlp_installer.dart` (`httpDownload`)
  - `lib/main.dart` (the stream-metadata hook)
- Test: `test/youtube/yt_json_test.dart`, `test/youtube/thumbnail_fetcher_test.dart`, `test/library/art_cache_test.dart`, `test/youtube/yt_import_service_test.dart`, `test/youtube/ytdlp_installer_test.dart`

**Interfaces:**
- Produces:
  - `List<String> thumbnailCandidates(String videoId, String? flatThumbnail)`, which returns, in order:
    1. `https://i.ytimg.com/vi/<id>/maxresdefault.jpg`
    2. `https://i.ytimg.com/vi/<id>/hq720.jpg`
    3. `https://i.ytimg.com/vi/<id>/sddefault.jpg`
    4. the flat thumbnail
  - `ThumbnailFetcher.fetchBest(List<String> urls) → Future<String?>`, which tries each in turn. A 404, or YouTube's 120×90 "no thumbnail" placeholder, counts as a miss.
  - `ArtCache.maxSide = 720`.
  - Art refs written by this plan start with `yt2-`. A YouTube track whose `artworkRef` doesn't start with `yt2-` gets its art refetched the next time it is played, downloaded or synced.
  - `httpDownload(..., {Duration stallTimeout = const Duration(seconds: 60), Duration? totalTimeout})` fails only after 60 s with no bytes received. The installer passes no `totalTimeout`; thumbnails keep their 15 s total.

- [ ] **Step 1: Write failing tests**:
  - `thumbnailCandidates('abc', 'x.jpg')` returns the four urls above in order.
  - `fetchBest` with the first url returning 404 and the second returning a 1280×720 image → it stores a 720×720 square and the ref starts with `yt2-`.
  - `sddefault` (640×480 with black letterbox bars): letterbox removal crops the centre 16:9 region before the square crop. Test with a synthetic 640×480 image whose top and bottom 60 px are black: the stored image's corner pixels are not black.
  - `ArtCache.put` downsizes 1280×720 input to ≤ 720 px.
  - Import: the thumbnail pass calls `fetchBest` with the candidates for each needed video.
  - Sync, plus the metadata hook: a track with a ref `sq-…` is refetched, and a track with `yt2-…` is not.
  - `httpDownload` with a fake server that trickles one byte every 10 s for 15 minutes succeeds. One that stalls for 61 s fails with a `TimeoutException`.
- [ ] **Step 2: Run** the listed test files. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The letterbox crop: when the aspect ratio is 4:3, take the centre `w × w·9/16` band first.
  - The art upgrade runs in the same background thumbnail pass that import and sync already use. The play/download hook calls it fire-and-forget, with concurrency 6 as before.
- [ ] **Step 4: Run** `flutter test test/youtube test/library`. Expected: PASS.
- [ ] **Step 5: Commit** `fix: sharp YouTube covers; yt-dlp download fails only on a stall`.

---

### Task 4: Android "Add music folder" opens the picker and explains failures

**Root cause:**
- `android_file_picker` 2.1.1's `getDirectoryPath` catches every `PlatformException` and returns null: `already_active`, `no_activity`, `unknown_path` (Downloads, SD card), `explorer_not_found`.
- `addMusicFolder` treats null as "cancelled", so the user sees nothing at all.
- On Android the plan therefore uses its own `ACTION_OPEN_DOCUMENT_TREE` channel, which reports each outcome.

**Files:**
- Create:
  - `android/app/src/main/kotlin/com/songies/songies/FolderPickerPlugin.kt`
  - `lib/ui/library/android_folder_picker.dart`
- Modify:
  - `android/app/src/main/kotlin/com/songies/songies/MainActivity.kt` (register it, and forward `onActivityResult`, calling `super` for other request codes)
  - `lib/ui/library/pickers.dart`
  - `lib/ui/library/add_folder_flow.dart`
- Test: `test/ui/library/add_folder_flow_test.dart`, `test/ui/library/android_folder_picker_test.dart`

**Interfaces:**
- Produces:
  - `sealed class FolderPick`, with the subclasses `FolderPicked(String path)`, `FolderPickCancelled()` and `FolderPickFailed(FolderPickError error, String? detail)`.
  - `enum FolderPickError { unsupportedLocation, noFileManager, busy, unknown }`.
  - `typedef FolderPicker = Future<FolderPick> Function()`. This is a changed signature; update every caller and fake.
  - Channel `songies/folder_picker`, method `pick` → `{"path": String}`, `{"cancelled": true}` or a `PlatformException` code from `unsupported_location | no_file_manager | busy`.
- Kotlin path rules:
  - A tree URI `primary:<rel>` maps to `/storage/emulated/0/<rel>`.
  - `<UUID>:<rel>` maps to `/storage/<UUID>/<rel>`.
  - Authorities other than `com.android.externalstorage.documents` (Downloads, cloud providers) fail with `unsupported_location`.

- [ ] **Step 1: Write failing tests**:
  - The Dart channel mapping, with the channel mocked via `TestDefaultBinaryMessengerBinding`: each of the three result shapes and each error code maps to the matching `FolderPick`.
  - `addMusicFolder`:
    - `FolderPickFailed(unsupportedLocation)` → the snack **"That folder can't be used — pick one under Internal storage or the SD card (not Downloads or a cloud folder)"**.
    - `noFileManager` → **"No file manager found to pick a folder"**.
    - `busy` → **"The folder picker is already open"**.
    - `unknown` → **"Couldn't open the folder picker"**.
    - `FolderPickCancelled` → nothing shown.
    - A permission refusal still shows the existing dialog.
  - The scan summary for 0 files found says **"No MP3 files in <name>"**. Songies plays `.mp3` only: spec §2.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The Kotlin side uses `startActivityForResult` with its own request code. A second `pick` while one is pending → `busy`.
  - Desktop wraps `file_picker` into `FolderPick` (null → cancelled).
  - Log every outcome with `AppLog.i('Folder pick: <outcome>')`.
- [ ] **Step 4: Run** `flutter test test/ui/library` and `flutter build apk --debug`. Expected: PASS and a build.
- [ ] **Step 5: Add to `docs/manual-test-checklist.md`** (Android):
  - "Library → + → Add music folder opens the system folder picker."
  - "Picking Music adds its MP3s."
  - "Picking Downloads shows the 'can't be used' message."
- [ ] **Step 6: Commit** `fix: Android folder picker opens and reports why it can't`.

---

### Task 5: Download data — schema v4 and `DownloadRepository`

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart`, `lib/player/track_resolver.dart` (doc only)
- Create: `lib/downloads/download_repository.dart`
- Test: `test/data/migration_test.dart`, `test/downloads/download_repository_test.dart`, `test/player/composite_track_resolver_test.dart`

**Interfaces:**
- Schema v4:
  - New table `PlaylistDevicePrefs(playlistId TEXT PK, downloadEnabled BOOL default false)`.
  - New `LocalFiles` columns: `requestedAt INT nullable` and `manual BOOL default false`.
  - Migration `if (from < 4)`: create the table and add both columns.
- YouTube download rows reuse `local_files`:
  - `path` is `''` until done.
  - `state` is one of `queued | downloading | done | failed`.
  - `bytes`, `mtimeMs = 0`, and `error` hold the user message.
- Produces (`DownloadRepository(AppDatabase db)`):
  - `Future<int> setPlaylistDownload(String playlistId, bool enabled)`: enabling queues every active-entry YouTube track that is not `unavailable` and not already queued/downloading/done, and returns the number newly queued. Disabling only clears the pref.
  - `Future<List<String>> exclusiveFiles(String playlistId)`: the track ids whose done files no other enabled playlist and no `manual` row needs.
  - `Future<int> removeFiles(List<String> trackIds, Directory ytDir)`: deletes the files and the rows (a queued or failed row is just deleted) and returns the bytes freed.
  - `Future<void> dropUnwanted()`: deletes `queued`/`failed` rows no enabled playlist and no manual request still wants.
  - `Future<bool> downloadTrack(String trackId)`: sets `manual = true` and queues if not done. It returns false for a non-YouTube or unavailable track.
  - `Future<void> removeTrackDownload(String trackId, Directory ytDir)`: clears `manual`, and deletes the file unless an enabled playlist contains the track.
  - `Future<int> queueAdded(String playlistId, List<String> trackIds)`: a no-op unless the playlist is enabled.
  - `Future<void> retryFailed({String? playlistId})`.
  - Queue moves:
    - `Future<List<LocalFile>> nextQueued(int limit)`: oldest `requestedAt` first.
    - `markDownloading(id)`.
    - `markDone(id, path, bytes)`.
    - `markFailed(id, message)`.
    - `requeue(id)`.
    - `resetInterrupted()`: `downloading` → `queued`.
    - `reconcileMissing()`: a `done` YouTube row whose file is gone → `queued` if wanted, else deleted.
  - Watchers:
    - `Stream<Set<String>> watchEnabledPlaylists()`.
    - `Stream<PlaylistDownloadStatus> watchPlaylist(String playlistId)`, with `PlaylistDownloadStatus { enabled, total, done, queued, downloading, failed, bytes }` and `total` counted over active, available YouTube entries.
    - `Stream<Map<String, String>> watchTrackStates(Iterable<String> trackIds)`.
    - `Stream<int> watchTotalBytes()`.
    - `Stream<List<(String playlistId, int bytes)>> watchBytesPerPlaylist()`.

- [ ] **Step 1: Write failing tests** (in-memory db, `test_db.dart`):
  - Migration v3 → v4 keeps existing rows, and the new columns read as null/false.
  - Enabling a playlist with 3 YouTube tracks (1 unavailable) and 1 local track → 2 queued rows, `requestedAt` set, and the return value is 2. Enabling again → 0.
  - The same track in playlists A and B (both enabled) → one row. `exclusiveFiles(A)` doesn't include it. After B is disabled, it does.
  - A manual row is never in `exclusiveFiles`.
  - `nextQueued` order is FIFO by `requestedAt`.
  - `resetInterrupted` moves `downloading` → `queued`.
  - `reconcileMissing`: a done row with a missing file and an enabled playlist → queued. Without one → the row is deleted.
  - `queueAdded` on a disabled playlist → 0.
  - `watchPlaylist` emits a new status after `markDone`.
  - The resolver (Review Focus 5): a `downloading` row with `path ''` → `CompositeTrackResolver` streams. A `done` row with an existing file → `FileSource`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the tables, the migration (then run `dart run build_runner build`) and the repository. Every multi-row change runs inside one `guardDb` transaction.
- [ ] **Step 4: Run** `flutter test test/data test/downloads test/player`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: schema v4 download rows, per-device download switch and repository`.

---

### Task 6: yt-dlp downloads with live progress

**Files:**
- Modify:
  - `lib/youtube/ytdlp_runner.dart`
  - `lib/youtube/desktop_ytdlp_runner.dart`
  - `lib/youtube/android_ytdlp_runner.dart`
  - `lib/youtube/ytdlp_client.dart`
  - `lib/youtube/yt_models.dart`
  - `android/app/src/main/kotlin/com/songies/songies/YtDlpPlugin.kt`
  - `test/helpers/fake_ytdlp_runner.dart`
  - `docs/yt-dlp-notes.md`
- Create: `test/fixtures/ytdlp/download_stdout.txt`, `test/fixtures/ytdlp/download_stderr_429.txt`, `test/fixtures/ytdlp/download_stderr_nospace.txt`
- Test: `test/youtube/ytdlp_client_download_test.dart`, `test/youtube/desktop_ytdlp_runner_test.dart`, `test/youtube/android_ytdlp_runner_test.dart`

**Interfaces:**
- `YtDlpRunner.run(List<String> args, {Duration? timeout, void Function(String line)? onLine, String? processId})`:
  - `onLine` gets each stdout line as it arrives.
  - `stdout` in the result still holds everything.
- New method: `Future<void> YtDlpRunner.cancel(String processId)`. Desktop kills the process; Android calls the existing `cancel`.
- Android delivers lines through an `EventChannel('songies/ytdlp_lines')` with events `{processId, line}`, from youtubedl-android's `execute(request, processId) { progress, eta, line -> }` callback, posted on the main thread.
- `YtErrorKind` gains `throttled` and `diskFull`:
  - `throttled`: stderr contains `HTTP Error 429`.
  - `diskFull`: `No space left on device` or `Errno 28`.
- Produces:
  - `YtDlpClient.download(String videoId, Directory outDir, {required String processId, void Function(int downloaded, int? total)? onProgress, Duration stallTimeout = const Duration(minutes: 2)}) → Future<Result<YtDownload>>`.
  - `YtDownload { String path; int bytes; String? title; String? artist; String? album; int? durationMs }`.
  - If no output line arrives for `stallTimeout`, the process is cancelled → `Err(network)`.
- Arguments (verify on the host in Step 1 and record them in `docs/yt-dlp-notes.md`):
  ```
  -f bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio --no-playlist --continue --no-mtime
  --newline --progress --progress-template "download:songies-progress %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s"
  -o "<outDir>/%(id)s.%(ext)s"
  --print "after_move:songies-done %(.{filepath,title,artist,track,album,duration})j"
  https://music.youtube.com/watch?v=<id>
  ```
  - `title` = `track` ?? `title`. `artist` is cleaned with `cleanArtist`.
  - `NA` values parse as null.

- [ ] **Step 1: Probe on the host** (the network is allowed for this step only):
  - Install yt-dlp into a scratch dir with the app's own installer, or use the system one.
  - Run the arguments above on one known public video (take an id from the existing fixtures).
  - Save stdout and stderr into the fixture files.
  - Confirm that `--print after_move` still shows progress lines with `--progress`, and that the file lands as `<id>.webm` or `<id>.m4a`.
  - Record any change to the arguments in `docs/yt-dlp-notes.md` under "Downloads". The probe output overrides this plan where they differ.
- [ ] **Step 2: Write failing tests**:
  - The client against `FakeYtDlpRunner` replaying `download_stdout.txt` line by line: `onProgress` is called in increasing order, and the result has the right path, bytes (from the fake file), artist and album.
  - The 429 fixture → `Err` kind `throttled`. The no-space fixture → `diskFull`.
  - Stall: `fake_async`, no lines for 2 min → `cancel(processId)` is called and the result is `network`.
  - Desktop runner: `onLine` order with a fake process that writes 3 lines; `cancel` kills it.
  - Android runner: lines for another `processId` are ignored.
- [ ] **Step 3: Run** them. Expected: FAIL.
- [ ] **Step 4: Implement.**
  - The desktop runner moves to `Process.start` with line decoding (`utf8` + `LineSplitter`) on stdout, and keeps its existing timeout and kill path.
  - Kotlin: the `run` call passes a callback that posts `{processId, line}` to the event sink.
- [ ] **Step 5: Run** `flutter test test/youtube` and `flutter build apk --debug`. Expected: PASS and a build.
- [ ] **Step 6: Commit** `feat: yt-dlp downloads with streamed progress and cancel`.

---

### Task 7: `DownloadService` — the queue

**Files:**
- Create: `lib/downloads/download_service.dart`, `lib/downloads/download_notifier.dart` (the `DownloadNotifier` interface and `NoopDownloadNotifier` only; Task 8 adds the Android one)
- Modify:
  - `lib/providers.dart`
  - `lib/main.dart` (construct it and call `start()` after the db opens, then wire the sync hook)
  - `lib/ui/playlist/yt_playlist_actions.dart` (after a successful sync, `queueAdded(playlistId, result.addedTrackIds)` and then `kick()`)
- Test: `test/downloads/download_service_test.dart`

**Interfaces:**
- Consumes: `DownloadRepository` (Task 5), `YtDlpClient.download` (Task 6), `NetworkStatus`, `SettingsRepository` (`kWifiOnly`), `LibraryRepository.updateTrackMetadata` / `markUnavailable`, and the Task 3 art upgrade hook.
- Produces:
  - `DownloadService({required DownloadRepository repo, required YtDlpClient client, required NetworkStatus network, required SettingsRepository settings, required Directory ytDir, required int concurrency, required Future<void> Function(String trackId, YtDownload d) onDownloaded, required Future<void> Function(String trackId) onUnavailable, DownloadNotifier? notifier, bool wifiOnlyFallback})`.
  - `Future<void> start()`: runs `resetInterrupted`, `reconcileMissing` and `dropUnwanted`, then `kick`.
  - `void kick()`: fills free slots.
  - `Future<void> cancelUnwanted()`: cancels running downloads whose rows were removed, and deletes their `<id>.*.part`.
  - `Future<void> resume()`: clears a disk-full pause or retries now.
  - `Stream<DownloadSnapshot> get snapshots` (a new listener first gets the current value), and `DownloadSnapshot get current`.
  - `Future<void> dispose()`.
- The snapshot types:
  - `DownloadSnapshot { int queued; int active; int completedThisRun; int failedThisRun; int totalThisRun; Map<String, TrackProgress> progress; DownloadPause? pause; bool extractorFailing; String? currentTitle }`.
  - `TrackProgress { int downloaded; int? total; double? get fraction }`.
  - `DownloadPause { DownloadPauseReason reason; DateTime? resumesAt }`.
  - `enum DownloadPauseReason { wifiOnly, offline, throttled, diskFull }`.
  - A "run" starts when the queue goes from empty to non-empty and ends when it's empty again. The notification shows `completedThisRun / totalThisRun`.
- Behaviour:
  - Concurrency is 2 on Android and 3 on desktop.
  - Starting a slot: `markDownloading`, then `client.download(processId: 'dl-<trackId>')`.
  - On `Ok`: `markDone`, then `onDownloaded` (metadata + art).
  - `notFound` → `onUnavailable`, delete the row, continue.
  - `extractor` / `unknown` → `markFailed(ytErrorUserMessage)` and `extractorFailing = true` until the next success.
  - `throttled` → requeue, and pause every slot with backoff 30 s, 60 s, 120 s, … capped at 10 min. The backoff resets after a success.
  - `network`, or a network change to offline → requeue and pause `offline`, then resume on the next non-offline change.
  - `NetworkKind.mobile` with Wi-Fi only → cancel the running processes, requeue and pause `wifiOnly`. Resume on a `wifi`/`other` change or when the setting turns off (`watchBool`).
  - `diskFull` → requeue and pause `diskFull` until `resume()`.
  - The repository watchers (pref changes, `removeTrackDownload`) call `cancelUnwanted` and `kick`. No polling.

- [ ] **Step 1: Write failing tests** (`fake_async`, fake runner and network, in-memory db):
  - 5 queued rows on desktop → exactly 3 run at once, FIFO, and all are done at the end with `completedThisRun == 5`.
  - Android concurrency 2.
  - Progress lines → `snapshot.progress[trackId].fraction` rises.
  - 429 on one → all pause with `resumesAt` 30 s later; the next 429 waits 60 s; it caps at 10 min; a success resets it.
  - Mobile with Wi-Fi only → the running processes are cancelled, rows `queued` (not failed), pause `wifiOnly`. A wifi event → resumes. The setting turned off while on mobile → resumes.
  - Offline mid-download → pause `offline`; online → resume.
  - Disk full → pause until `resume()`.
  - notFound → `onUnavailable` is called, and the queue continues with the next one.
  - Extractor → failed row and `extractorFailing`; a later success clears it.
  - Review Focus 1: disabling the playlist mid-download → `cancel` is called, the `.part` is deleted, and the row never becomes done even if the fake runner then reports success.
  - Review Focus 3: `start()` with a `downloading` row → it runs again.
  - Sync hook: a sync result with 2 added ids on an enabled playlist → 2 new downloads.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** One `_pump()` loop driven by events; no `Timer.periodic`. The backoff uses a single `Timer` that's cancelled on dispose.
- [ ] **Step 4: Run** `flutter test`. Expected: all tests pass, and `flutter analyze` is clean.
- [ ] **Step 5: Commit** `feat: download queue with Wi-Fi only, backoff and resume`.

---

### Task 8: Android download notification and foreground service

**Files:**
- Create:
  - `android/app/src/main/kotlin/com/songies/songies/DownloadForegroundService.kt`
  - `android/app/src/main/kotlin/com/songies/songies/DownloadNotifierPlugin.kt`
  - `lib/downloads/android_download_notifier.dart`
- Modify:
  - `android/app/src/main/AndroidManifest.xml`: add `FOREGROUND_SERVICE_DATA_SYNC`, plus `<service android:name=".DownloadForegroundService" android:foregroundServiceType="dataSync" android:exported="false"/>`.
  - `MainActivity.kt`
  - `lib/main.dart`
- Test: `test/downloads/download_notifier_test.dart`

**Interfaces:**
- Produces:
  - Uses Task 7's `abstract class DownloadNotifier { Future<void> update(DownloadSnapshot s); Future<void> finished(int completed, int failed); }`.
  - This task adds `AndroidDownloadNotifier` (channel `songies/download_notifier`, methods `update` and `finished`). Desktop keeps `NoopDownloadNotifier`.
  - The Dart side throttles `update` to at most one call per second.
- Notification content (channel id `downloads`, name "Downloads", low importance, no sound):
  - **Running:** title **"Downloading songs"**, text **"<done> of <total> · <currentTitle>"**, a determinate progress bar of `done/total`, ongoing.
  - **Paused:** text **"Paused — waiting for Wi-Fi"**, **"Paused — offline"**, **"Paused — YouTube is limiting downloads, retrying in <m> min"** or **"Paused — storage is full"**.
  - **Finished:** the service stops and posts a dismissible **"Downloaded <n> songs"**, plus **" · <f> failed"** if any failed.
  - Tapping the notification opens the app.
- The service starts on the first `update` with `active + queued > 0` and stops on `finished`.
- Notification permission: the first time the user enables a download or downloads a song, request `Permission.notification` on API 33+. A refusal never blocks downloading.

- [ ] **Step 1: Write failing tests** (mocked channel):
  - A snapshot sequence → `update` payloads with the exact texts above, throttled to 1 per second under `fake_async`.
  - The run ending → one `finished(5, 1)` call.
  - Desktop gets `NoopDownloadNotifier` from the provider when `isAndroidProvider` is false.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the Kotlin side, using `NotificationCompat.Builder` and `ServiceCompat.startForeground(..., FOREGROUND_SERVICE_TYPE_DATA_SYNC)` on API 29+. Plus the Dart side.
- [ ] **Step 4: Run** `flutter test test/downloads` and `flutter build apk --release`. Expected: PASS and a build.
- [ ] **Step 5: Commit** `feat: Android download progress notification`.

---

### Task 9: Download UI everywhere

**Files:**
- Create:
  - `lib/ui/downloads/download_toggle.dart`
  - `lib/ui/downloads/download_status_line.dart`
  - `lib/ui/downloads/track_download_icon.dart`
  - `lib/ui/downloads/download_ring.dart`
  - `lib/ui/downloads/downloads_banner.dart`
  - `lib/ui/downloads/downloads_sheet.dart`
  - `lib/ui/settings/downloads_settings.dart`
- Modify:
  - `lib/ui/playlist/playlist_page.dart`
  - `lib/ui/home/home_page.dart`
  - `lib/ui/library/library_page.dart` (the Downloaded chip)
  - `lib/ui/shell/sidebar.dart`
  - `lib/ui/shell/phone_shell.dart` / `desktop_shell.dart` (the banner and the active indicator)
  - `lib/ui/now_playing/now_playing_header.dart`
  - `lib/ui/settings/settings_page.dart`
  - `lib/providers.dart`
- Test: `test/ui/downloads/*_test.dart`, `test/ui/playlist/playlist_page_test.dart`, `test/ui/library/library_page_test.dart`

**Interfaces:**
- Consumes: `DownloadRepository` watchers, `DownloadService.snapshots`, `ytErrorUserMessage`.
- Providers:
  - `downloadSnapshotProvider` (StreamProvider)
  - `playlistDownloadProvider.family(playlistId)`
  - `trackDownloadStatesProvider.family(playlistId)` → `Map<trackId, state>`
- UI copy (exact):
  - **Playlist hero (YouTube playlists):**
    - A **Download** toggle: an icon button with a down-arrow in a circle, outline when off and filled accent when on.
    - Turning it on queues the songs and shows the snack **"Downloading <n> songs"** ("1 song").
    - Turning it off with files present asks **"Remove downloads?"**: "<n> songs (<size>) are only in this playlist. Remove them from this device?". The buttons are **Keep files** and **Remove**. Either way the pref turns off.
  - **The status line under the hero:**
    - "Downloading <done> of <total> · <size>", with a `LinearProgressIndicator` of the combined fraction, including partial bytes
    - "Downloaded · <total> songs · <size>"
    - "<f> failed · Retry", where tapping Retry calls `retryFailed`
    - the pause texts from Task 8, minus the "Paused — " prefix
  - **Track rows:** a trailing `TrackDownloadIcon`:
    - queued: a muted `schedule` icon
    - downloading: a 16 px circular progress with value `fraction`
    - done: a filled accent `download_done` icon
    - failed: `error_outline`, where a tap shows the error and offers Retry
  - **The track ⋯ menu** (YouTube tracks): **Download** / **Remove download** (D1).
  - **Home and sidebar playlist cards/rows:** a `DownloadRing` (a 14 px ring with value `done/total`). It shows as a filled check when complete and is hidden when off.
  - **The Library filter chip "Downloaded":** playlists with the download enabled.
  - **The app-wide indicator while `active + queued > 0`:**
    - Phone: a slim row above the mini player: "Downloading <done> of <total>", with a thin progress line.
    - Desktop: the same row at the top of the sidebar library list.
    - Tapping it opens `DownloadsSheet`, which lists the active songs with their progress and the queued count, with **Pause downloads** / **Resume** (a pause is a user pause held in memory only and stops new slots) and **Retry failed**.
  - **Banner, when `extractorFailing`:** **"Downloads failing — update yt-dlp?"**. Its action **Update** runs the same update as Settings, and **Dismiss** hides it until the next failure.
  - **Now Playing:** a small `download_done` icon next to the artist when the current track's file is done (spec §11).
  - **Settings → Downloads:**
    - "Wi-Fi only" (moved from the YouTube section; same key)
    - "Downloaded songs · <size>" total
    - a per-playlist list "<name> · <size>"
    - **Pause** / **Resume** downloads
- The service needs a user pause, so add `DownloadService.pauseByUser()` / `resumeByUser()` (in memory), with tests in `download_service_test.dart`.

- [ ] **Step 1: Write failing widget tests**, using fake providers:
  - The toggle on → `setPlaylistDownload(id, true)` and the snack text.
  - The toggle off with exclusive files → the dialog. **Remove** → `removeFiles` with those ids; **Keep files** → no removal.
  - The status-line strings for each state.
  - The track icon for each state.
  - Library's Downloaded chip filters.
  - The indicator shows and hides with the snapshot; the sheet buttons call the service.
  - The banner shows when `extractorFailing`.
  - The Now Playing icon.
  - The Settings sizes are formatted with `formatBytes`.
  - The track menu Download → `downloadTrack`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Rows watch only their own playlist's state map, so there are no per-row streams.
  - `progress` updates rebuild only the ring/icon widgets, via `select`.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass, with no issues.
- [ ] **Step 5: Commit** `feat: download toggle, progress rings, indicator, banner and settings`.

---

### Task 10: Docs, checklist and builds

**Files:** `docs/PROGRESS.md`, `docs/manual-test-checklist.md`, `docs/yt-dlp-notes.md`

- [ ] **Step 1:** Run `flutter test`, `flutter analyze`, `flutter build apk --release` and `flutter build linux --release`. Expected: all pass, no issues, and both builds made. Windows is built on the user's PC.
- [ ] **Step 2:** Run a real-network smoke test on Linux. Import the known test playlist, turn on Download, and wait for 3 songs to finish. Check:
  - `.webm`/`.m4a` files exist in `~/.local/share/songies/library/yt/`.
  - Playing one uses the file (log line `FileSource`).
  - Turning the download off with **Remove** deletes them.
- [ ] **Step 3: Checklist additions:**
  - **Android:**
    - Turning on a playlist download shows the notification with "x of y" and a progress bar.
    - Locking the phone mid-download keeps it running.
    - Wi-Fi off with Wi-Fi only on → "Paused — waiting for Wi-Fi", and it resumes when Wi-Fi returns.
    - Airplane mode → paused offline.
    - Finishing posts "Downloaded n songs".
    - Downloaded songs play in airplane mode.
  - **All platforms:**
    - Home/Library always open their root (Task 1).
    - Skipping shows "Skipped …" (Task 2).
    - Covers are sharp on Now Playing (Task 3).
- [ ] **Step 4: PROGRESS.md:**
  - Mark Plan 3 done, with the rulings and the parked items.
  - Next is Plan 4 (`docs/superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md`).
  - Roadmap renumber: Plan 5 = lyrics, Plan 6 = device sync, Plan 7 = packaging.
- [ ] **Step 5: Commit** `docs: Plan 3 verification, checklist and progress`.
