# Songies Plan 8 (synced lyrics): session log

_Last updated: 2026-10-29. **Plan 8 is implemented on branch `plan-8-lyrics`; Tasks 1–9 are done and reviewed. The final whole-branch review is pending.** Nothing is pushed or merged._

**To resume (next plan):**
> Songies Plan 8 is implemented on branch `plan-8-lyrics` (Tasks 1–9 done and reviewed; final review done and its fixes reviewed). Next: the device checks, then write Plan 9 (listening statistics). Read docs/PROGRESS.md. Don't merge.

## Where things are
- **Plan 8, synced lyrics:** branch `plan-8-lyrics`, made from `plan-7-youtube-login`.
  - Spec: [Lyrics design](superpowers/specs/2026-10-29-songies-lyrics-design.md). Plan: [Plan 8](superpowers/plans/2026-10-29-songies-plan-8-lyrics.md).
  - Tasks 1–9 are done and each was reviewed.
  - 1,636 tests pass and `flutter analyze` is clean. The APK and Linux release builds succeed (sizes in PROGRESS.md).
- **What it does:** a Lyrics tab on Now Playing (phone), a right-side lyrics panel on desktop (toggled from the player bar), and a Lyrics tab in the desktop Now Playing dialog. Lookup order: the song's own `.lrc` file, then LRCLIB, then YouTube Music (YouTube songs only). Timed lyrics beat plain ones. Results are cached on the device (new `lyrics` table, schema 6) and shown offline. Lookups happen only while a Lyrics view is open.
- **Ledger:** `.superpowers/sdd/2026-10-29-songies-plan-8-lyrics/progress.md` (git-ignored). It holds the conflict scan, all rulings and every deferred minor.

## Not verified live (manual checks pending)
- The "Plan 8: lyrics" section of `docs/manual-test-checklist.md` has not been run on a phone, Linux or Windows.
- The Task 1 probe saw the real LRCLIB and YouTube Music answers, but the app itself has not been run against them end to end.
- The live sign-in check from Plan 7 is still pending too.

## Decisions made on your behalf (cost if wrong)
- **R1:** YouTube Music lyrics are plain text only. Timed ones need a different client and gave no timing signed out. *If wrong:* YouTube songs that LRCLIB lacks show plain lyrics, not timed.
- **R2:** an LRCLIB timed answer with fewer than 2 timed lines is ignored (the probe saw a one-line junk stub for a mainstream song). *If wrong:* a real one-line timed lyric is dropped.
- **R3:** in an LRCLIB search, an "instrumental" result is skipped if another in-range result has lyrics. *If wrong:* an instrumental track might show lyrics from another version of it (still matched within 2 s).
- **R4:** when your own plain file lyrics are shown, the best online result is still saved in the cache (never the file's text). *If wrong:* a saved online lyric you never see.
- **R5:** timed lyrics use a plain scrolling column, not a lazy list. Lyrics are a few hundred short lines at most, and measuring every line keeps the line placement exact after seeks. *If wrong:* slower layout on a very long lyric.
- **R6:** small dimmed lines meet the 4.5:1 contrast rule and large ones meet 3:1. *If wrong:* small dim lines look slightly less dim.
- **R7:** the desktop Now Playing dialog's Lyrics tab uses the smaller text size. *If wrong:* a one-word change.
- **R8:** the player bar volume slider is now flexible (up to 104 px) so the Lyrics button fits at the 720 px breakpoint. *If wrong:* a narrower volume slider on narrow windows.
- **R9:** when the device is online but every online source fails (LRCLIB down or rate limited), the view says "No lyrics found" with Search again, and nothing is cached. "Lyrics need a connection" is only for offline. *If wrong:* during an LRCLIB outage you see "No lyrics found" instead of a connection message.
- **R10:** on a desktop window narrower than 1000 px, the open lyrics panel holds the sidebar collapsed (your own choice comes back when the panel closes or the window widens). If the main pane would still be narrower than 360 px, the panel lies over the right side of the content instead of taking width. *If wrong:* on narrow windows and Android tablets the sidebar shrinks to icons, or the panel covers part of the page.
- **R11:** when every online source fails, Songies checks the connection again: offline shows "Lyrics need a connection" (and retries when you're back online), online shows "No lyrics found" with Search again. *If wrong:* one extra connection check per failed lookup.
- **R12:** the dimmed lyric lines use one brightness everywhere, picked so they stay readable on the hardest background (the blurred cover). *If wrong:* the desktop panel's dimmed lines are a little brighter than they need to be.
- **P1:** the YouTube lyrics source lives in `lib/lyrics/ytm_lyrics.dart`, so the YouTube code doesn't depend on lyrics types. *If wrong:* a file move.
- **P2:** "Search again" bumps a retry counter, and the next lookup skips the cache. *If wrong:* a small rework of one provider.
- **P3:** precedence is: timed from any source (your file first), then your file's plain lyrics, then online plain lyrics. A cached result is reused only if your file has no timed answer. *If wrong:* a plain online lyric shows instead of your own plain file, or the other way round.

## Worth your attention
- **Network:** the app now contacts lrclib.net (with the user agent `Songies/1.0.0`) and music.youtube.com, but only while a Lyrics view is open. Nothing is fetched in the background.
- **Secret scan:** the only hits for the cookie names in this branch's history are text in docs and the scrub test's list of forbidden words. No real values.
- **Test data:** the lyric fixtures hold invented lines only ("First invented line", and so on). The repo is public.
- **Windows:** the Windows build is made on your PC. The panel and player bar layout need a look there.
- **Small things left open:** the deferred minors are in the ledger (for example, no re-anchor of the current line on resize or rotate).
