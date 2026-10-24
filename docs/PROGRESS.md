# Songies — Progress

_Last updated: 2026-10-24_

## Plan 3 (bug fixes + downloads) — done and reviewed task by task; final whole-branch review still to come

- **Branch:** `plan-3-downloads-fixes` (from `plan-2-youtube`). Plan: [Plan 3](superpowers/plans/2026-10-23-songies-plan-3-fixes-and-downloads.md). Nothing is pushed or merged.
- **Status:** Tasks 1–10 are implemented; Tasks 1–9 were reviewed by separate reviewers. **The final whole-branch review and its fix batch are still to come.** Tests: 762 passing, `flutter analyze` clean, `flutter build apk --release` and `flutter build linux --release` succeed (APK 79.0 MB). Windows is built on your PC.
- **What it does now:**
  - Home/Library/Search tabs always open their root.
  - Playback no longer shows one song while playing another; failed songs show "Skipped …" and 3 in a row stop playback.
  - Covers are sharp (maxres first, letterbox cut, stored at 720 px).
  - Android has its own folder picker that says why it can't be used.
  - Per-device Download switch beside "Sync with YouTube" in the playlist hero, with progress rings, per-song icons, an app-wide indicator and Downloads panel, a "Downloads failing — update yt-dlp?" banner and Settings → Downloads. Remove downloads? offers Keep files / Remove.
  - Files go to `<appData>/library/yt/<videoId>.<ext>`; 2 at a time on Android, 3 on desktop; Wi-Fi only pauses on mobile data; 429 backs off 30 s → 10 min; offline pauses and resumes; full storage pauses.
  - Android: a foreground-service notification ("Downloading songs · x of y", "Paused — waiting for Wi-Fi", "Downloads paused", "Downloaded n songs").
- **Verification on Linux:** the in-app GUI could not be driven from the agent. Instead yt-dlp 2026.08.19 was run with the app's exact download args (format `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`, `--no-playlist --continue --no-mtime`, output `%(id)s.%(ext)s`) in a scratch directory for the first 3 songs of the test playlist (`PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI`): 3 `.webm` files (3.9 MB, 10.4 MB, 3.7 MB) downloaded. **Still a manual check for you:** the in-app Linux flow (files in `~/.local/share/songies/library/yt/`, `FileSource` log line on play, Remove deletes them); it is in [manual-test-checklist.md](manual-test-checklist.md).
- **Rulings:** see [plan-3-session-log.md](plan-3-session-log.md) for the full list. Task 9 added: the Download toggle sits beside "Sync with YouTube" (the Play/Shuffle row overflowed 400 px phones); a user pause only blocks new slots (running downloads finish) and shows as "Paused" / "Downloads paused" via `DownloadPauseReason.user`; Settings → Downloads resumes any resumable pause; the singular "Remove downloads?" copy; the downloads banner is keyboard-reachable.
- **Parked items (deferred minors):** the per-task lists in the session log, plus Task 9: banner/indicator heights are hardcoded in the phone overlay padding (covered by the 400 px shell test, phone check is yours); the status line rebuilds on each progress tick (needed for the combined fraction); `track_download_icon` catches `on Exception` where others catch `DownloadDbException`; "Retry failed" is always shown in the Downloads panel; no build-count test for the rebuild-scoping rule. Task 8 minors also remain (service restarts each update, stale "retrying in" text, "Downloaded 0 songs" after cancel-all, duplicated notifier choice, extra core-ktx dependency, stop/refused-flag edge cases).
- **Next:** the final whole-branch review and fixes, then your device checks, then [Plan 4](superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md) (a living UI and the theme engine). Roadmap renumbered: Plan 5 = lyrics, Plan 6 = device sync, Plan 7 = packaging.
- **To resume in a new Claude session:**
  > Songies Plan 3 is implemented on branch `plan-3-downloads-fixes` (Tasks 1–10 done). Next: the final whole-branch review and its fixes, then start Plan 4. Read docs/plan-3-session-log.md. Don't push or merge.

## Plan 2 (YouTube) — done and reviewed, pending your device checks

- **Branch:** `plan-2-youtube`, made from `plan-1-foundation`. Plan: [Plan 2](superpowers/plans/2026-10-22-songies-plan-2-youtube-import-sync-stream.md).
- **Status:** Tasks 1-10 are implemented and reviewed task by task, and the final whole-branch review's findings are fixed (see "Plan 2 final review fixes" below). The YouTube section of the [manual checklist](manual-test-checklist.md) is for you.
- **Tests:** 583 passing; `flutter analyze` is clean.

### What works now
- **Import:** paste a YouTube or YouTube Music playlist link, or Share one from the YT Music app (Android). Importing the same playlist twice says it already exists.
- **Sync with YouTube:** new songs are appended; songs removed on YouTube are flagged, and you choose Keep or Delete. Private or deleted videos show as unavailable and are skipped.
- **Streaming:** YouTube songs stream through yt-dlp, with no downloads yet. Stream links are cached in memory and renewed before they expire. The next song is prepared in the last 20 seconds so the gap is short.
- **Network rules:** Wi-Fi only blocks streaming on mobile data with a message; offline playback stops with a message; a network change clears cached stream links.
- **yt-dlp:** on desktop, Settings installs and updates it (checked against the release's SHA-256), or uses the system yt-dlp ("Use system yt-dlp"). On Android it comes bundled (youtubedl-android) and Settings updates it.

### Verification done on this host (Nobara, no Windows)
- **Real-network run** (throwaway program outside the repo, real classes end to end, Linux yt-dlp). Playlist `PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI`:
  - yt-dlp install: 3.3 s (version 2026.10.21).
  - Import: 182 tracks and 182 entries in 2.3 s. All 182 got artwork (3.8 s more, in the background). None unavailable.
  - Sync right after: 0 added, 0 flagged, 0 restored (2.0 s).
  - Stream resolve of one track: 3.2 s. A ranged GET (`Range: bytes=0-1023`) with the returned headers gave HTTP 206, `audio/webm`, `bytes 0-1023/3947045`.
- **`flutter build linux --release`:** succeeds (bundle 33 MB), without `mpv-libs-devel`. The release bundle was launched for 12 s with no errors (media_kit_libs_linux registered); audio was not listened to.
- **`flutter build apk --release`:** succeeds, 78.8 MB after the final fixes (78.5 MB before) (arm64-v8a, armeabi-v7a and x86_64). It prints `llvm-strip` "not a valid object file" errors for `libpython.zip.so`. They don't fail the build; the file just ships unstripped. No gradle change was made.
- **Not done here (left for the Windows PC):** `flutter build windows --release`, idle RAM (target 150 MB or less), and "Install yt-dlp" from Settings on Windows. No audio, phone or Windows checks were possible.

### Next steps
1. Tick the YouTube section of the manual checklist on Android, Windows and Nobara.
2. Merge `plan-1-foundation` and `plan-2-youtube` once happy.
3. **Plan 3: downloads** (save YouTube songs for offline play).

- **To resume in a new Claude session:**
  > Songies Plan 2 is implemented on branch `plan-2-youtube` (Tasks 1-10 done, final review fixed, 583 tests). Next: the manual YouTube checks on Android/Windows/Nobara, then write Plan 3 (downloads) from docs/superpowers/specs/2026-10-21-songies-design.md. Read docs/PROGRESS.md. Don't push or merge.

## Plan 1 status

## Where things stand

- **Branch:** `plan-1-foundation`. All Plan 1 work is here, split from `master` at `19a071c`. `master` holds only the spec and plan.
- **Plan 1** ([plan](superpowers/plans/2026-10-21-songies-plan-1-foundation-local-playback.md), [spec](superpowers/specs/2026-10-21-songies-design.md)): **all 15 tasks are implemented and reviewed task by task, and the final whole-branch review is done.** Its findings were fixed in one batch, and that batch passed a re-check.
- **Tests:** 382 passing; `flutter analyze` is clean.
- **Builds:** `flutter build windows --debug`, `flutter build windows --release` and `flutter build apk --debug` all succeed.
- **Windows release build:** about 128 MB of RAM when idle (target ≤ 150 MB).

### What works now
- **Library:**
  - Add music folders, which are scanned recursively.
  - Duplicates are detected by file content, and moved or deleted files are flagged "File missing".
  - Embedded album art is read from the files.
- **Playlists:**
  - Create, rename, delete.
  - Add songs, drag to reorder, swipe to remove with Undo.
  - Locate a missing file.
- **Playback:**
  - Queue, shuffle, repeat (off / all / one), previous and next.
  - Volume (desktop).
  - Missing files are skipped instead of stopping playback.
- **System media controls:**
  - **Android:** notification, lock screen and headset buttons; pauses when headphones are unplugged.
  - **Windows:** media flyout (SMTC) and keyboard media keys.
  - **Linux:** MPRIS (the KDE/GNOME media widget).
- **UI:**
  - Phone layout: bottom nav with icons above labels and a filled Home icon, plus a mini-player 8 px above the nav.
  - Desktop layout: title bar with search (Ctrl+K), sidebar, player bar, and keyboard shortcuts.
  - Screens: Home, Search, Library, Playlist, Now Playing (blurred cover background and a queue tab), Settings.
- **Default theme:** the theme engine model and the Default theme. The theme editor comes in Plan 4.

## Next steps (in order)

1. **Manual testing on real devices** using [manual-test-checklist.md](manual-test-checklist.md). This covers Android phone, Windows and Nobara. Agents couldn't do it because they had no audio, no phone and no Linux machine.
2. **Merge** `plan-1-foundation` into `master`.
3. **Write Plan 2** (YouTube import, Sync with YouTube, streaming), then Plans 3–6 (downloads, themes and lyrics, device sync, packaging). The roadmap is at the top of the Plan 1 file.

### Plan 1 resume note (superseded by Plan 2 above)
> Songies Plan 1 is complete and reviewed on branch `plan-1-foundation`. Next: merge it if not done yet, then write Plan 2 (YouTube import, sync and streaming) from docs/superpowers/specs/2026-10-21-songies-design.md. Start with a polish task covering the deferred minor items in docs/PROGRESS.md.

## Environment notes (this PC)

- **Flutter 3.47.7:** at `C:\Users\dmart\Downloads\flutter_windows_3.47.7-stable\flutter\bin`. It's on the user PATH but not on Git Bash's PATH.
- **Rust:** required for the `smtc_windows` plugin.
- **Windows Developer Mode:** must be on.
- **Android:** SDK 36 / platform 37, NDK 28.2.13676358 and CMake 3.22.1 installed. The project uses `compileSdk = 37` and `minSdk 24`.
- **Nobara needs:** `sudo dnf install clang cmake ninja-build gtk3-devel mpv-libs libsecret-devel` before building there.

## Environment notes (Nobara host used for Plan 2)

- **Flutter 3.47.7** at `~/flutter` (add `~/flutter/bin` to PATH).
- **Android SDK** at `~/Android/Sdk` (platform `android-37.0`, NDK 28.2.13676358).
- **JDK 21** (Temurin) at `~/jdk-21`; `flutter config --jdk-dir ~/jdk-21` is set.
- **mpv:** the runtime `mpv-libs` package (0.41) is what's needed, and it is present on this host. `mpv-libs-devel` is not needed; the Linux build and launch work without it.

## Decisions made during implementation (rulings)

Each entry says what was decided and what it costs if it turns out wrong.

- **R1: `.gitignore`.** It keeps `.superpowers/` and `test/native/` alongside Flutter's standard entries. Cost if wrong: scratch files get committed.
- **R2: `fake_async` dev dependency.** It's needed by the media-controls idle-timer tests. Cost if wrong: none.
- **R3: fractional-index port.** The rocicorp fractional-index library was ported faithfully, and its own test values win over values recalled in the plan. The library's licence is CC0, not MIT as the plan said. Cost if wrong: one test value.
- **R4: build checks instead of hands-on testing.** Agents verified builds and app launch rather than listening to audio or using devices, so all hands-on checks went into `docs/manual-test-checklist.md`. Cost if wrong: platform bugs surface later, during your manual testing.
- **R5: placeholder shell.** Task 11 used a temporary shell that Task 12 replaced. Cost if wrong: none.
- **R6: Locate a missing file.** Locate imports the chosen file. If its content differs from the missing one, the new `LibraryRepository.replaceEntryTrack` points the playlist entry at the new track. Cost if wrong: a small API addition.
- **R7: injectable clock.** `nowProvider` provides an injectable clock for the time-of-day greeting. Cost if wrong: none.
- **R8: SQLite packaging.** The end-of-life `sqlite3_flutter_libs` was replaced by `sqlite3` 3.x, which bundles SQLite itself. It's verified bundled in both the APK and the Windows build. Cost if wrong: one dependency swap.
- **R9: commit trailers.** Some commits name "Claude Sonnet 5.5" because subagents used their own model name. They were not amended. Cost if wrong: cosmetic only.
- **R10: shared error handling.** A shared `guardDb` maps database errors from the background isolate to `Err(io)`. Cost if wrong: a tiny refactor.
- **Duplicate MP3s in a second folder** are re-hashed on every rescan, because there is one file row per track. Accepted as-is. Cost if wrong: slower rescans of folders full of duplicates.
- **R11: audio interruptions.** The audio engine never pauses itself. Headphone unplugs and interruptions are routed through `PlayerService`, so the "playing" state stays truthful. Cost if wrong: one small extra file.
- **R12: Windows build fix.** A compile define, `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`, makes `permission_handler_windows` compile with MSVC 14.51. Cost if wrong: harmless dead config once the plugin is fixed.
- **R13: progress updates.** The playback position is updated every 200 ms, for battery and CPU. Cost if wrong: the scrubber updates 5 times a second instead of up to 60.
- **Ducking.** With R11, Songies doesn't lower its own volume for short interruptions such as navigation prompts. Accepted, because Android 8+ ducks automatically. Cost if wrong: no ducking on Android 7.
- **R14: Settings and Now Playing routes.** Settings lives inside the shell, so desktop keeps the sidebar and player bar. Now Playing on desktop opens as an overlay with a close button. Cost if wrong: a small router change.
- **R15: Locate on Android picks a folder.** It then rescans that folder, because Android's single-file picker copies the file into the app's cache, which breaks "files are referenced in place". Cost if wrong: Locate on Android is slightly less direct.

## Plan 2 rulings (R17 onward)

- **R17:** `YtDlpMissing` lives in `ytdlp_runner.dart`; the client maps it to `missingBinary` and any other throw to `unknown`. Cost if wrong: a moved class.
- **R18:** `YtDlpRunner.run(args, {timeout})`; playlist fetch gets 10 min, stream resolve 60 s, and a timeout counts as a network error. Cost if wrong: one parameter.
- **R19:** Errors carry a `ytdlp:<kind>:` prefix; `ytErrorUserMessage` turns a kind into fixed user copy (for example "Not found on YouTube — it may be private or deleted"). Cost if wrong: copy edits.
- **R20:** `TrackResolver` has concrete `prefetch` and `invalidate` methods, and implementers `extends` it. Cost if wrong: none.
- **R21:** When the engine rejects a cached stream URL, `PlayerService` drops it and resolves again once per entry before skipping. Cost if wrong: one extra resolve per failure.
- **R22:** `NetworkStatus` has a `changes` stream; `StreamResolver` clears its cache on any change (event-driven, no polling). Cost if wrong: none.
- **R23:** Stream URLs are renewed 10 minutes before expiry (the plan's constraint), not 5 as the probe notes suggested. Cost if wrong: renewals happen 5 minutes earlier.
- **R24:** Streams resolve with `-J` instead of the spec's `-g`, because the request headers only come from the JSON. Cost if wrong: none.
- **R25:** Windows builds and checks can't run on the Nobara host, so Task 10 became a Linux real-network run plus Linux and APK builds. The Windows release build and RAM check are left for you. Cost if wrong: Windows-only build problems show up later.
- **R26:** Cancel and progress streams for long import/sync runs (spec section 12) are not in the plan and are deferred; a spinner covers progress. Cost if wrong: a 1,000-song import can't be cancelled.
- **R27:** With a system yt-dlp, "Update" explains that the package manager does it (it never overwrites the distro's binary); `version()` runs the system binary. Cost if wrong: one message.
- **R28:** A network failure leaving `StreamResolver` has a ready-to-show message ("Couldn't reach YouTube — check your connection"); other kinds keep the prefix and the UI maps them. Cost if wrong: copy edit.
- **R29:** `SyncStamp.nextMany(n)` hands out many stamps in one write, so a 1,500-song import doesn't make thousands of separate calls. Cost if wrong: a small extra API.
- **R30:** Thumbnails download in the background after an import or sync returns (6 at a time, `thumbnailsSettled` for tests). Cost if wrong: artwork appears a bit after the playlist opens.
- **R31:** Songies doesn't de-duplicate connectivity changes itself. Note that `connectivity_plus` already applies `distinct` to its own stream, so a Wi-Fi to Wi-Fi switch or VPN toggle that keeps the same connection type sends no event; a stream link bound to the old IP then fails on load, and the one-time fresh-URL retry (R38, I1) recovers it. Cost if wrong: a few extra resolves.
- **R32:** Prefetch uses the same next-song rules as playback and skips unavailable songs. Cost if wrong: a small refactor.
- **R33:** Next or previous while offline stops the still-playing song (the network-failure rule), rather than silently ignoring the tap. Cost if wrong: one behaviour tweak.
- **R34:** One song reads "Imported 1 song" / "Added 1 new song"; other counts keep the plural. Cost if wrong: two strings.
- **R35:** Import errors from yt-dlp itself show inline in the import dialog; sync and stream errors show as snack bars. Cost if wrong: one widget change.
- **R36 (P13):** A YouTube stream failure of kind extractor, missingBinary or unknown stops playback like a network failure (the failing song stays current, the snack shows the mapped copy such as "yt-dlp isn't installed — install it in Settings"). Region-blocked and age-restricted errors count as notFound, so those songs are still skipped. Reason: these errors hit every track alike, and skipping would run yt-dlp hundreds of times. Cost if wrong: one queue stop where a skip might have worked.
- **R37 (P14):** Sync rewrites a live track's `unavailable` flag from the fetched playlist when it differs (stamped only on change), in both directions. `HTTP Error 400` counts as notFound only for `[youtube:tab]` (playlist) errors; elsewhere it's extractor. Cost if wrong: a song that playback marked unavailable but YouTube still lists flips back to available on each sync, until playback marks it again.
- **R38 (P15):** The final fix wave also took cheap, user-visible minors: R8 keep rules for youtubedl-android in release; the import dialog can't stick busy; no artwork fetch for unavailable entries; radio/mix `list=RD…` links are rejected (curated `RDCLAK…` playlists still import); the un-awaited `throwsA` test is awaited; the player shows the tapped YouTube song (buffering) before its stream resolves. Cost if wrong: a slightly larger fix wave.

## Plan 2 final review fixes

1. **C1 Android streaming:** stream headers are now sent natively (ExoPlayer request properties, media_kit `httpHeaders`) instead of through just_audio's local `http://127.0.0.1` proxy, which Android blocks without cleartext permission (`useProxyForRequestHeaders: false`).
2. **C2 broken yt-dlp:** extractor, missingBinary and unknown stream failures stop playback with the right message instead of trying every song in the queue (R36).
3. **I1 dead stream URL on load:** when `setSource`/`play` throws for a YouTube song (typically HTTP 403 for an expired or IP-bound link), the cached link is dropped and the song is resolved once more, through the same helper as the engine-error retry.
4. **I2 user additions:** Sync no longer flags YouTube songs you added from another playlist as "removed on YouTube"; only ids that came from this playlist (`yt_seen`) are checked.
5. **I3 unavailable both ways:** Sync clears or sets `unavailable` from YouTube's current list; HTTP 400 is notFound only for playlist errors (R37).
6. **I4 timeouts:** downloads have connect, idle (30 s) and overall (10 min) timeouts; each thumbnail gives up after 15 s, and one failing thumbnail no longer drops the rest; the installer's `--version` check is capped at 30 s.
7. **Extras (R38):** R8 keep rules (`android/app/proguard-rules.pro`), import dialog try/finally, no artwork for unavailable entries, radio/mix links rejected, awaited test expectation, immediate feedback when tapping a YouTube song.

## Final review fixes (after Task 15)

1. **Android Back:** opening a playlist from Home or Search now pushes it inside that tab (`/home/playlist/:id`, `/search/playlist/:id`, `/library/playlist/:id`), so Back returns to where you came from instead of closing the app. The old `/playlist/:id` link redirects to the Library one.
2. **Retagged MP3s:** editing a song's tags and rescanning now updates the same track in place, so playlist entries survive.
3. **Playback errors** now show a snack bar, for example "Couldn't play — the song files are missing".
4. **Files that come back:** a file that returns plays and clears its "File missing" flag. Tapping a greyed-out song now tries to play it.
5. **Engine errors:** an engine error mid-song skips to the next track. Consecutive failures are capped so repeat-all can't loop forever.
6. **Locate on Android** rescans the picked folder without adding it to Settings → Music folders.
7. **App name** shows as "Songies" on Android, Windows and Linux. Template leftovers (README, pubspec description, `cupertino_icons`, the gradle TODO) are cleaned up.
8. **Checklist:** three new manual checks for the items above.

- **R16:** the final fix batch covered the 3 important findings plus 5 minor ones (items 4–8). The rest of the minor items are deferred to a polish task at the start of Plan 2. Cost if wrong: that polish waits.

## Known follow-ups and deferred minor items

**Must address before later plans:**
- **Plan 4:** `ThemeSpec.fromJson` needs range checks (glowStrength, fontScale, cornerRadius) before theme import ships.
- **Plan 5:** `Hlc.parse` should reject non-canonical clocks. Re-adding a deleted track must resurrect its row, because of the unique `fileHash`/`ytVideoId` columns. Add a `local_seq` index.
- **Remove** `dependency_overrides: flutter_rust_bridge: 2.11.1` once `smtc_windows` is rebuilt against flutter_rust_bridge ≥ 2.13.

**Plan 2 deferred minor items (none block use):**
- **Link parsing:**
  - A shared link with trailing punctuation (`list=PLx.` or in parentheses) isn't recognised.
  - Watch links with `&list=PL…` are accepted as playlists, untested.
- **yt-dlp client and runners:**
  - The `ERROR:` line filtering and the no-entries check are duplicated.
  - Untested branches: getaddrinfo/unreachable network errors, `chmod`/write failures, SIGKILL escalation.
  - `httpDownload` buffers about 35 MB in memory. A timed-out `--version` run isn't killed (only abandoned).
  - A non-UTF-8 byte in yt-dlp output can throw an unmapped exception.
  - Any `ProcessException` maps to "missing", including permission-denied.
  - The inner `exitCode.timeout` future is unawaited; `desktop_ytdlp_runner.dart` has a missing `const` and an `ignore_for_file: prefer_initializing_formals`.
  - The timeout test depends on `pgrep`.
  - Android: post-dispose `main.post` result calls, and init runs per plugin instance.
  - Android: a non-zero exit drops partial stdout and the real exit code; `version()` catches only `PlatformException`.
- **Share on Android:** the initial share intent is re-read after the activity is recreated; share snack bars may sit under the mini-player; the share path in `main.dart` is untested; a second shared link stacks a second dialog.
- **Import and sync:**
  - Playlist lookups run outside `guardDb`.
  - Already-live tracks still consume a stamp.
  - yt-dlp's `track`/`artists` metadata isn't used; the plan amendment chose the channel as artist.
  - A large playlist's JSON is decoded on the UI isolate.
  - Test gaps: duplicate ids in one sync response, a restored entry keeping its position, a failed fetch leaving `lastYtSyncAt`, mid-transaction rollback. One test prints a warning and stack trace.
- **Streaming and player:**
  - An expired-URL retry restarts the song from 0; `engineRetried` isn't reset on explicit play.
  - Retrying inside the last 20 s prefetches again (harmless).
  - After a network stop, the duration still shows the previous song's.
  - `_advance`/`_candidates` don't filter unavailable songs themselves.
  - `dispose()` doesn't clear tokens; `StreamResolver.dispose` is never called (app lifetime).
  - Missing tests: header equality of `UrlSource`, `onUnavailable` throwing, prefetch with shuffle, stale in-flight regressions.
  - `ytErrorUserMessageFromText` builds a dummy `Failure`.
  - Linux plugin registrants weren't regenerated for `connectivity_plus` (the Linux build works).
  - With "Use system yt-dlp" on, a missing binary still says "install it in Settings", which is misleading there.
- **Settings UI:**
  - The sync busy flag is widget-local, so leaving and returning allows a second sync.
  - Keep/Delete have no busy state.
  - Toggle writes give no failure feedback.
  - If the version lookup fails, desktop shows "Update" instead of "Install".
  - The `useSystemYtDlpProvider` doc is inaccurate.
  - The Library empty state doesn't offer "Import a YouTube playlist".
- **Housekeeping:** meaningless ignore comment in `composite_track_resolver.dart`; a "no thumbnails" comment in the 1,500-entry test is false; an earlier fix commit bundled format-only edits to three unrelated files.

**Plan 1 minor polish (none of it blocks use):**
- **Playback error wording:** a single-song queue whose audio engine fails still says "files are missing".
- **Shortcuts:** desktop shortcuts don't work while the Now Playing overlay is open.
- **Duplicate code:** the scrubber is implemented twice (player bar and Now Playing).
- **Duplicate songs:** a song that appears twice in a playlist highlights both rows while playing.
- **Accessibility:**
  - Keyboard Tab access is excluded from the sidebar and player bar (`ExcludeFocus`).
  - The player-bar play/pause button lacks button semantics.
- **Settings and scanning:**
  - Two progress indicators show when you add a folder from Settings.
  - Repeated Rescan taps queue duplicate scans.
  - Removing a folder while it's being scanned re-adds it.
  - `formatBytes` shows "1024.0 KB" instead of "1.0 MB".
- **Scanner edge cases:**
  - Windows path case-sensitivity.
  - Long or control-character titles aren't cleaned up.
  - Noisy warnings for 0-byte files.
- **Large files to split:**
  - `player_service.dart` (573 lines)
  - `playlist_page.dart` (655 lines)
  - `library_scanner.dart` (447 lines)
- **Test gaps:**
  - SMTC binding and `MediaControlsBinding.create`.
  - Log format.
  - Database rollback paths.
  - Some UI branches.
