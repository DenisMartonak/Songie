# Songies Plan 3: session log (Tasks 1–8 done, stopped before Task 9)

_Written 2026-10-23._

**Where things are:**
- **Branch:** `plan-3-downloads-fixes`, made from `plan-2-youtube` at `211cfc1`. Nothing is pushed or merged.
- **Plans:**
  - [Plan 3: bug fixes and downloads](superpowers/plans/2026-10-23-songies-plan-3-fixes-and-downloads.md)
  - [Plan 4: a living UI and the theme engine](superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md), written in this session and not started
- **Tests at `246cdd1`:** 714 passing and `flutter analyze` is clean. Task 8 also built a release APK.

## What you reported, and what was done about it

| You saw (Android) | Cause found in the code | Fixed in |
|---|---|---|
| Home or Library showed an old playlist | The tabs reopened whatever page each tab had open last. The sidebar never reset it, and the phone tabs only reset on a second tap of the same tab | Task 1 |
| "Add music folder": the picker never opened | The picker library swallowed every Android error and returned "cancelled", so the app showed nothing | Task 4 |
| The next song showed as playing while the old one was still heard | The player showed the new YouTube song while it loaded, without stopping the old audio | Task 2 |
| It started changing songs by itself | One failed start made the player silently try every later song, showing each one. A late error from the old song could also be blamed on the new one | Task 2 |
| Covers looked pixelated | YouTube's playlist data only gives covers up to 336×188, which were cropped to 188 px squares | Task 3 |
| No download progress or notification | Downloads didn't exist yet | Tasks 5–8 (the data, queue and notification). **The download screens are Task 9, not built yet** |

None of these fixes has been tried on a phone. This machine has no Android device connected and can't run an emulator, so the phone checks are for you.

## Done, task by task (each reviewed by a separate reviewer)

| Task | Commits | What it does now |
|---|---|---|
| 1. Tabs open their root | `5d6b9eb` | Home, Search and Library always open their main page, on the phone, the desktop sidebar and Ctrl+K. Back inside a tab still works |
| 2. Honest playback | `b68168c`, `83e44ed` | Switching songs pauses the old audio straight away, whether through Next, tapping a song in a list or removing the current song. It stops after 3 songs in a row fail, with the reason. Each skip shows "Skipped '<title>' — <reason>". Late errors from the previous song are ignored. A YouTube stream that ends more than 5 s early gets one fresh link instead of being skipped |
| 3. Sharp covers | `80975f8` | Covers are tried at maxres → hq720 → sd → the playlist's own thumbnail. 4:3 letterbox bars are cut off, and covers are stored at up to 720 px. Old low-res covers are replaced when a song is played or synced. The yt-dlp install now only fails after 60 s with no data, not after 10 minutes in total |
| 4. Android folder picker | `2884a63` | Songies' own Android folder picker. It reports why it can't be used: Downloads or cloud folders, no file manager, already open. A folder with no MP3s says "No MP3 files in <name>" |
| 5. Download data | `1147bf5`, `3ead472` | Database v4: a per-device "Download" switch per playlist, plus queue rows in `local_files` with a request time and a "downloaded by hand" flag. Covers which songs to fetch, songs shared between playlists, and what turning a playlist off may delete. YouTube rows are kept out of all local-file logic, so they are never marked missing and never get Locate |
| 6. yt-dlp downloads | `ec5cabb`, `9379883` | Downloads run with live progress lines on desktop and Android, with cancel and a stall timeout (2 min with no output). Rate limiting (429) and full storage are recognised. On Windows, cancel ends the whole yt-dlp process tree |
| 7. Download queue | `d1f9934`, `6db5177` | 2 downloads at once on Android and 3 on desktop, first requested first. Wi-Fi only pauses on mobile data. Rate limiting waits 30 s → 10 min. A dropped connection pauses until it's back. A failed download retries with the same wait unless the phone is really offline. Full storage pauses. Interrupted downloads resume after a restart. New songs from "Sync with YouTube" are queued automatically |
| 8. Android notification | `9cb7107`, `246cdd1` | A foreground service keeps downloads going with the screen off, under a "Downloading songs · x of y · title" notification with a progress bar. Paused states say why. A finished run posts "Downloaded n songs". If Android refuses the service, a plain notification is used instead |

## Not done yet

1. **Task 9, the download UI.** The Download switch on playlists, progress rings, per-song icons, the app-wide indicator and downloads panel, the "Downloads failing" banner and the Settings → Downloads sizes. Until Task 9 there is no button to start downloads.
   - Its callers must also invoke `ensureNotificationPermission()` and `DownloadService.resume()` (see the rulings).
2. **Task 10.** Docs, the checklist, the release builds and a real download test on Linux.
3. **The final whole-branch review**, then one batch of fixes from it.
4. **Your phone checks** for Tasks 1–4 now, and for Tasks 5–9 once Task 9 exists.

**To resume in a new Claude session:**
> Continue Songies Plan 3 subagent-driven on branch `plan-3-downloads-fixes`, starting at Task 9. Tasks 1–8 are done. Read docs/plan-3-session-log.md. Don't push or merge.

The workflow's working files (ledger, task briefs, reports, review diffs) are in `.superpowers/sdd/2026-10-23-songies-plan-3-fixes-and-downloads/`. That folder is git-ignored, and its ledger is what a new session resumes from. This document repeats everything in it that matters.

## Decisions I made on your behalf

Each line says what I decided and what it costs if it's wrong.

**While writing the plans**
- **Single songs can be downloaded**, not only whole playlists, because you asked for it. *If wrong:* one menu item.
- **Covers are stored at 720 px instead of the spec's 512.** *If wrong:* more disk used by the art cache.
- **Android uses Songies' own folder picker.** *If wrong:* some Kotlin to maintain.
- **Downloads use an Android foreground service**, which needs a permanent notification while they run. *If wrong:* one service.
- **Playback stops after 3 failed songs in a row.** *If wrong:* a different number.
- **Plan 4:**
  - Colours come from `material_color_utilities`, because `palette_generator` is discontinued.
  - "Album glow" becomes the default theme on fresh installs.
  - Lyrics become their own Plan 5, so device sync is Plan 6 and packaging Plan 7.
  - There's a "Reduce animations" setting.
  - *If wrong:* the default theme, and the plan order.

**Before starting** (gaps between tasks in the plan)
- **A cover-refresh call** (`refreshArtwork`) runs after a song is played, synced or downloaded. *If wrong:* a rename.
- **The queue reacts to database changes** instead of polling, which the plan forbids. *If wrong:* one extra watcher.
- **YouTube download rows are kept out of all local-file logic:** no missing flags, no rescans, no Locate. *If wrong:* a few query conditions.
- **Error text:**
  - Rate limiting: "YouTube is limiting downloads — retrying soon".
  - Full storage: "Storage is full — free up space and retry".
  - *If wrong:* copy edits.
- **Notification permission** is asked once per app run, the first time you download, on Android 13+. Refusing it never blocks downloads. *If wrong:* nothing.

**During the tasks**
- **Songs already marked unavailable** are skipped silently and don't count toward the 3-song stop. *If wrong:* you're not told why a greyed song was passed over.
- **The "song ended early" check only applies to YouTube streams.** Local MP3 durations can be wrong, which would cause false "Skipped" messages. *If wrong:* a dying local file isn't retried.
- **Task 5's tests were written after its code.** I accepted them because they test real database behaviour. Every fix after that had to show a failing test first. *If wrong:* a test that can't fail.
- **Commit attribution:** commits made by the Sonnet-model helpers carry a "Claude Sonnet 5.5" line, not the plan's "Opus 5.5" line. I left history alone. *If wrong:* those messages are reworded before merging.
- **Downloaded files of songs you later remove from a downloaded playlist aren't cleaned up yet.** The spec only covers cleanup when the switch is turned off. *If wrong:* some leftover MB until cleanup is added.
- **A user's cancel looks like a failure to yt-dlp**, so the queue tracks the cancels it sent, including ones sent before the download started. *If wrong:* nothing.
- **Playback treats "YouTube is limiting" and "storage full" as skip-worthy**, not as reasons to stop at once. The 3-song stop catches them. *If wrong:* up to 3 skipped songs.
- **Every pause cancels the downloads in progress and re-queues them.** yt-dlp resumes the partial file. *If wrong:* a few partial downloads restart.
- **Download retries:**
  - A failed download on working Wi-Fi retries on the 30 s → 10 min ladder. The plan's text said to wait for a network change, which could stall forever.
  - Only a real offline state pauses as "offline".
  - *If wrong:* a few retries against a dead connection.
- **A stuck "run never ends" case was fixed**, so the notification always finishes. *If wrong:* nothing.
- **The Downloads panel's Resume button must call the queue's resume** (Task 9), or a full-storage pause can only be cleared by restarting the app. *If wrong:* nothing.
- **Unavailable songs drop out of the run's total** instead of counting as failed. *If wrong:* the summary says "4 of 4" when 5 were asked for.
- **A connection problem gets its own pause text:** "Paused — connection problem, retrying in <m> min". "YouTube is limiting downloads" is kept for real rate limiting. *If wrong:* one more pause state.
- **"Downloaded 1 song"** uses the singular, as Plan 2 did. *If wrong:* one string.

## Smaller issues left for the final review

These were found in task reviews, judged not worth a fix round, and noted for the final review to sort.

- **Task 1:** no test for typing in the desktop search box. The phone tests open a playlist through the router, not by tapping a card.
- **Task 2:**
  - An early-ended stream restarts at 0:00 instead of where it stopped.
  - An old "Skipped" notice can carry into a new queue.
  - Two tests are missing: that a failed retry counts toward the 3-song stop, and that the counter resets on remove.
  - Debug logging is silenced for the whole player test file.
  - A YouTube error without the yt-dlp tag shows as raw text.
  - `player_service.dart` is about 920 lines.
- **Task 3:**
  - Unrelated formatting changes are in two files.
  - The cover refresh has no in-flight guard, so a song can be re-fetched while a fetch is pending, or forever if every cover URL misses.
  - Old `sq-` cover files stay on disk.
  - The 720 px limit also applies to local MP3 art.
- **Task 4:**
  - Picking the "Documents" root (`home:`) maps to a non-existent path.
  - If Android recreates the app while the picker is open, the pick never returns.
  - Desktop picks aren't logged.
  - Small style and test gaps.
- **Task 5:**
  - Two methods check, then act, outside one transaction.
  - Some queue moves throw raw database errors.
  - `removeFiles` counts freed bytes even when a delete failed.
  - A latent edge with soft-deleted tracks.
  - `retryFailed` can re-queue songs that have become unavailable.
  - One missing test.
- **Task 6:**
  - No test that output resets the stall timer.
  - An unhandled-error edge on the desktop timeout path.
  - A stall at the very moment of success reports a network error.
  - One test prints a stack trace.
- **Task 7:**
  - Rare internal errors can leave the queue idle until the next event.
  - A failure before a run starts isn't counted.
  - The "current title" can name a song that's only reserved.
  - The sync hook only catches database errors.
- **Task 8:**
  - Each progress update restarts the service call.
  - The "retrying in <m> min" text goes stale during a long wait.
  - Cancelling everything posts "Downloaded 0 songs".
  - The notifier choice is duplicated in two files.
  - An extra Android library was added.
  - A stop can leave a "refused" flag set for the next run.
  - A stop briefly starts the service.

## Your checks once Task 9 exists (phone)

1. **Folders:** Library → + → Add music folder opens the picker. Picking Music adds MP3s. Picking Downloads shows the "can't be used" message.
2. **Playback:** tapping songs and Next never plays one song while showing another. A dead song shows "Skipped …", and 3 in a row stop with a message.
3. **Tabs:** Home and Library always open their main page.
4. **Covers:** sharp on Now Playing, after replaying older songs.
5. **Downloads:**
   - The notification appears and keeps going with the screen locked.
   - Wi-Fi off with Wi-Fi only on → "waiting for Wi-Fi", and it resumes when Wi-Fi returns.
   - Downloaded songs play in airplane mode.
6. **If anything misbehaves:** Settings → Export log, then send me the file.
