# Songies Plan 9 (listening statistics): session log

_Last updated: 2026-10-29. **Plan 9 is implemented on branch `plan-9-stats`; Tasks 1–6 are done and reviewed. The final whole-branch review is done and its fixes were reviewed.** Nothing is pushed or merged._

**To resume (next plan):**
> Songies Plan 9 is implemented on branch `plan-9-stats` (Tasks 1–6 done and reviewed; final review fixed). Next: the device checks, then plan device sync. Read docs/PROGRESS.md. Don't merge.

## Where things are
- **Plan 9, listening statistics:** branch `plan-9-stats`, made from `plan-8-lyrics`.
  - Spec: [Listening stats design](superpowers/specs/2026-10-29-songies-listening-stats-design.md). Plan: [Plan 9](superpowers/plans/2026-10-29-songies-plan-9-listening-stats.md).
  - Tasks 1–6 are done and each was reviewed. The final review ran; its fixes (untagged files out of top artists, short-song plays with a 1 s end allowance, the main artist on top songs, a stale "400 days" comment) landed and were reviewed.
  - 1,756 tests pass and `flutter analyze` is clean. The APK and Linux release builds succeed (sizes in PROGRESS.md).
- **What it does:** every song you play is recorded as a listen (new `listens` table, schema 7, synced like the other tables). A "Your listening" card on Home shows the last 7 days. Tapping it opens a stats page with 7 days, 1 month, 6 months and 12 months, a bar chart, top artists and top songs. Recording happens only when the player does something: no timers, no background jobs. Old listens are pruned once, at app start.
- **Ledger:** `.superpowers/sdd/2026-10-29-songies-plan-9-listening-stats/progress.md` (git-ignored). It holds the conflict scan, all rulings and every deferred minor.

## Not verified live (manual checks pending)
- The "Plan 9: listening stats" section of `docs/manual-test-checklist.md` has not been run on a phone, Linux or Windows.
- Real playback was never run against the recorder. The tests use a fake player, so the 30 s checkpoint and the force-quit loss need a real song.
- The Plan 7 live sign-in check and the Plan 8 lyrics checks are still pending too.

## Decisions made on your behalf (cost if wrong)
- **S1:** a comma inside a real band name (for example "Earth, Wind & Fire") is split like a featured artist. Tracks only keep YouTube's comma-joined artist line. *If wrong:* such bands count under their first word. The fix needs YouTube's artist list stored with the track.
- **S2:** the last listen of a session is saved when playback stops and when it first counts as a play. Without it, a short final song's play was lost. *If wrong:* one extra write per pause.
- **S3:** listens are kept for 730 days, not the brief's 400. The 12-month view compares with the 12 months before it, which needs two years. The previous period is summed in SQL, with no row fetch. *If wrong:* about twice the table size (still small).
- **S4:** tapping a top artist opens Search with the artist's name. Tracks store no artist id, so the spec's "go to their page when known" never applies today. *If wrong:* tapping an artist opens a search instead of doing nothing (the design said nothing happens when their page isn't known).
- **S5:** a removed song's row has no menu. Nothing in the menu applies without a library track except radio and search. *If wrong:* one menu missing on removed songs.
- **S6:** year-view bar labels keep the year ("Oct 2026"), which tells two partial Octobers apart. *If wrong:* none.

## Worth your attention
- **Pruning:** it is 730 days, not 400 (S3). The brief said 400; the spec's own comparison needs more.
- **Artist names:** "Earth, Wind & Fire" and similar bands are split (S1). It is a known trade-off, pinned by a test.
- **Privacy:** listens stay on your device and in your own sync. Nothing new goes over the network.
- **Windows:** the Windows build is made on your PC. The card and stats page layouts need a look there.
- **Small things left open:** the deferred minors are in the ledger (for example, stats are worked out on the main thread, about 60 to 150 ms per refresh while the page is open and playing).
