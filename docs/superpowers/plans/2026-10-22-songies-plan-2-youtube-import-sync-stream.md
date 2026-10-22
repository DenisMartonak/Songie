# Songies Plan 2: YouTube Import, Sync and Streaming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import public/unlisted YouTube Music playlists by link or Android Share, keep them in sync with a "Sync with YouTube" button (append new, flag removed, never undo user edits), and stream their songs ad-free through yt-dlp on Android, Windows and Linux.

**Architecture:** One Dart `YtDlpClient` builds yt-dlp arguments and parses its JSON. It runs on a platform `YtDlpRunner`: `Process` with a managed binary on desktop, and a Kotlin platform channel around `youtubedl-android` on Android. `YtImportService` turns playlist JSON into synced rows (`playlists`, `tracks`, `playlist_entries` and the new `yt_seen`) and runs the §6.2 diff. A `CompositeTrackResolver` plays local files as before and resolves YouTube tracks to short-lived stream URLs (with headers) through a cached `StreamResolver`. `PlayerService` asks it to prefetch the next track about 20 s early.

**Tech Stack:** Flutter 3.47 / Dart 3.13, drift (schema v3), Riverpod, go_router, just_audio + just_audio_media_kit, yt-dlp (desktop binary), `youtubedl-android` (Kotlin), `connectivity_plus`, `http` (or `dart:io` HttpClient).

**Spec:** `docs/superpowers/specs/2026-10-21-songies-design.md` (§6 YouTube import, sync and streaming; §7 "yt-dlp updates"; §11 UI; §12 errors). Plan 1 is complete on branch `plan-1-foundation`. Its decisions and deferred items are in `docs/PROGRESS.md`.

## Global Constraints

- Targets: Android (sideloaded APK, `minSdk 24`, `compileSdk 37`), Windows 10+, Linux (Fedora/Nobara).
- Import accepts **public/unlisted playlist links only, with no sign-in**: `music.youtube.com/playlist?list=…` or `youtube.com/playlist?list=…` (also `www.`/`m.`), plus Android Share text that contains such a link.
- Every synced row write takes its own `SyncStamp.next()` inside one transaction (`guardDb`). Synced rows are never hard-deleted; deletion is `deleted = true`. Device-local tables are unstamped.
- New synced table `yt_seen(id, playlist_id, video_id, sync columns)`, unique `(playlist_id, video_id)`. `schemaVersion` becomes **3**.
- A YouTube track is unique by `yt_video_id`. Re-adding a video whose track row is tombstoned **resurrects** that row (`deleted = false`, new stamp) instead of inserting.
- Sync never re-adds ids already in `yt_seen`, never changes user order, never touches `kept = true` entries, and only appends new ids at the end in YouTube's relative order.
- Stream format selector: `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`. Stream URLs are cached in memory only, until their `expire` query parameter minus **10 min**. They are never written to synced tables.
- The next track's stream is resolved **~20 s** before the current track ends.
- **Wi-Fi only** setting: default **on** on Android, **off** on desktop. On a mobile/metered connection streaming is refused with the message **"Wi-Fi only is on — connect to Wi-Fi to stream"**.
- Desktop yt-dlp binary: `<appData>/bin/yt-dlp.exe` (Windows) or `<appData>/bin/yt-dlp` (Linux). It's downloaded from the official `yt-dlp/yt-dlp` GitHub "latest" release, verified against that release's `SHA2-256SUMS`, and replaced atomically. On Linux a setting can use the system `yt-dlp` from PATH instead.
- **No idle work:** no polling or timers. Import, sync, update, prefetch and resolve run only on user action or during playback.
- Tests never touch the network, YouTube or real audio. Use `FakeYtDlpRunner`, JSON fixtures, fake HTTP and fake connectivity.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Bad input links** (a video link instead of a playlist, a private or deleted playlist, a typo, no network): a clear message and nothing written. Pinned in Tasks 3 and 6.
2. **Unplayable entries inside a playlist** (`[Private video]`, `[Deleted video]`, region-blocked): these must not break the import. They're imported as `unavailable` tracks and skipped during playback with no error loop. Pinned in Tasks 3 and 6.
3. **Large playlists** (1,000+ songs): import completes in one transaction, and the UI stays responsive (no per-row awaits on the UI isolate). Pinned in Task 6.
4. **Streams that fail mid-queue** (expired URL, YouTube error, offline, Wi-Fi only): no hang and no endless skipping. Offline and Wi-Fi-only stop playback with their message instead of skipping through the queue. Pinned in Tasks 7 and 8.
5. **Re-importing a link already in the library**, or the same video in two playlists: no duplicate playlist and one track row. Re-import opens the existing playlist and offers Sync. Pinned in Task 6.

---

## File Structure

```
lib/ui/widgets/page_surface.dart          PageSurface: opaque Material per routed page (ink fix)
lib/youtube/yt_links.dart                 parsePlaylistLink, extractLinkFromSharedText
lib/youtube/yt_models.dart                YtPlaylist, YtEntry, YtStream, YtError kinds
lib/youtube/yt_json.dart                  parsePlaylistJson, parseStreamJson, cleanArtist, pickThumbnail
lib/youtube/ytdlp_runner.dart             YtDlpRunner interface, YtDlpRun result
lib/youtube/ytdlp_client.dart             YtDlpClient: args + parsing + error mapping
lib/youtube/desktop_ytdlp_runner.dart     Process-based runner
lib/youtube/ytdlp_installer.dart          desktop install/update with SHA-256 verification
lib/youtube/android_ytdlp_runner.dart     MethodChannel runner
android/app/src/main/kotlin/com/songies/songies/YtDlpPlugin.kt   youtubedl-android bridge
android/app/src/main/kotlin/com/songies/songies/MainActivity.kt   + share intent channel
lib/youtube/share_intents.dart            Stream<String> of shared links (Android)
lib/youtube/thumbnail_fetcher.dart        download → ArtCache.put(square crop)
lib/youtube/yt_import_service.dart        import + sync diff
lib/player/stream_resolver.dart           StreamResolver (cache, expiry, wifi-only)
lib/player/composite_track_resolver.dart  local files first, then streams
lib/core/connectivity.dart                NetworkStatus interface + connectivity_plus impl
lib/data/settings_repository.dart         typed get/set over the Settings table
lib/ui/library/import_dialog.dart         paste-link dialog + progress
lib/ui/playlist/yt_playlist_actions.dart  Sync button, last-synced text, removed-row actions
lib/ui/settings/youtube_settings.dart     yt-dlp version/update, Wi-Fi only, system yt-dlp (Linux)
test/fixtures/ytdlp/*.json                captured yt-dlp outputs (Task 2)
test/helpers/fake_ytdlp_runner.dart
```

---

### Task 1: Page surfaces (ink bleed fix) + small Plan 1 polish

**Root cause (from investigation):**
- No routed page (Home, Search, Library, Playlist, Settings) has its own `Material`/`Scaffold`. Every `InkWell` paints on the shell's `Scaffold` Material, which sits below the branch `Navigator`.
- A tapped Home card's ripple therefore keeps spreading on that shared surface. It shows through the pushed Playlist page, which has no background of its own.

**Files:**
- Create: `lib/ui/widgets/page_surface.dart`
- Modify: `lib/router.dart` (every page `builder`), `lib/ui/settings/storage_usage.dart` (`formatBytes`), `lib/ui/settings/settings_page.dart` (rescan de-dupe), `lib/ui/shell/player_error_snacks.dart`, `lib/player/player_service.dart` (engine-failure wording)
- Test: `test/ui/page_surface_test.dart`, plus existing settings and shell tests

**Interfaces:**
- Produces: `class PageSurface extends StatelessWidget { const PageSurface({required Widget child}); }`. It renders `Material(color: SongiesColors.background, child: child)`.

- [ ] **Step 1: Write failing tests**
  - `page_surface_test.dart`:
    - Pump the real router at 400×800 and push `/home/playlist/p1`.
    - Assert that `Material.of(<element inside PlaylistPage>)` is not the shell Scaffold's Material, i.e. it's a descendant of the branch `Navigator`.
    - Assert that the same holds for an InkWell inside HomePage.
  - Settings: `formatBytes(1048575) == '1.0 MB'`; `formatBytes(1023) == '1023 B'`.
  - Settings: two quick taps on **Rescan** of the same folder enqueue it once while that scan is pending.
  - Player: when the engine fails on every track, the snack bar text is **"Couldn't play these songs"**. When files are missing it stays "Couldn't play — the song files are missing". Give the engine-failure path its own error constant.
- [ ] **Step 2: Run** `flutter test test/ui/page_surface_test.dart test/ui/settings_test.dart test/ui/shell_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `router.dart` wraps each `GoRoute` builder's page in `PageSurface`. Now Playing keeps its own Scaffold.
  - `formatBytes` picks the unit after rounding.
  - Settings keeps a `Set<String>` of folders queued from this page and skips duplicates until each enqueue future completes.
  - Add `PlayerService.engineFailedError = 'Engine failed on every track'`, used where engine failures exhaust the queue, mapped in `playerErrorMessage` to "Couldn't play these songs".
- [ ] **Step 4: Run** the full `flutter test` and `flutter analyze`. Expected: all PASS, no issues.
- [ ] **Step 5: Commit** `fix: give each page its own surface so ripples don't bleed; small polish`.

---

### Task 2: yt-dlp feasibility probe (decides the exact arguments)

A probe whose output is **knowledge and fixtures, not app code**. YouTube changes often, and yt-dlp may now need extra pieces (for example a JavaScript runtime for some YouTube formats), so pin reality first.

**Files:**
- Create: `docs/yt-dlp-notes.md`, `test/fixtures/ytdlp/playlist_flat.json`, `test/fixtures/ytdlp/stream_opus.json`, `test/fixtures/ytdlp/playlist_with_private.json` (trim each to ≤ 50 KB: keep ≤ 5 entries and the fields the parser needs)
- Nothing in `lib/`.

- [ ] **Step 1:** In the scratchpad (not the repo), download the latest official `yt-dlp.exe` and the release's `SHA2-256SUMS` from `https://github.com/yt-dlp/yt-dlp/releases/latest/download/`. Verify the hash.
- [ ] **Step 2:** Run against one public YouTube Music playlist (any public playlist URL; record which):
  - `yt-dlp --flat-playlist -J <playlist url>` → save as `playlist_flat.json`.
  - `yt-dlp -J -f "bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio" --no-playlist https://music.youtube.com/watch?v=<one id>` → save as `stream_opus.json`. Record the selected format's `url`, `http_headers`, `ext`, `acodec`, `abr`, and the `expire` query parameter.
  - The same flat command on a playlist containing a private or deleted video (create or find one) → save as `playlist_with_private.json`.
  - A video link and a nonexistent playlist id. Record stderr text and exit codes.
- [ ] **Step 3:** Record any warnings, especially about a missing JS runtime, PO tokens or SABR, and whether audio formats were still returned. If audio formats are **not** available without extra components, **stop and report BLOCKED** with the exact messages. The controller decides with the user.
- [ ] **Step 4:** Record for Android the current Maven coordinates and latest version of `youtubedl-android` (the JunkFood02 fork `io.github.junkfood02.youtubedl-android:library` used by Seal, or the original `com.github.yausername.youtubedl-android` if that's current). Also record its init, execute and update APIs (`YoutubeDL.getInstance().init(context)`, `execute(YoutubeDLRequest)`, `updateYoutubeDL(context, …)`), and whether a separate `ffmpeg` artifact is needed (it shouldn't be).
- [ ] **Step 5:** Write `docs/yt-dlp-notes.md`: working commands, exit codes and stderr patterns for "not a playlist", "playlist does not exist", "private video" and "network error", the header requirement, Android coordinates, and any caveats. **Commit** `docs: record yt-dlp behaviour and fixtures for Plan 2`.

---

### Task 3: yt-dlp models, link parsing, JSON parsing, client + fake runner

**Files:**
- Create: `lib/youtube/{yt_links,yt_models,yt_json,ytdlp_runner,ytdlp_client}.dart`, `test/helpers/fake_ytdlp_runner.dart`
- Test: `test/youtube/{yt_links,yt_json,ytdlp_client}_test.dart`

**Interfaces:**
- Consumes: Task 2 fixtures and `docs/yt-dlp-notes.md` (the error patterns).
- Produces:
  - `String? parsePlaylistLink(String input)`: returns the canonical `https://music.youtube.com/playlist?list=<id>`, or null. It accepts `music.youtube.com`, `youtube.com`, `www.`, `m.`, `youtu.be` with `list=`, and surrounding whitespace.
  - `String? extractLinkFromSharedText(String text)`: finds the first URL and passes it through `parsePlaylistLink`.
  - `class YtEntry { String videoId; String title; String artist; int durationMs; String? thumbnailUrl; bool unavailable; }`
  - `class YtPlaylist { String id; String title; List<YtEntry> entries; }`
  - `class YtStream { Uri url; Map<String,String> headers; DateTime? expiresAt; String? title; String? artist; String? album; int? durationMs; }`
  - `enum YtErrorKind { notAPlaylist, notFound, network, extractor, missingBinary, unknown }`. It maps to `Failure` with `FailureKind.network` for `network`, `notFound` for `notFound`/`notAPlaylist`, and `unknown` otherwise. Put the kind name in `Failure.message` as a prefix `ytdlp:<kind>:`.
  - `YtPlaylist parsePlaylistJson(String json)`, `YtStream parseStreamJson(String json)`, `String cleanArtist(String channel)` (strips a trailing ` - Topic`), `String? pickThumbnail(List thumbnails)` (prefers square, else the largest).
  - `class YtDlpRun { int exitCode; String stdout; String stderr; }`; `abstract class YtDlpRunner { Future<YtDlpRun> run(List<String> args); Future<String?> version(); Future<Result<void>> update(); }`
  - `class YtDlpClient { YtDlpClient(YtDlpRunner runner); Future<Result<YtPlaylist>> fetchPlaylist(String canonicalUrl); Future<Result<YtStream>> resolveStream(String videoId); }`
  - `FakeYtDlpRunner`: canned `YtDlpRun` per argument pattern, a call log, configurable `version`/`update`.
- Rules:
  - Entries whose title is `[Private video]` or `[Deleted video]`, or that have no duration and no channel, become `unavailable: true`. They are kept so sync bookkeeping stays complete.
  - `expiresAt` comes from the `expire` query parameter (unix seconds).
  - Exact args come from `docs/yt-dlp-notes.md`. The defaults are `['--flat-playlist','-J',url]` and `['-J','--no-playlist','-f',<selector>,'https://music.youtube.com/watch?v=<id>']`.

- [ ] **Step 1: Write failing tests** with the fixtures:
  - Link parsing: these all give the same canonical link:
    - `https://music.youtube.com/playlist?list=PLx`
    - `https://www.youtube.com/playlist?list=PLx&si=abc`
    - `  youtube.com/playlist?list=PLx  `
  - `https://www.youtube.com/watch?v=abc` → null; `hello` → null.
  - `extractLinkFromSharedText('Check this https://music.youtube.com/playlist?list=PLx')` → canonical.
  - `parsePlaylistJson(playlist_flat)`:
    - entry count matches the fixture
    - first entry's id, title and duration (ms) match
    - an artist taken from a `X - Topic` channel becomes `X`
  - `parsePlaylistJson(playlist_with_private)`: the private entry has `unavailable == true` and the others are false.
  - `parseStreamJson(stream_opus)`: url non-empty, headers include `User-Agent`, `expiresAt` equals the `expire` param.
  - The client maps each stderr pattern in the notes to its `YtErrorKind`. A runner throw (binary missing) maps to `missingBinary`.
- [ ] **Step 2: Run** `flutter test test/youtube`. Expected: FAIL.
- [ ] **Step 3: Implement.** Pure Dart only, no `dart:io` in models or parsing.
- [ ] **Step 4: Run** `flutter test test/youtube`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add yt-dlp client, models and link parsing`.

---

### Task 4: Desktop runner + installer/updater

**Files:**
- Create: `lib/youtube/desktop_ytdlp_runner.dart`, `lib/youtube/ytdlp_installer.dart`
- Test: `test/youtube/ytdlp_installer_test.dart`, `test/youtube/desktop_ytdlp_runner_test.dart`

**Interfaces:**
- Consumes: `YtDlpRunner`, `YtDlpRun` (Task 3), `AppPaths.bin`.
- Produces:
  - `class YtDlpInstaller { YtDlpInstaller(Directory binDir, {required Future<List<int>> Function(Uri) download, required bool isWindows}); File get binary; Future<Result<String>> installOrUpdate(); }`. It downloads `yt-dlp.exe` or `yt-dlp_linux` plus `SHA2-256SUMS` from `https://github.com/yt-dlp/yt-dlp/releases/latest/download/`, checks the matching line's hash, writes `<name>.download`, makes it executable on Linux (`chmod +x` via `Process.run`), renames over the old file, and returns the new version string from running `--version`.
  - `class DesktopYtDlpRunner implements YtDlpRunner { DesktopYtDlpRunner({required File Function() binary, required YtDlpInstaller installer, String? systemBinary}); }`. It uses `systemBinary` when set (Linux "use system yt-dlp"). It runs with `Process.run`, `runInShell: false`, and UTF-8 decoding. A missing binary throws `YtDlpMissing`, which the client maps to `missingBinary`.
- Rules:
  - A hash mismatch → `Err(io, 'yt-dlp download failed verification')` with the old binary untouched.
  - The download function is injected, so tests use bytes and no network.

- [ ] **Step 1: Write failing tests:**
  - A good hash installs, and the binary file exists with exactly the downloaded bytes.
  - A bad hash → Err, and an existing binary is unchanged.
  - A download throw → Err(network), and the old binary is unchanged.
  - Runner with a missing binary → throws `YtDlpMissing`.
  - Runner with `systemBinary: 'yt-dlp'` uses that executable name. Inject the process starter.
- [ ] **Step 2: Run** `flutter test test/youtube/ytdlp_installer_test.dart test/youtube/desktop_ytdlp_runner_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same tests.** Expected: PASS. Then a real manual check on Windows: install into a temp `binDir` and run `fetchPlaylist` on the Task 2 playlist through `YtDlpClient`. Expected: Ok with ≥ 1 entry. Record it in the report.
- [ ] **Step 5: Commit** `feat: add desktop yt-dlp runner and verified installer`.

---

### Task 5: Android runner (youtubedl-android) + share intent channel

**Files:**
- Create: `android/app/src/main/kotlin/com/songies/songies/YtDlpPlugin.kt`, `lib/youtube/android_ytdlp_runner.dart`, `lib/youtube/share_intents.dart`
- Modify: `android/app/build.gradle.kts` (dependency from Task 2 notes; `packaging { jniLibs { useLegacyPackaging = true } }` if the library requires it), `MainActivity.kt`, `AndroidManifest.xml` (`ACTION_SEND` `text/plain` intent filter on MainActivity; `INTERNET` permission)
- Test: `test/youtube/android_ytdlp_runner_test.dart`, `test/youtube/share_intents_test.dart` (channel mocks)

**Interfaces:**
- Produces:
  - MethodChannel `songies/ytdlp` with these methods:
    - `run(args: List<String>)` → `{exitCode:int, out:String, err:String}`. Runs on a background thread (Kotlin coroutine/Executor), never the main thread.
    - `version()` → `String?`
    - `update()` → `String`, a status
  - `init` happens lazily on first call.
  - `AndroidYtDlpRunner implements YtDlpRunner`.
  - MethodChannel `songies/share`: `initialText()` → `String?`, plus `EventChannel` `songies/share/events` for texts received while running (`onNewIntent`, `launchMode singleTop`).
  - `Stream<String> sharedPlaylistLinks(ShareSource source)`: emits canonical links only, using `extractLinkFromSharedText`. `ShareSource` wraps the channels so tests inject fakes. On non-Android platforms it's an empty stream.

- [ ] **Step 1: Write failing tests:**
  - The runner maps the channel result to `YtDlpRun`, and a `PlatformException` to exit code -1 with stderr.
  - Shared text with a playlist link emits the canonical link. Text without one emits nothing.
- [ ] **Step 2: Run** the two test files. Expected: FAIL.
- [ ] **Step 3: Implement** the Kotlin plugin and the Dart wrappers. Register the plugin in `MainActivity.configureFlutterEngine`.
- [ ] **Step 4: Run** the tests. Expected: PASS. Then `flutter build apk --debug`. Expected: success. Record the APK size change. Device checks go to the checklist (Task 10).
- [ ] **Step 5: Commit** `feat: add Android yt-dlp bridge and share intent`.

---

### Task 6: Schema v3 (`yt_seen`) + YtImportService (import + sync)

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart` (v3 migration), `lib/library/library_repository.dart` (`keepEntry`, `findPlaylistByYtUrl`)
- Create: `lib/youtube/yt_import_service.dart`, `lib/youtube/thumbnail_fetcher.dart`
- Modify: `lib/library/art_cache.dart`, adding `put(bytes, {bool squareCrop = false})` with a center-crop before the downscale
- Test: `test/data/migration_test.dart` (add v2→v3), `test/youtube/yt_import_service_test.dart`, `test/library/art_cache_test.dart`

**Interfaces:**
- Consumes: `YtDlpClient.fetchPlaylist`, `SyncStamp.next`, `guardDb`, `keyBetween`/`nKeysBetween`, `normalizeForSearch`, `ArtCache.put`.
- Produces:
  - `class YtSeen extends Table with SyncColumns { playlistId, videoId; uniqueKeys {playlistId, videoId} }`
  - `class ImportResult { String playlistId; bool alreadyExisted; int added; }`
  - `class SyncResult { int added; int flaggedRemoved; int restored; List<String> addedTrackIds; }`
  - `class YtImportService { YtImportService(AppDatabase db, SyncStamp stamp, YtDlpClient client, ThumbnailFetcher thumbs);`
    - `Future<Result<ImportResult>> importPlaylist(String input);`
    - `Future<Result<SyncResult>> syncPlaylist(String playlistId); }`
  - `LibraryRepository.keepEntry(String entryId) → Future<Result<void>>` sets `status='active'` and `kept=true`, stamped.
  - `LibraryRepository.findPlaylistByYtUrl(String canonicalUrl) → Future<Playlist?>` returns live rows only.
  - `class ThumbnailFetcher { ThumbnailFetcher(ArtCache art, Future<List<int>> Function(Uri) download); Future<String?> fetch(String? url); }`. It never throws and returns null on failure.
- Rules (spec §6.1, §6.2 and Global Constraints):
  - **Import:**
    - Invalid link → `Err(invalidInput, 'Not a YouTube playlist link')`, nothing written.
    - Fetch failure → that Err, nothing written.
    - Link already imported (live) → `Ok(alreadyExisted: true)`, nothing written.
    - Otherwise, in one transaction: create the playlist (`source='yt'`, `ytPlaylistUrl`, `lastYtSyncAt=now`), upsert tracks by `ytVideoId` (resurrecting tombstoned rows), add entries in YouTube order using `nKeysBetween`, and add every id to `yt_seen`.
    - Thumbnails are fetched **after** the transaction and their `artworkRef` set in a second stamped batch (failures ignored), so a slow network never holds the write.
  - **Sync:**
    - New / Gone / Back exactly as spec §6.2, with `kept` respected and `lastYtSyncAt` updated, all in one transaction.
    - Duplicate video ids within one playlist response are added once.
    - Thumbnails for new tracks are fetched afterwards, as in import.
  - `unavailable` entries are imported (`tracks.unavailable = true`) like the rest.
  - A video id that appears more than once in one YouTube playlist is imported and synced once, in the position of its first appearance (`yt_seen` is unique per playlist and video).
  - Queueing downloads for new songs (spec §6.2) is Plan 3's job. `SyncResult` carries the new track ids (`List<String> addedTrackIds`) so Plan 3 can hook in.
  - `searchText` = `normalizeForSearch('$title $artist')`.

- [ ] **Step 1: Write failing tests** with `FakeYtDlpRunner` + `YtDlpClient` and in-memory db:
  - Import:
    - Creates 1 playlist, N tracks, N entries in fixture order, and N `yt_seen` rows. Every row is stamped.
    - Invalid link → Err(invalidInput) and the table counts are unchanged.
    - Fetch error (runner returns the notFound pattern) → Err(notFound) and nothing written.
    - Re-import of the same link → `alreadyExisted: true` and counts unchanged.
    - The same video in two imported playlists → one track row.
    - A tombstoned track with that video id → resurrected (same id, `deleted=false`, newer localSeq).
    - A 1,500-entry generated playlist imports in one call, with exactly 1,500 entries and an order matching the input.
  - Sync, starting from an import of [a,b,c], then user deletes b and moves c first:
    - YouTube now returns [a,b,c,d] → only d is appended, after a. Order is c,a,d. b stays deleted.
    - YouTube returns [a,d] → c is flagged `removed_on_yt` and a stays active.
    - Keep c, then sync [a,d] again → c is not flagged.
    - YouTube returns [a,c,d] after c was flagged → c is restored to active.
    - `lastYtSyncAt` is updated.
  - Migration: a real v2 file opened with v3 code has `yt_seen` and data survives.
  - ArtCache `squareCrop`: a 1280×720 input gives a 512×512 output.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** (drift `uniqueKeys` for `yt_seen`; `if (from < 3) createTable(ytSeen)`).
- [ ] **Step 4: Run** the full `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: import and sync YouTube playlists`.

---

### Task 7: Settings repository, connectivity, StreamResolver, CompositeTrackResolver

**Files:**
- Create: `lib/data/settings_repository.dart`, `lib/core/connectivity.dart`, `lib/player/stream_resolver.dart`, `lib/player/composite_track_resolver.dart`
- Modify: `lib/player/audio_backend.dart` (`UrlSource(Uri url, {Map<String,String> headers = const {}})`), `lib/player/just_audio_backend.dart` (pass headers to `AudioSource.uri(url, headers: …)`), `test/helpers/fake_audio_backend.dart`, `pubspec.yaml` (`connectivity_plus`)
- Test: `test/player/stream_resolver_test.dart`, `test/player/composite_track_resolver_test.dart`, `test/data/settings_repository_test.dart`

**Interfaces:**
- Produces:
  - `class SettingsRepository { SettingsRepository(AppDatabase db); Future<bool> getBool(String key, {required bool fallback}); Future<void> setBool(String key, bool v); Stream<bool> watchBool(String key, {required bool fallback}); Future<String?> getString(String key); Future<void> setString(String key, String? v); }`
  - Keys: `wifi_only` (default `Platform.isAndroid`), `ytdlp_use_system` (default false, Linux only).
  - `abstract class NetworkStatus { Future<NetworkKind> current(); }`; `enum NetworkKind { wifi, mobile, other, offline }`. `ConnectivityPlusStatus` maps ethernet to `other` (unmetered) and mobile to `mobile`.
  - `class StreamResolver { StreamResolver(YtDlpClient client, NetworkStatus net, SettingsRepository settings, {DateTime Function()? now}); Future<Result<UrlSource>> resolve(String videoId); Future<void> prefetch(String videoId); }`
    - In-memory cache keyed by videoId. Reused while `now < expiresAt - 10 min`. When `expiresAt` is null, reused for 1 h.
    - Offline → `Err(network, 'You're offline')`.
    - Wi-Fi only and mobile → `Err(network, 'Wi-Fi only is on — connect to Wi-Fi to stream')`.
    - YouTube unavailable/private → `Err(notFound, …)`.
    - Concurrent `resolve` calls for one id share a single in-flight future.
  - `class CompositeTrackResolver implements TrackResolver { CompositeTrackResolver(LocalTrackResolver local, StreamResolver streams, {Future<void> Function(Track t, YtStream s)? onStreamMetadata}); Future<void> prefetch(Track t); }`
    - Order: a `LocalFiles` row that exists → file. Otherwise, a `source == 'yt'` track → stream. Otherwise, local's Err.
    - A track with `unavailable == true` → `Err(notFound)` without calling yt-dlp.
  - `onStreamMetadata` lets main.dart update rough metadata (spec §6.1 step 5) through a stamped `LibraryRepository.updateTrackMetadata(trackId, {title, artist, album, durationMs})`. Add that method, which writes only changed fields and does nothing when nothing changed.

- [ ] **Step 1: Write failing tests:**
  - **Cache:** resolve twice within the window → the runner is called once. With `expiresAt = t0+60min`, a resolve at `t0+49min` reuses the cache and one at `t0+51min` re-resolves.
  - **Concurrency:** two concurrent resolves → one runner call.
  - **Network:** offline → Err with "You're offline". Wi-Fi only + mobile → Err with the exact Wi-Fi message. Wi-Fi only + wifi → Ok.
  - **Composite resolver:**
    - a local file wins over the stream
    - yt without a file → `UrlSource` with headers
    - `unavailable` → notFound with no runner call
  - **Settings:** default `wifi_only` = the fallback; set then get round-trips; watch emits changes.
  - **Metadata:** `updateTrackMetadata` stamps only when a field changed.
- [ ] **Step 2: Run** the three test files. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: resolve YouTube tracks to cached streams with Wi-Fi only`.

---

### Task 8: PlayerService — network failures and next-track prefetch

**Files:**
- Modify: `lib/player/player_service.dart`, `lib/player/track_resolver.dart` (add `Future<void> prefetch(Track t) async {}` as a default on the interface), `lib/ui/shell/player_error_snacks.dart`
- Test: `test/player/player_service_test.dart`

**Interfaces:**
- Consumes: `TrackResolver.prefetch`, `Failure.kind`.
- Rules:
  - A resolve failure with `FailureKind.network` **stops** playback (no skipping through the queue), with `playing=false` and `error = failure.message`. The snack bar shows the message as is.
  - `notFound` keeps the existing skip behaviour. YouTube `notFound` also marks the track `unavailable` via a new optional `onUnavailable(trackId)` callback, wired to a stamped `LibraryRepository.markUnavailable`. Add that method.
  - Prefetch: when `duration - position <= 20 s` on a playing track, call `resolver.prefetch(nextTrack)` once per current entry. The next track is decided by the queue, shuffle and repeat rules. There's none at the end with repeat off.
- [ ] **Step 1: Write failing tests** (FakeAudioBackend plus a fake resolver):
  - Network Err on play → backend not started, `playing false`, error equals the message, and the resolver was called once (no skip loop).
  - YouTube `notFound` → skipped and `onUnavailable('id')` called.
  - Position updates crossing `duration - 20 s` call `prefetch(next)` exactly once. With repeat off on the last track there's no prefetch.
- [ ] **Step 2: Run** `flutter test test/player/player_service_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: stop on network errors and prefetch the next stream`.

---

### Task 9: UI — import, YouTube playlist actions, YouTube settings, wiring

**Files:**
- Create: `lib/ui/library/import_dialog.dart`, `lib/ui/playlist/yt_playlist_actions.dart`, `lib/ui/settings/youtube_settings.dart`
- Modify: `lib/ui/library/library_page.dart` ("+" menu item **Import from YouTube**; `YouTube` filter chip), `lib/ui/playlist/playlist_page.dart` (YouTube hero subtitle `YouTube playlist · last synced <relative>`; **Sync with YouTube** button; removed rows), `lib/ui/settings/settings_page.dart`, `lib/providers.dart`, `lib/main.dart` (construct runner, client, services, resolvers, share stream → import dialog)
- Test: `test/ui/import_dialog_test.dart`, `test/ui/yt_playlist_test.dart`, `test/ui/youtube_settings_test.dart`

**Interfaces:**
- Consumes: `YtImportService`, `YtDlpRunner.version/update`, `YtDlpInstaller`, `SettingsRepository`, `sharedPlaylistLinks`.
- Produces / UI copy (exact):
  - **Import dialog:** title "Import from YouTube". Field hint "Paste a YouTube Music playlist link". Buttons "Cancel" / "Import". While working: "Importing…" with a spinner.
  - **Import results:**
    - Success → navigate to `/library/playlist/<id>` and show snack "Imported N songs".
    - `alreadyExisted` → navigate there and show snack "Already in your library — use Sync to update it".
    - Error → the message inline under the field. `missingBinary` → "yt-dlp isn't installed — install it in Settings" with a button "Open Settings".
  - **Android share:** a received link opens the dialog prefilled.
  - **Playlist page (YouTube playlists only):**
    - A **Sync with YouTube** button. While running: "Syncing…". When done: snack "Up to date", "Added N new songs", or "Added N, M removed on YouTube".
    - Removed rows are greyed with the tag "removed on YT" and two actions: **Keep** (`keepEntry`) and **Delete** (`removeEntry`).
    - Unavailable tracks are greyed with the tag "unavailable".
  - **Settings → YouTube section:**
    - "yt-dlp version: X" or "not installed".
    - Button "Install yt-dlp" or "Update yt-dlp". On Android only "Update yt-dlp". Result snack "yt-dlp updated to X" or the error.
    - Toggle "Wi-Fi only streaming".
    - Linux only: toggle "Use system yt-dlp".
  - **Extractor errors:** any import, sync or stream `ytdlp:extractor:` error shows the snack "YouTube changed something — try Settings → Update yt-dlp".
- [ ] **Step 1: Write failing widget tests** (fakes for service, runner and settings):
  - Import a valid link → navigates and shows the "Imported 3 songs" snack.
  - Invalid link → the inline message and no navigation.
  - `alreadyExisted` → the right snack.
  - `missingBinary` → message plus "Open Settings".
  - YouTube playlist page shows Sync; local playlist doesn't.
  - Sync result snacks for each case.
  - Removed row: Keep calls `keepEntry`; Delete calls `removeEntry`.
  - Settings shows the version. Update shows the result snack. The Wi-Fi toggle writes `wifi_only`. The Linux toggle is hidden on non-Linux (injectable platform flag).
  - Library "YouTube" chip filters to `source == 'yt'`.
- [ ] **Step 2: Run** the three test files. Expected: FAIL.
- [ ] **Step 3: Implement + wire `main.dart`.**
  - `CompositeTrackResolver` replaces `LocalTrackResolver` in `PlayerService`.
  - Desktop uses `DesktopYtDlpRunner`; Android uses `AndroidYtDlpRunner`.
  - Linux reads `ytdlp_use_system`.
  - `onStreamMetadata` → `updateTrackMetadata`; `onUnavailable` → `markUnavailable`.
- [ ] **Step 4: Run** the full `flutter test` + `flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat: YouTube import, sync and settings UI`.

---

### Task 10: End-to-end verification + checklist

**Files:**
- Modify: `docs/manual-test-checklist.md` (new "YouTube" section), `docs/PROGRESS.md`

- [ ] **Step 1: Windows end-to-end, done by the agent:**
  - Build `flutter build windows --release`.
  - Launch, and install yt-dlp from Settings by driving the app or calling the installer through a small integration test against the real network.
  - Import the Task 2 playlist, start playing one song for a few seconds (process alive, no errors in the log), and run Sync.
  - Record the results and the idle RAM.
- [ ] **Step 2: Build** `flutter build apk --release`. Expected: success. Record the APK size.
- [ ] **Step 3: Checklist "YouTube" section:**
  - import by link
  - import by Share from the YT Music app
  - re-import message
  - streaming plays with no ads
  - next song starts without a long gap
  - Wi-Fi only blocks on mobile data with the message
  - offline message
  - Sync with YouTube after adding a song on YouTube (song appended)
  - removing a song on YouTube (flagged), then Keep and Delete
  - private/deleted videos shown as unavailable and skipped
  - Update yt-dlp on Android and desktop
  - "Use system yt-dlp" on Nobara
- [ ] **Step 4: Update `docs/PROGRESS.md`:**
  - mark Plan 2 done
  - new decisions
  - what's next (Plan 3: downloads)
- [ ] **Step 5: Commit** `docs: Plan 2 verification and checklist`.

---

## Amendments from the Task 2 probe (binding for Tasks 3–9)

Facts recorded in `docs/yt-dlp-notes.md` change these tasks:

- **Task 3 — results and errors:**
  - **Exit code first.** On failure yt-dlp exits 1 with `null` on stdout. Never JSON-decode stdout when the exit code isn't 0. Classify by the stderr `ERROR:` line.
  - **Warnings are not failures.** Successful runs (exit 0) always print `WARNING:` lines on stderr: the "no JavaScript runtime" warning, and a "YouTube Music is not directly supported. Redirecting" warning for `music.youtube.com` links. Ignore stderr when the exit code is 0.
  - **notAPlaylist:** a watch link given to `--flat-playlist -J` exits 0 with single-video JSON that has no `entries`. `fetchPlaylist` classifies exit 0 with missing `entries` as `notAPlaylist`.
- **Task 3 — stderr mapping:**

  | stderr contains | Kind |
  |---|---|
  | `The playlist does not exist`, `This video is unavailable`, `Private video`, `removed for violating` | `notFound` |
  | `HTTP Error 400` (malformed id) | `notFound` |
  | `Unable to connect`, or `Unable to download` without `HTTP Error 4xx` | `network` |
  | non-YouTube `[generic]` 404 | `notFound` |
  | other `ERROR:` lines | `extractor` |

- **Task 3 — parsing:**
  - Null `title`, `duration`, `channel` and `uploader` are tolerated.
  - Unavailable = title `[Private video]` or `[Deleted video]`, or null duration and null channel. Don't use `availability`.
  - Key entries by `id`. Don't assert `entries.length == playlist_count`.
  - The " - Topic" artist cleanup is tested with an inline synthetic entry (the fixtures have none).
  - Stream: read the top-level `url` and `http_headers` from `-J` (the selected format is merged at top level). `album` may be null. `title`, `artist` (channel or uploader) and `duration` also come from top level.
- **Task 4:**
  - Decode `Process.run` output explicitly as UTF-8 (`stdoutEncoding: utf8, stderrEncoding: utf8`), because titles contain accented characters.
  - No short timeout: large playlists take minutes. Allow 10 min for a playlist fetch and 60 s for a stream resolve.
  - Don't add a JS runtime now. The "may be missing formats" warning is tracked as a follow-up.
- **Task 5:**
  - Dependency: `io.github.junkfood02.youtubedl-android:library:0.18.1` from `mavenCentral()`.
  - Packaging: `useLegacyPackaging = true` / `extractNativeLibs`.
  - ABI filters: `arm64-v8a`, `armeabi-v7a`, `x86_64`.
  - Check its minSdk against ours (24) while building. `execute` failures arrive as exceptions carrying stderr, which feed the same classifier.
- **Task 7:**
  - Stream URLs last about 6 h but are tied to the device's IP address. Clear the stream cache when the network changes (`NetworkStatus` change stream).
  - If a cached URL fails to load (the engine errors right after `setSource`), resolve again once before skipping.
