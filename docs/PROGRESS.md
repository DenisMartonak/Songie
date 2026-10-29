# Songies — Progress

_Last updated: 2026-10-29_

## Plan 9 (listening statistics) — implemented, reviewed task by task; final review pending

- **Branch:** `plan-9-stats` (from `plan-8-lyrics`). Plan: [Plan 9](superpowers/plans/2026-10-29-songies-plan-9-listening-stats.md). Spec: [Listening stats design](superpowers/specs/2026-10-29-songies-listening-stats-design.md). Session log: [plan-9-session-log.md](plan-9-session-log.md). Nothing is pushed or merged.
- **Status:** Tasks 1–6 are done and Tasks 1–5 were each reviewed. The final whole-branch review is pending. Tests: 1,751 passing, `flutter analyze` clean, `flutter build apk --release` succeeds (81.3 MB), `flutter build linux --release` succeeds (bundle 35 MB). Windows is built on your PC. The secret scan of the branch history found only doc text. **Nothing has been run on a device yet.**
- **What it does now:**
  - **Recording:** every song you play is saved as a "listen" (new `listens` table, schema 7, synced like the other tables). Minutes count all the time you heard. A play counts after 30 s, or the whole song when it is shorter. Pausing doesn't end a listen and seeking doesn't start one. A force-quit loses at most about 30 s.
  - **Home:** a compact "Your listening" card with the last 7 days' minutes, a tiny chart and your top artist. Tapping it opens the stats page. Your playlists stay visible.
  - **Stats page:** pick 7 days, 1 month, 6 months or 12 months. It shows total minutes against the period before, a bar chart, top artists and top songs (top 5, with Show top 10). Tapping a top song plays it.
  - **Main artist:** a song counts for its first artist only (text before the first comma for YouTube songs; before a comma, semicolon, "/", "feat." or "ft." for local files). "&", "+" and " x " never split a name.
  - **No idle work:** recording happens only when the player does something. No timers while nothing plays and no background jobs.
- **Rulings** (each with its cost if wrong; the full text is in the session log):
  - **S1:** a comma inside a real band name (for example "Earth, Wind & Fire") is split like a featured artist, because tracks only keep YouTube's comma-joined artist line. Cost: such bands count under their first word.
  - **S2:** the last listen of a session is saved when playback stops and when it first counts as a play. Cost: one extra write per pause.
  - **S3:** listens are kept for **730 days**, not the brief's 400. The 12-month view compares with the 12 months before it, so it needs two years. The previous period is summed in SQL. Cost: about twice the table size (still small).
  - **S4:** tapping a top artist opens Search with their name, because tracks store no artist id. Cost: one tap leads to search results instead of an artist page.
  - **S5:** a removed song's row has no menu. Cost: one menu missing on removed songs.
  - **S6:** year-view bar labels keep the year ("Oct 2026"). Cost: none.
- **Next:** your device checks (the Plans 7, 8 and 9 sections of the [manual checklist](manual-test-checklist.md), plus the still-pending live sign-in check from Plan 7), then device sync and packaging.
- **To resume in a new Claude session:**
  > Songies Plan 9 is implemented on branch `plan-9-stats` (Tasks 1–6 done and reviewed; final review pending). Next: the device checks, then plan device sync. Read docs/PROGRESS.md. Don't merge.

## Plan 8 (synced lyrics) — done, reviewed, final review fixed

- **Branch:** `plan-8-lyrics` (from `plan-7-youtube-login`). Plan: [Plan 8](superpowers/plans/2026-10-29-songies-plan-8-lyrics.md). Spec: [Lyrics design](superpowers/specs/2026-10-29-songies-lyrics-design.md). Session log: [plan-8-session-log.md](plan-8-session-log.md). Nothing is pushed or merged.
- **Status:** Tasks 1–9 are done and each was reviewed. The final whole-branch review ran; its fixes (lyrics contrast over the blurred cover, the lyrics panel on narrow windows and Android tablets, and three small items) landed and were reviewed. Tests: 1,636 passing, `flutter analyze` clean, `flutter build apk --release` succeeds (81.3 MB), `flutter build linux --release` succeeds (bundle 35 MB). Windows is built on your PC. The secret scan of the branch history found only doc text, and the lyric fixtures hold invented lines only. **Nothing has been run on a device yet.**
- **What it does now:**
  - **Where:** a Lyrics tab next to Queue on Now Playing (phone), a right-side panel on desktop toggled from the player bar (it stays open across tabs), and a Lyrics tab in the desktop Now Playing dialog.
  - **Lookup:** your own `.lrc` file next to the song, then LRCLIB, then YouTube Music (YouTube songs only). Timed lyrics beat plain ones. Lookups happen only while a Lyrics view is open; there is no background fetching.
  - **Reading:** the current line is highlighted and followed, tapping a line seeks, scrolling by hand pauses following for 5 s, and reduced motion jumps instead of scrolling. Nothing moves while paused.
  - **Offline:** results are cached on the device (the new `lyrics` table, schema 6, synced like the other tables). Seen lyrics show offline; others say "Lyrics need a connection". "No lyrics found" has a Search again button.
  - **Credit:** a small line at the end ("Lyrics from LRCLIB", "Lyrics from YouTube Music", "Lyrics from the file").
- **Rulings** (each with its cost if wrong; the full text is in the session log):
  - **R1:** YouTube Music lyrics are plain only. Cost: songs LRCLIB lacks aren't timed.
  - **R2:** an LRCLIB timed answer with fewer than 2 timed lines is ignored. Cost: a real one-line lyric is dropped.
  - **R3:** an instrumental LRCLIB search result is skipped if another in-range result has lyrics. Cost: an instrumental may show another version's lyrics.
  - **R4:** the best online result is still cached when your file's plain lyrics are shown. Cost: a cached lyric you never see.
  - **R5:** timed lyrics use a plain scrolling column. Cost: slower layout on a very long lyric.
  - **R6:** small dim lines meet 4.5:1, large ones 3:1. Cost: small dim lines look a little less dim.
  - **R7:** the desktop dialog's Lyrics tab uses the smaller text. Cost: a one-word change.
  - **R8:** the player bar volume slider is flexible (up to 104 px). Cost: a narrower slider on narrow windows.
  - **R9:** online but every source failing shows "No lyrics found" (with Search again), not cached; the connection message is only for offline. Cost: an LRCLIB outage reads as "No lyrics found".
  - **R10:** under 1000 px the open lyrics panel holds the sidebar collapsed; if the main pane would still be under 360 px, the panel lies over the content. Cost: icon-only sidebar, or a covered strip of the page, on narrow windows.
  - **R11:** when every online source fails, the connection is checked again: offline shows the connection message, online shows "No lyrics found". Cost: one extra connection check per failed lookup.
  - **R12:** one dim-line brightness everywhere, readable on the blurred cover. Cost: desktop panel dim lines slightly brighter than needed.
  - **P1–P3:** the YouTube lyrics source lives in `lib/lyrics/ytm_lyrics.dart`; Search again bumps a retry counter that skips the cache; precedence is timed first, then your file's plain lyrics, then online plain.
- **Next:** your device checks (the Plans 7 and 8 sections of the [manual checklist](manual-test-checklist.md), plus the still-pending live sign-in check from Plan 7), then **Plan 9 (listening statistics)**, then device sync and packaging.
- **To resume in a new Claude session:**
  > Songies Plan 8 is implemented on branch `plan-8-lyrics` (Tasks 1–9 done and reviewed; final review fixed). Next: the device checks, then write Plan 9 (listening statistics). Read docs/PROGRESS.md. Don't merge.

## Plan 7 (YouTube sign-in for a personal feed) — done, reviewed; live check pending

- **Branch:** `plan-7-youtube-login` (from `plan-6-song-menu`). Plan: [Plan 7](superpowers/plans/2026-10-28-songies-plan-7-youtube-login.md). Spec: [YouTube login design](superpowers/specs/2026-10-27-songies-youtube-login-design.md). Both `plan-6-song-menu` and `plan-7-youtube-login` are pushed; nothing is merged.
- **Status:** Tasks 1–7 are done and each was reviewed. The final whole-branch review ran (no secret leak; ready to merge with fixes) and its fix wave landed: the session keeps only the cookies a browser sends to music.youtube.com, never google.com ones (R8), and signed-in play reports go only to https YouTube hosts; a bad cookie value no longer breaks Home; a keyring hiccup no longer signs you out; unlocking the keyring later restores the sign-in without a restart; "Sign in again" offers every route. Tests: 1,457 passing (1,430 before the fix wave), `flutter analyze` clean, `flutter build apk --release` succeeds (81.2 MB), `flutter build linux --release` succeeds (bundle 34 MB). Windows is built on your PC. **No live sign-in has been run**: the Task 1 probe never ran, so the personal feed, history attribution and expiry detection are marked "manual check pending" in [innertube-notes.md](innertube-notes.md).
- **What it does now:**
  - **Sign in:** Settings → YouTube. Android and Windows open Google's page in an in-app web view; Linux opens it in a WebKitGTK window, or reads the sign-in from your browser ("Use the YouTube sign-in from my browser", Firefox family and Chromium family, Flatpaks included, only after you pick and confirm).
  - **Personal feed:** only the Home `browse` request and play reports go out signed in. Qualifying plays are reported with account tracking URLs so they count in YouTube Music history.
  - **Expiry:** a signed-out Home answer or HTTP 401/403 shows the regular feed once, marks "Sign in again" and shows one notice. No retry loop.
  - **Storage:** the session lives only in secure storage (`yt_session`: Keystore, Credential Manager, libsecret). Never in drift, logs, exports or sync. No keyring means sign-in isn't offered, with an explanation. Sign out clears the session and the web view data.
- **Linux packages needed to build:** `libsecret-devel` and `webkit2gtk4.1-devel` (installed on this machine). `libwebkit2gtk-4.1` becomes a runtime dependency. Windows builds need `nuget.exe` on PATH (see the checklist).
- **Pinned beta packages:** `flutter_inappwebview` 6.1.5 breaks the Android release build under AGP 9, so `pubspec.yaml` pins `flutter_inappwebview_platform_interface` 1.4.0-beta.3, `flutter_inappwebview_android` 1.2.0-beta.3 and `flutter_inappwebview_windows` 0.7.0-beta.3. TODO: replace with stable 6.2.x once published.
- **Rulings:**
  - **R1:** a signed-in WEB_REMIX `player` call after a play qualifies (tracking URLs only, never streaming). Cost: one extra request per qualifying play.
  - **R2:** the Linux dev packages need sudo; the user installed them.
  - **R3:** browser cookie discovery includes Flatpak profiles under `~/.var/app/`.
  - **R4:** real signed-in responses are never committed as fixtures; signed-in fixtures stay hand-crafted.
  - **R5:** startup reads no secure storage; a non-secret marker (`yt_signed_in`) plus the cached name give the startup state, and the keyring is read on demand. Cost: the first signed-in Home load waits for the keyring once.
  - **R6:** expiry means an explicit signed-out marker or HTTP 401/403 only. Cost: a stale session answering 200 with no marker shows the regular feed without a notice.
  - **R7:** the browser route asks first and lists browsers by path only; no cookie database is touched until you confirm.
- **Parked items (deferred minors, summarised):**
  - Sign-in state: `ensureSession` has no in-flight dedup; no retry after a keyring failure until restart or sign-in; the generation guards are untested; `forget()` isn't awaited at sign-out; a completion re-check can be dropped while one is in flight.
  - Tracking: `accountTracking` has no unit test of its own; the `playbackTracking` parse is duplicated; the first signed-out play with no anonymous tracking marks itself reported.
  - Browser route: WebKit's native `clearAll` isn't awaited; the cancel test is weak; quoted cookie values are rejected (fails safe).
  - Fixtures and probe: the scrub test picks signed-in fixtures by filename and misses `SID=`/`HSID=`-style names; the probe's `OUT` isn't resolved through symlinks.
- **Incident (resolved):** during Task 6, a test run deleted two leftover WebKit probe folders (`~/.local/share/com.songies.songies` and `~/.cache/com.songies.songies`). They held only probe leftovers; the real data folder was untouched. The test now injects its own directories.
- **Stash:** `stash@{0}` holds unrelated `dart format` changes from Task 6; left alone.
- **Next:** your device checks (the Plan 6 and Plan 7 sections of the [manual checklist](manual-test-checklist.md)), then **Plan 8 (synced lyrics)**, **Plan 9 (listening statistics)**, then device sync and packaging.
- **To resume in a new Claude session:**
  > Songies Plan 7 is implemented on branch `plan-7-youtube-login` (Tasks 1–7 done and reviewed, final review fixed, 1,457 tests; Plan 6 is on `plan-6-song-menu`; both pushed). The live sign-in check is still pending. Next: the device checks, then write Plan 8 (synced lyrics). Read docs/PROGRESS.md. Don't merge.

## Plan 6 (the one song menu) — done, reviewed

- **Branch:** `plan-6-song-menu` (commits `60ba176` and `80d415f`), pushed. One song menu now opens from every song row (library, playlist, search, YouTube Music results, Home), by long-press or right-click, with Play next, Add to queue, Add to playlist, Download, Start radio, Go to artist and Go to album and, inside a playlist, Remove from this playlist. It also opens from the queue, the YouTube Music album, artist and playlist pages, and the Now Playing ⋯ button. (The roadmap numbers shifted: lyrics are now Plan 8 and statistics Plan 9.)

## Plan 5 (YouTube Music) — done, reviewed, final review fixed

- **Branch:** `plan-5-youtube-music`. Plan: [Plan 5](superpowers/plans/2026-10-25-songies-plan-5-youtube-music.md). Spec: [YouTube Music design](superpowers/specs/2026-10-25-songies-youtube-music-design.md). Session log: [plan-5-session-log.md](plan-5-session-log.md). The branch is pushed; nothing is merged.
- **Status:** Tasks 1–11 are done and each was reviewed by a separate reviewer, with its fixes applied. The final whole-branch review ran (ready to merge with fixes) and its one fix wave landed: yt-dlp now confirms an unavailable song before it is marked (R12), a broken home response shows Retry, the radio continuation waits for the queue append, the song menu reads providers before awaiting, artist shelves match "EPs" as a word, the empty Search text mentions YouTube Music, and the checklist spells out the Wi-Fi upgrade note. Tests: 1,278 passing (1,270 before the fix wave), `flutter analyze` clean, `flutter build apk --release` succeeds (80.2 MB), and `flutter build linux --release` succeeds (bundle 34 MB). The Linux release bundle was launched for 12 s with no errors (`media_kit_libs_linux registered`); audio was not listened to. The first APK attempt died when the Gradle daemon was OOM-killed on this 7 GB machine (`org.gradle.jvmargs=-Xmx8G`) while the NDK and SDK platform were first installed; the retry built cleanly. Windows is built on your PC.
- **What it does now:**
  - **Instant streams:** songs resolve through YouTube's Innertube `player` API (one client after another), then yt-dlp, then the Plan 3 skip-and-notice path. A failing Innertube route never shows an error by itself. Live on this host: Innertube 68–148 ms per song, yt-dlp 1972–2493 ms (stream lookup only; see [innertube-notes.md](innertube-notes.md), "Live check").
  - **Search:** YouTube Music results under a short library section, with tabs (songs, albums, artists, playlists), song rows, a song menu and load-more. Only the last query's results are shown.
  - **Radio:** tapping a searched song plays it and fills the queue from its radio, which extends itself; artist pages start an artist radio.
  - **Home:** YouTube Music rows below your library, the EU consent sheet, and Settings → Reset YouTube recommendations.
  - **Pages:** artist, album and YouTube Music playlist pages with a palette from the shown cover, Play/Shuffle and **Import as playlist**.
  - **Library stays yours:** a played search, feed or radio song becomes a normal `tracks` row but shows in Library lists, local search and the add-songs picker only while a playlist holds it; Recents and history show everything played.
  - **Settings:** "Wi-Fi only downloads" (the old key) and the new device-local "Wi-Fi only streaming" (off by default). Search, browse and covers ignore both.
  - **Play reports:** a song heard for 30 s (or to its end if shorter) is reported to YouTube, so the feed learns; the same rule (`kPlayThreshold`) will drive Plan 7's statistics.
  - **Dev only:** `--dart-define=SONGIES_FORCE_YTDLP=true` (ignored in release builds) skips Innertube; `flutter test tool/stream_timing.dart` times both routes and live-checks continuations.
- **Live checks (2026-10-27, all pass):** a search continuation returns 20 new songs (ruling R6); a radio continuation returns 49 new songs; artist radio (`RDEM…` with the seed videoId) returns 49 songs; consent was not asked from this host.
- **Linux / libmpv:** `mpv-libs-devel` is **not** installed on this host and is not needed: the Linux release build links and runs against the runtime `mpv-libs` (0.41), which is installed. If a future Linux build fails on a missing libmpv, install the headers with `sudo dnf install mpv-libs-devel`.
- **Rulings** (each with its cost if wrong; the full text is in the session log):
  - **R1, R11:** commits end with `Co-Authored-By` and `Claude-Session` trailers; R11 names the session that made the commit.
  - **R2** (stop-on-notFound superseded by R12): Innertube reports a song unavailable only when every client tried says so at video level (unplayable, an error that isn't "reload", or an age login); any other failure falls through to yt-dlp. Cost: a few truly unavailable songs take one slow yt-dlp try before the skip.
  - **R12** (supersedes R2's stop-on-notFound): `FallbackStreamSource` stops on `notFound` only from the LAST source; an Innertube `notFound` falls through to yt-dlp, and only yt-dlp's `notFound` marks the song unavailable. Cost: about 2 s once per truly dead song.
  - **R2b:** a visitor id is fetched (one request) before the first `player` call when none is stored; a "not a bot" login is a client-level failure. Cost: one request on first play.
  - **R3:** fixtures YouTube didn't serve here (per-kind search tabs, video-level unplayable) are hand-made from real rows (`*_handcrafted.json`). Cost: tab parsers rest on reshaped rows; the live run above covered search.
  - **R4:** play reports use `playbackUrl` + `ver=2&cpn=…`, and watchtime adds `st=0&et=<heard s>&cmt=<pos s>`. Cost: YouTube may ignore them and the feed is less personal.
  - **R5:** after **Accept**, Innertube requests carry `Cookie: SOCS=CAI`.
  - **R6:** continuations go both as ytmusicapi-style query parameters and in the body. Verified live.
  - **R7:** the playlist-reachability filter hides only `yt` tracks; scanned local files stay visible.
  - **R8:** "artist is the channel name" is approximated: a `yt` row with no album takes the richer artist; rows with an album keep theirs. Cost: an imported row with a hand-fixed artist but no album is overwritten once.
  - **R9:** **Not now** on the consent sheet lasts for the app session; **Accept** is permanent per device.
  - **R10:** real-network timing uses the dev tool (stream lookup, not player start-up); the Linux build is recorded as blocked if libmpv is the only failure.
  - Task 1: the fixture scrub also replaces the `fexp` and `initcwndbps` URL parameters (nothing parses them).
- **Parked items (deferred minors that matter):** the full list is in the ledger and session log. The ones worth doing first:
  - Radio: `_start` has no try/catch; `_becomeQueue` doesn't clear the source playlist or notice. (The early continuation fetch is fixed: `_continuation` is set after `addToQueue` returns.)
  - ~~Now Playing title/artist stay stale after a metadata upgrade (branch-wide).~~ Fixed: the queue now picks up covers and details that arrive after a song was queued (`PlayerService.updateTrack`, fed by `YtTrackStore.changes`).
  - Song menu: Play next / Add to queue use `ref` after `await` without a `mounted` check.
  - Consent: `ConsentListener` is mounted only on Home (move it to the shell); an in-flight request can re-store the old visitor id right after Reset.
  - A revived deleted `yt` row keeps `unavailable` and can overwrite a known duration with 0.
  - Album page: the header's playlist id isn't checked for the `OLAK5uy_` prefix (Import could pick an `RDAM` id); YTM playlist continuations need a seen-set guard against cycling tokens.
  - Play reports: repeat-one doesn't re-report (decide for Plan 7); short forward seeks count as heard.
  - Parser robustness: artist page `title.contains('ep')` sorts "Deep cuts" as singles; a missing home section list logs nothing.
  - Tests: no test pins the `stream … via … in … ms` log line or a shared visitor bootstrap for concurrent first plays.
- **Next:** your device checks (the Plan 5 section of the [manual checklist](manual-test-checklist.md)), then **Plan 6 (synced lyrics)**. The roadmap is now: **6 lyrics, 7 statistics, 8 device sync, 9 packaging.**
- **To resume in a new Claude session:**
  > Songies Plan 5 is implemented on branch `plan-5-youtube-music` (Tasks 1–11 done and reviewed, final review fixed, 1,278 tests). Next: the device checks, then write Plan 6 (synced lyrics). Read docs/plan-5-session-log.md. Don't merge.

## Plan 4 (a living UI and the theme engine) — done, reviewed, final review fixed

- **Branch:** `plan-4-alive-ui-themes`, made from `plan-3-downloads-fixes` at `766750b` (Plan 3 isn't merged, so Plan 4 builds on it). Plan: [Plan 4](superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md). Nothing is pushed or merged.
- **Status:** Tasks 1–10 are implemented and each was reviewed by a separate reviewer, with its fixes applied. The final whole-branch review ran and its one fix wave landed. Tests at `69dce2c`: 1,047 passing, `flutter analyze` clean, `flutter build apk --release` (79.9 MB) and `flutter build linux --release` (bundle 34 MB) succeed. Windows is built on your PC.
- **What it does now:**
  - **Themes:** Settings → Appearance → Themes lists the three built-ins (Default, Album glow, Terminal) and your own. A live editor changes base, colours, follow-cover, glow, corner radius, font, font size and the Now Playing blur; editing a built-in saves "<name> copy". Themes export and import as spec §9 JSON files (with their imported font), and themes and fonts live in tables ready for device sync (schema v5: `themes`, `fonts`; the sync itself is Plan 6). A fresh install starts on Album glow.
  - **Fonts:** Inter, Outfit and JetBrains Mono are bundled (OFL); `.ttf`/`.otf` files can be imported and are kept in `<appData>/fonts/<sha256>.<ext>`.
  - **Colours from the cover:** with "Follow cover", the accent, glow and tints come from the playing song's art and fade over 600 ms; skipped-past songs are never analysed. Text keeps 4.5:1 contrast, falling back to white or black.
  - **Motion:** shared motion tokens, shared-axis page transitions, press feedback, list entrances and loading shimmer; Settings → Reduce animations (and the system setting) turns all of it off.
  - **Now Playing:** cover breathes and slides on skips, scrolling long titles, buffered bar, remaining time, swipe down to close (phone and desktop), the cover flies to and from the mini player.
  - **Pages and shell:** playlist header in the cover's colour with a floating Play button that pins to the top bar, Home glow and greeting, equalizer bars on the playing playlist, mini player swipe-to-skip, nav icon bounce, sliding sidebar selection bar, thicker scrubber/volume on hover.
  - **Battery:** nothing animates while paused. A new test (`test/ui/idle_frames_test.dart`) pumps the whole app on Album glow and checks that no frame is scheduled once paused and settled, on Home and on Now Playing, at phone and desktop widths (the desktop shell stays painted behind the Now Playing panel), and that a backgrounded app schedules none even while playing. It passed on its first run; removing either the "only while playing" or the "only while on screen" rule makes it fail.
- **Rulings:** see [plan-4-session-log.md](plan-4-session-log.md) for the full list, each with its cost if wrong. The main ones: fresh install gets Album glow (decided once); theme names are unique ignoring case and against built-ins; Album glow's glow strength is 0.65; static font weights cut from Google's variable Outfit/JetBrains Mono; Songies' own HSV colour picker; `animations` 3.0.0; muted text is worked out, not stored (Terminal's grey becomes #a0a0a0); light themes get light-style dialogs and switches; imported theme files are saved but not switched to; the playlist page's Play button floats (the one layout change); shimmer may run while loading but stops in the background.
- **Final review:** the final whole-branch review ran (ready to merge with fixes), and its fix wave landed: `fromJson` clamps and opaque colours, a readable Now Playing top on light Follow-cover themes, muted text from the readable text, a guarded font rollback on a failed theme import, and theme-text tints (not white) for hover, the selected sidebar row, the mini-player track and the title-bar buttons. Tests: 1,047 passing, `flutter analyze` clean.
- **Parked items (deferred minors):** the "Smaller issues left for the final review" list in the session log, task by task. Done in the final fix wave: `ThemeSpec.fromJson` now clamps glow strength, corner radius and font scale and makes every colour opaque, and theme files with out-of-range values or a see-through colour are rejected. Still open from earlier: the APK build prints a harmless "Expected to find fonts for CupertinoIcons" note. Device sync (Plan 6) must re-register a synced font when its file arrives.
- **Next:** your device checks (the Plan 4 section of the [manual checklist](manual-test-checklist.md)), then **Plan 5 (lyrics)**, written from spec §10.
- **To resume in a new Claude session:**
  > Songies Plan 4 is implemented on branch `plan-4-alive-ui-themes` (Tasks 1–10 done and reviewed, final review fixed, 1,047 tests). Next: the device checks, then write Plan 5 (lyrics) from docs/superpowers/specs/2026-10-21-songies-design.md §10. Read docs/plan-4-session-log.md. Don't push or merge.

## Plan 3 (bug fixes + downloads) — done and reviewed; final whole-branch review done and its fixes applied

- **Branch:** `plan-3-downloads-fixes` (from `plan-2-youtube`). Plan: [Plan 3](superpowers/plans/2026-10-23-songies-plan-3-fixes-and-downloads.md). Nothing is pushed or merged.
- **Status:** Tasks 1–10 are implemented and were reviewed by separate reviewers. The final whole-branch review is done, and its fix wave is applied: YouTube download rows are filtered in SQL (large local libraries no longer hit "too many SQL variables"), a run that finished nothing posts no "Downloaded 0 songs", the Android picker's Documents root maps to `/storage/emulated/0/Documents`, and offline playback skips undownloaded YouTube songs quietly (outside the 3-in-a-row cap) instead of stopping. Tests: 769 passing, `flutter analyze` clean, `flutter build apk --release` and `flutter build linux --release` succeed (APK 79.0 MB). Windows is built on your PC.
- **What it does now:**
  - Home/Library/Search tabs always open their root.
  - Playback no longer shows one song while playing another; failed songs show "Skipped …" and 3 in a row stop playback.
  - Covers are sharp (maxres first, letterbox cut, stored at 720 px).
  - Android has its own folder picker that says why it can't be used.
  - Per-device Download switch beside "Sync with YouTube" in the playlist hero, with progress rings, per-song icons, an app-wide indicator and Downloads panel, a "Downloads failing — update yt-dlp?" banner and Settings → Downloads. Remove downloads? offers Keep files / Remove.
  - Files go to `<appData>/library/yt/<videoId>.<ext>`; 2 at a time on Android, 3 on desktop; Wi-Fi only pauses on mobile data; 429 backs off 30 s → 10 min; offline pauses and resumes; full storage pauses.
  - Android: a foreground-service notification ("Downloading songs · x of y", "Paused — waiting for Wi-Fi", "Downloads paused", "Downloaded n songs").
- **Verification on Linux:** the in-app GUI could not be driven from the agent. Instead yt-dlp 2026.08.19 was run with the app's exact download args (format `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`, `--no-playlist --continue --no-mtime`, output `%(id)s.%(ext)s`) in a scratch directory for the first 3 songs of the test playlist (`PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI`): 3 `.webm` files (3.9 MB, 10.4 MB, 3.7 MB) downloaded. yt-dlp warned "no JavaScript runtime found" during this smoke test (it fell back to clients that don't need JS); the downloads still worked. **Still a manual check for you:** the in-app Linux flow (files in `~/.local/share/songies/library/yt/`, `FileSource` log line on play, Remove deletes them); it is in [manual-test-checklist.md](manual-test-checklist.md).
- **Rulings:** see [plan-3-session-log.md](plan-3-session-log.md) for the full list. Task 9 added: the Download toggle sits beside "Sync with YouTube" (the Play/Shuffle row overflowed 400 px phones); a user pause only blocks new slots (running downloads finish) and shows as "Paused" / "Downloads paused" via `DownloadPauseReason.user`; Settings → Downloads resumes any resumable pause; the singular "Remove downloads?" copy; the downloads banner is keyboard-reachable.
- **Parked items (deferred minors):** the per-task lists in the session log, plus Task 9: banner/indicator heights are hardcoded in the phone overlay padding (covered by the 400 px shell test, phone check is yours); the status line rebuilds on each progress tick (needed for the combined fraction); `track_download_icon` catches `on Exception` where others catch `DownloadDbException`; "Retry failed" is always shown in the Downloads panel; no build-count test for the rebuild-scoping rule. Task 8 minors also remain (service restarts each update, stale "retrying in" text, duplicated notifier choice, extra core-ktx dependency, stop/refused-flag edge cases).
- **Next:** your device checks, then [Plan 4](superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md) (a living UI and the theme engine). Roadmap renumbered: Plan 5 = lyrics, Plan 6 = device sync, Plan 7 = packaging.
- **To resume in a new Claude session:**
  > Songies Plan 3 is implemented on branch `plan-3-downloads-fixes` (Tasks 1–10 done and reviewed, final review fixed). Next: the device checks, then start Plan 4. Read docs/plan-3-session-log.md. Don't push or merge.

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
3. **Write Plan 2** (YouTube import, Sync with YouTube, streaming), then Plans 3–7 (downloads, a living UI and themes, lyrics, device sync, packaging). The roadmap at the top of the Plan 1 file uses the old numbering; Plan 3 renumbered it.

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
- **`ThemeSpec.fromJson` range checks** (glowStrength, fontScale, cornerRadius): done in the Plan 4 final fix wave (stored rows are clamped, theme files are rejected).
- **Plan 6 (device sync):** `Hlc.parse` should reject non-canonical clocks. Re-adding a deleted track must resurrect its row, because of the unique `fileHash`/`ytVideoId` columns. Add a `local_seq` index.
- **yt-dlp JavaScript runtime** (from the Plan 3 final review): since late 2025 yt-dlp wants an external JS runtime (only deno is enabled by default) for YouTube's player challenges, and without one it falls back to JS-free clients. If YouTube drops those, streaming and downloads both fail.
  - **Desktop:** detect `deno`/`node` on PATH and pass `--js-runtimes`, or have the installer fetch deno.
  - **Android:** check yt-dlp's stderr on the device for the same "no JavaScript runtime found" warning (yt-dlp enables only deno by default, so the bundled QuickJS may not be used).
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

## Plan 7 platform notes (flutter_secure_storage)
- Linux: needs `libsecret-1-dev` (Fedora: `libsecret-devel`) at build time and a running Secret Service (GNOME Keyring or KWallet) at run time. No extra CMake edits; `flutter build linux --release` verified. No keyring means `YtAuthUnavailable`.
- Android: minSdk 24 already meets the plugin's requirement; Keystore-backed.
- Windows: Credential Manager, no setup; built on the user's PC (checklist item).
