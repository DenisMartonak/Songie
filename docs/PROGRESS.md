# Songies — Progress

_Last updated: 2026-10-22_

## Where things stand

- **Branch:** `plan-1-foundation`. All Plan 1 work is here, split from `master` at `19a071c`. `master` holds only the spec and plan.
- **Plan 1** ([plan](superpowers/plans/2026-10-21-songies-plan-1-foundation-local-playback.md), [spec](superpowers/specs/2026-10-21-songies-design.md)): **all 15 tasks are implemented and reviewed task by task.** The final whole-branch review is still to do.
- **Tests:** 362 passing; `flutter analyze` is clean.
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

1. **Final whole-branch review of Plan 1.** This is the step after Task 15 in the subagent-driven workflow. Review `git diff 19a071c..plan-1-foundation` against the spec and the plan, then fix whatever it finds.
2. **Manual testing on real devices** using [manual-test-checklist.md](manual-test-checklist.md). This covers Android phone, Windows and Nobara. Agents couldn't do it because they had no audio, no phone and no Linux machine.
3. **Merge** `plan-1-foundation` into `master`.
4. **Write Plan 2** (YouTube import, Sync with YouTube, streaming), then Plans 3–6 (downloads, themes and lyrics, device sync, packaging). The roadmap is at the top of the Plan 1 file.

### To resume in a new Claude session
> Continue Songies Plan 1: run the final whole-branch review of `plan-1-foundation` (base `19a071c`) using superpowers subagent-driven-development, then finishing-a-development-branch. Context is in docs/PROGRESS.md.

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

## Known follow-ups and deferred minor items

**Must address before later plans:**
- **Plan 4:** `ThemeSpec.fromJson` needs range checks (glowStrength, fontScale, cornerRadius) before theme import ships.
- **Plan 5:** `Hlc.parse` should reject non-canonical clocks. Re-adding a deleted track must resurrect its row, because of the unique `fileHash`/`ytVideoId` columns. Add a `local_seq` index.
- **Remove** `dependency_overrides: flutter_rust_bridge: 2.11.1` once `smtc_windows` is rebuilt against flutter_rust_bridge ≥ 2.13.

**Minor polish (none of it blocks use):**
- **Accessibility:**
  - Keyboard Tab access is excluded from the sidebar and player bar (`ExcludeFocus`).
  - The player-bar play/pause button lacks button semantics.
- **Navigation:** the Playlist page has no back arrow when opened from Home or Search.
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
- **Template leftovers:** README, pubspec description, unused `cupertino_icons`, gradle TODO comment.
