# Songies — Progress

_Last updated: 2026-10-22_

## Plan 2 (YouTube) — in progress

- **Branch:** `plan-2-youtube`, made from `plan-1-foundation`. Plan: [Plan 2](superpowers/plans/2026-10-22-songies-plan-2-youtube-import-sync-stream.md). Read its "Amendments from the Task 2 probe" section too.
- **Done:**
  - **Task 1:** the ripple-bleed fix (every page has its own surface), `formatBytes`, Rescan de-dupe, and the engine-failure message.
  - **Task 2:** the yt-dlp probe. YouTube audio works with no extra components: yt-dlp 2026.10.21, Opus format 251. Details are in [yt-dlp-notes.md](yt-dlp-notes.md), with sample outputs in `test/fixtures/ytdlp/`.
- **Next:** Tasks 3–10, starting with Task 3 (the yt-dlp client and link parsing). That's an estimated 3.5–5 hours of agent work.
- **To resume in a new Claude session:**
  > Continue Songies Plan 2 subagent-driven on branch `plan-2-youtube`, starting at Task 3. Tasks 1–2 are done. Read docs/PROGRESS.md and the plan's amendments section. Don't push or merge; build Windows and Android when finished.

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
- **Nobara needs:** `sudo dnf install clang cmake ninja-build gtk3-devel mpv-libs-devel libsecret-devel` before building there.

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

**Minor polish (none of it blocks use):**
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
