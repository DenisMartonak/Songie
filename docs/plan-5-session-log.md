# Songies Plan 5: session log

_Last updated: 2026-10-27. **Plan 5 is finished.** All 11 tasks are done and reviewed, the final whole-branch review ran, its one fix wave landed, and the branch `plan-5-youtube-music` is pushed. Nothing is merged._

**To resume (next plan):**
> Songies Plan 5 is done on branch `plan-5-youtube-music`. Next: the Plan 5 device checks in docs/manual-test-checklist.md, then write Plan 6 (synced lyrics). Read docs/PROGRESS.md. Don't merge.

## Where things are
- **Plan:** [Plan 5](superpowers/plans/2026-10-25-songies-plan-5-youtube-music.md). Spec: [YouTube Music design](superpowers/specs/2026-10-25-songies-youtube-music-design.md). Status, rulings and parked items: [PROGRESS.md](PROGRESS.md).
- **Verified at the pushed head:**
  - `flutter test` passes 1,278 tests and `flutter analyze` is clean.
  - The release APK (80.2 MB) and the Linux release bundle (34 MB) both build. The Linux bundle launched with no errors; the runtime libmpv is enough.
  - A scan of every file in all 139 commits found no visitor-shaped tokens.
- **Live check (2026-10-27):**
  - Innertube resolves a stream in about 0.1 s; yt-dlp takes about 2 s.
  - Search and radio continuations, and artist radio, all work.
  - No consent request appeared. Details are in [innertube-notes.md](innertube-notes.md).
- **Flutter:** 3.47.8 is at `~/development/flutter/bin`. Add it to your PATH.

## Tasks
| Task | Commits | Result |
|---|---|---|
| 1 Innertube client core | `8887028` | Clean. The branch was rewritten to remove a leaked visitor token. |
| 2 Instant streams + Wi-Fi split | `a52482e`, `57eabd9` | Clean after 1 fix round |
| 3 Search + radio parsers | `b10497d`, `0a9cfbe` | Clean after 1 fix round |
| 4 Home / artist / album / playlist browse | `84cb422` | Clean |
| 5 Track rows, library-only lists | `967cc49`, `92795c9` | Clean after 1 fix round |
| 6 Play reports | `e53b479`, `bc105a7` | Clean after 1 fix round |
| 7 Queue commands + radio | `a0bbd43` | Clean |
| 8 Search page | `c747e4c`, `59cc964` | Clean after 1 fix round |
| 9 Home feed, consent, reset | `49e861b` | Clean |
| 10 Artist / album / playlist pages | `48f20a2`, `ab3f3b2` | Clean after 1 fix round |
| 11 Timing tool, docs, checklist, builds | `5652d84`, `06d663e` | Clean |
| Final review fix wave | `bc21e83` | Clean |

## Decisions made on your behalf (cost if wrong)
- **R1:** commits carry the Co-Authored-By and Claude-Session trailers. *If wrong:* one extra line per commit.
- **R2 (superseded by R12):** a song counts as unavailable only when every Innertube client says so at the video level.
- **R2b:** the first play ever fetches a visitor id with one request. *If wrong:* one request.
- **R3:** the missing search-tab and UNPLAYABLE fixtures were hand-built from real recorded rows. The live checks in Task 11 then confirmed the tab paths. *If wrong:* little.
- **R4:** play reports add `ver=2&cpn=…` (plus `st/et/cmt` on watchtime). *If wrong:* YouTube ignores the reports and the feed gets less personal.
- **R5:** after Accept, every Innertube request sends `Cookie: SOCS=CAI`. *If wrong:* nothing.
- **R6:** continuations are sent as query params, with the token also in the body. Verified live in Task 11.
- **R7:** only YouTube songs are hidden from library lists when they're in no playlist. Local files always show. *If wrong:* local files outside playlists still show.
- **R8:** an imported song with no album counts as "channel-name metadata" and takes YouTube Music's artist. *If wrong:* a hand-corrected artist on an album-less song gets overwritten once.
- **R9:** consent "Not now" lasts for the session; Accept is permanent. *If wrong:* an EU user who declines sees the sheet once per launch.
- **R10:** real-network timing used a dev-only CLI tool (`tool/stream_timing.dart`) instead of timing the release app. *If wrong:* the timing leaves out player start-up.
- **R11:** commits from the resumed session name that session in their Claude-Session trailer. *If wrong:* the trailers differ between commits.
- **R12:** yt-dlp must confirm a song is unavailable before it is marked unavailable. This overrides the plan's Review Focus 4, because the spec's rule that "a failing Innertube route never errors" takes priority. *If wrong:* about 2 s once per truly removed song.
- The fixtures also scrub the `fexp` and `initcwndbps` stream parameters. *If wrong:* those two values are placeholders.

## Worth your attention
- **The leaked token on GitHub:** the old commit `c3fa2fe` may still be fetchable by its hash until GitHub cleans it up. Ask GitHub Support to purge it if that matters. Any other clone should `git fetch && git reset --hard origin/plan-5-youtube-music`.
- **Parked findings:** the final review judged that all the findings left from the per-task reviews can wait. The main ones are listed in PROGRESS.md:
  - the consent listener only runs on Home;
  - the YouTube Music pages have no pinned Back button;
  - Now Playing text stays stale after a metadata upgrade;
  - tapping a long YouTube Music playlist stores every row before playback starts (measure this on a device).
