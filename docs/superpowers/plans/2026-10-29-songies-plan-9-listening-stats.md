# Songies Plan 9: Listening Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record real listening, then show it as a stats page (7 days, 1 month, 6 months and 12 months: total minutes, a chart, top artists and top songs) and a "Your listening" card on Home.

**Architecture:**
- **Recording:** a `ListenRecorder` listens to `PlayerService` (its state stream plus a new `trackStarts` stream). It uses a heard-time counter shared with `PlayReporter`, and writes one stamped row per listen into a new synced `listens` table, with a checkpoint about every 30 s of heard time.
- **Reading:** a `StatsRepository` answers each period with indexed SQL on `started_at`. Bucketing into days, weeks and months happens in Dart, in local time.
- **UI:** the stats page and the Home card are plain widgets over Riverpod providers; the chart is a small custom painter.

**Tech Stack:** Flutter 3.47.8 (`~/development/flutter/bin`, not on PATH), Dart 3.13, Riverpod 3, drift, go_router.

**Spec:** `docs/superpowers/specs/2026-10-29-songies-listening-stats-design.md`. Read it before any task. Where this plan and the spec disagree, the spec wins.

## Global Constraints

- **Counting rules:**
  - a **play** uses `reachedPlay(heard, length)` from `lib/player/play_rules.dart` (`kPlayThreshold` = 30 s, or the whole song when shorter);
  - **minutes** count all heard time;
  - a listen with zero heard time is never written.
- **When a listen starts and stops:**
  - pausing never ends a listen, and seeking never starts one;
  - a new listen begins only on a player start (next, previous, a repeat-one restart, or a new queue).
- **The `listens` table:**
  - it uses `SyncColumns`, and every write (insert and each update) is stamped with `SyncStamp.next()`;
  - `started_at` is stored in UTC;
  - the schema goes from 6 to 7;
  - rows older than **730 days** are pruned (ruling S3) at app start.
- **Periods:** the last 7 / 30 / 182 / 365 calendar days including today, in local time. The comparison period is the same length immediately before.
- **Main artist:**
  - for YouTube songs (`source == 'yt'`), the text before the first `", "`;
  - for local songs, the text before the first `, `, `;`, ` / `, ` feat. `, ` feat `, ` ft. `, ` ft `, ` featuring ` (case-insensitive, including bracketed forms such as `(feat. …)`);
  - never split on `&`, `+` or ` x `;
  - names are trimmed and grouped case-insensitively;
  - an empty main artist is left out of top artists.
- **Rankings:** by plays, ties broken by minutes, then by name. Top 5 shown, expandable to 10.
- **No idle work:** recording happens only as a result of player events, with no timers while nothing plays and no background jobs. Pruning is one delete at start-up.
- **Earlier rules still hold:**
  - Motion tokens (`Motion.of(context)`), zero under reduced motion, nothing animating while playback is paused;
  - AA contrast via `SongiesColors`;
  - tests never touch the network or real home directories.
- **Commits** end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01PjntrucDy7bCG4aSheCsV1`
- **Checks before each commit:** `flutter analyze` is clean and `flutter test` passes. Use `dart format` on touched files only.

## Review Focus

1. **Pause, buffering and seeks inflating minutes.** A paused or buffering song adds nothing, and a seek forward or back adds nothing. Test in Task 2 with scripted player states.
2. **Repeat-one and "previous" restart.** Each restart starts a new listen, and the old one is closed with only its heard time. Test in Task 2 with `trackStarts` events.
3. **Midnight and DST.** A listen counts on the local day it started, and bucket boundaries follow local midnight across a DST change. Test in Task 3 with a fixed timezone offset change (inject a `toLocal` function).
4. **A year of data stays fast.** Seed about 40,000 listens across 365 days. The 12-month stats query completes within a generous bound in tests (under 500 ms on the test DB). Test in Task 3.
5. **A crash mid-song.** A listen whose final save never happened keeps its last checkpoint, and the next app run doesn't double-count it. Test in Task 2: checkpoint, then simulate disposal without finishing; the row holds the checkpoint value.

---

### Task 1: Listens table, store, main-artist rule, pruning

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart` (schema 7, plus an index on `started_at`), then regenerate `lib/data/database.g.dart`
- Create: `lib/stats/main_artist.dart`, `lib/stats/listen_store.dart`
- Modify: `lib/main.dart` (call `prune` once at start-up, unawaited and logged)
- Test: `test/stats/main_artist_test.dart`, `test/stats/listen_store_test.dart`, and a v6 to v7 case in `test/data/migration_test.dart`

**Interfaces:**
- Produces:
  - `@DataClassName('ListenRow') class Listens extends Table with SyncColumns`, with:
    - `TextColumn trackId`;
    - `DateTimeColumn startedAt` (UTC);
    - `IntColumn heardMs`;
    - `BoolColumn counted` (whether it is a play);
    - `TextColumn mainArtist`;
    - `TextColumn titleSnapshot`;
    - `TextColumn artistSnapshot`;
    - `TextColumn artworkRef` (nullable).
  - An index `listens_started_at` on `started_at`.
  - `String mainArtist(String artist, {required bool youtube})`
  - `class ListenStore { ListenStore(AppDatabase db, SyncStamp stamp, {DateTime Function() now = DateTime.now}); Future<String?> start(Track t, DateTime startedAtUtc, Duration heard, bool counted); Future<void> update(String id, Duration heard, bool counted); Future<void> prune(); }`
    - `start` inserts a stamped row with the snapshots taken from `t` (`mainArtist(t.artist, youtube: t.source == 'yt')`, `t.title`, `t.artist`, `t.artworkRef`) and returns its id.
    - `update` re-stamps the row.
    - `prune` deletes rows whose `started_at` is more than 730 days before `now()`.
    - All three log failures with `AppLog.w` and never throw; `start` returns null on failure.

- [ ] **Step 1: Write the failing tests:**
  - `mainArtist`:
    - `('Daft Punk, Pharrell Williams', youtube: true)` gives `'Daft Punk'`;
    - `('Simon & Garfunkel', youtube: true)` gives `'Simon & Garfunkel'`;
    - local `'Daft Punk feat. Pharrell'` gives `'Daft Punk'`;
    - `'A ft B'` gives `'A'`;
    - `'A FEATURING B'` gives `'A'`;
    - `'A (feat. B)'` gives `'A'`;
    - `'A; B'` gives `'A'`;
    - `'A / B'` gives `'A'`;
    - `'Florence + the Machine'` and `'A & B'` are unchanged;
    - `'Earth, Wind & Fire'` gives `'Earth'` (documented trade-off; the test pins it);
    - `'  '` gives `''`.
  - `ListenStore`:
    - `start` writes one stamped row with the snapshots;
    - `update` changes `heardMs` and `counted` with a newer clock;
    - `prune` keeps a 729-day-old row and deletes a 731-day-old one;
    - `start` against a closed DB returns null without throwing.
  - Migration: a v6 database opens at v7 with an empty `listens` table and the index present.
- [ ] **Step 2: Run** `flutter test test/stats test/data/migration_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, regenerate with `dart run build_runner build --delete-conflicting-outputs`, and add the existing migration tests' `user_version` bump to 7.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: listens table, store and main-artist rule`.

### Task 2: ListenRecorder (and a shared heard-time counter)

**Files:**
- Create: `lib/player/heard_time.dart`, `lib/stats/listen_recorder.dart`
- Modify:
  - `lib/innertube/play_reporter.dart`: use `HeardTime`, with behaviour unchanged;
  - `lib/player/player_service.dart`: add `trackStarts`;
  - `lib/main.dart`: create the recorder next to `PlayReporter`.
- Test: `test/player/heard_time_test.dart`, `test/stats/listen_recorder_test.dart`. The existing `test/innertube/play_reporter_test.dart` must still pass unchanged.

**Interfaces:**
- Consumes: `ListenStore` (Task 1) and `reachedPlay`.
- Produces:
  - `class HeardTime { void reset(); Duration get heard; void onState({required bool playing, required Duration position}); }`. This is the existing PlayReporter rule moved out:
    - a position step counts only while playing (or on the step into a stopping state), and only if it is greater than 0 and at most 5 s;
    - the first tick is credited when it is within 2 s of the start.
  - `Stream<Track> PlayerService.trackStarts`, a broadcast stream. It emits on every successful start: wherever `_reportStarted` runs, including the repeat-one restart in `_handleCompleted`, and in `_restartCurrent` (the "previous" restart).
  - `class ListenRecorder { ListenRecorder(Stream<PlayerState> states, Stream<Track> starts, ListenStore store); void dispose(); }`
    - On each `starts` event it finishes the open listen (a final `update` if a row exists) and opens a new one for that track.
    - States feed `HeardTime`; `buffering` counts as not playing.
    - On the first non-zero heard time it calls `store.start`.
    - After each further 30 s of heard time it calls `store.update` (the checkpoint).
    - When the current track becomes null, or on `dispose`, it closes the open listen with a final `update`.
    - `counted` is `reachedPlay(heard, length)`, with the length taken from the state's `duration`, else the track's `durationMs`.

- [ ] **Step 1: Write the failing tests**, scripting `PlayerState`s and start events:
  - `HeardTime` gets the same cases PlayReporter's tests pin (steps, seeks over 5 s, paused ticks, start credit).
  - **Review Focus 1:**
    - 20 s playing, a 60 s pause, then 15 s playing gives one listen of 35 s, counted;
    - a seek from 10 s to 3:00 adds nothing;
    - buffering ticks add nothing.
  - **Review Focus 2:**
    - repeat-one: 2:00 heard, then a start event for the same track, then 10 s heard gives two rows (120 s counted, 10 s not counted);
    - "previous" restart after 1:00 gives two rows.
  - **Zero heard:** a start followed by an immediate skip writes no row.
  - **Review Focus 5 (crash):** 75 s heard then dispose without a final state gives a row of at least 60 s (the last checkpoint is at 60 s; dispose writes 75 s). A second test: 75 s heard where the store's final update throws still leaves the row at the 60 s checkpoint.
  - **Checkpoints:** about 30 s apart. Heard 95 s gives `update` calls at about 30, 60 and 90 s, then a final one.
  - **`trackStarts`:** emits on `playQueue`, `next`, a repeat-one completion and a `previous` restart, and does not emit on `seek`, `pause` or `play`. Add this to `test/player/player_service_test.dart` with the fake backend.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement.** Move PlayReporter's counting into `HeardTime` with no behaviour change, then wire `ListenRecorder(player.states, player.trackStarts, listenStore)` in `main.dart`.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS, including the unchanged `play_reporter_test.dart`.
- [ ] **Step 5: Commit** `feat: record listens from playback`.

### Task 3: StatsRepository and providers

**Files:**
- Create: `lib/stats/stats_repository.dart`, `lib/stats/stats_models.dart`
- Modify: `lib/providers.dart`, `lib/main.dart`
- Test: `test/stats/stats_repository_test.dart`

**Interfaces:**
- Consumes: the `listens` table (Task 1).
- Produces:
  - `enum StatsPeriod { week, month, halfYear, year }`, with day counts 7, 30, 182 and 365, and labels '7 days', '1 month', '6 months' and '12 months'.
  - `class StatsBucket { final DateTime start; final DateTime end; final Duration heard; }`, with local start and end (end exclusive).
  - `class ArtistStat { final String name; final int plays; final Duration heard; final String? artworkRef; final String? sampleTrackId; }`
    - `name` is the most recently recorded spelling;
    - `artworkRef` is from the artist's most-played song in the period;
    - `sampleTrackId` is that song's id.
  - `class SongStat { final String trackId; final String title; final String artist; final String? artworkRef; final int plays; final Duration heard; }`, using the latest snapshots.
  - `class PeriodStats { final StatsPeriod period; final Duration total; final Duration? previousTotal; final List<StatsBucket> buckets; final List<ArtistStat> topArtists; final List<SongStat> topSongs; bool get isEmpty; }`
    - `previousTotal` is null when the previous period has nothing;
    - the top lists hold at most 10 entries.
  - `class StatsRepository { StatsRepository(AppDatabase db, {DateTime Function() now = DateTime.now, DateTime Function(DateTime utc)? toLocal}); Future<PeriodStats> period(StatsPeriod p); Stream<PeriodStats> watch(StatsPeriod p); }`. `watch` re-emits when `listens` changes, throttled to at most once per 5 s (the recorder checkpoints often).
  - Providers:
    - `statsRepositoryProvider` (`_unwired` like its neighbours);
    - `periodStatsProvider = StreamProvider.autoDispose.family<PeriodStats, StatsPeriod>`;
    - `statsPeriodProvider`, a session-only `Notifier<StatsPeriod>` starting at `week`.
- **Algorithm:**
  - Fetch the rows with `started_at >= (local start of the first day of the previous period, converted to UTC)` in one indexed query, then aggregate in Dart.
  - **Buckets:**
    - week: 7 daily buckets;
    - month: 30 daily buckets;
    - halfYear: 26 rolling 7-day blocks ending today;
    - year: calendar months from the period start, the oldest one partial (it starts at the period start).
  - Each listen goes wholly into the bucket containing its local `started_at`.

- [ ] **Step 1: Write the failing tests**, with injected `now`, `toLocal` and a test DB seeded through `ListenStore` or raw inserts:
  - totals and `previousTotal`, including null when the previous period is empty;
  - the bucket counts are 7, 30, 26 and 12 or 13, with the expected boundaries;
  - the year's oldest bucket starts exactly at the period start;
  - top artists:
    - ranked by plays, with ties broken by minutes then name;
    - uncounted listens add minutes but not plays;
    - `'daft punk'` and `'Daft Punk'` merge, showing the latest spelling;
    - an empty main artist is excluded;
    - the artwork comes from the most-played song;
  - top songs are ranked the same way and use the latest snapshot;
  - a period with no listens has `isEmpty` true;
  - **Review Focus 3:**
    - a listen at 23:59 local counts on that day even when it ran past midnight;
    - with a `toLocal` that shifts by +1 h partway through the period (DST), each listen lands on its local day;
  - **Review Focus 4:** 40,000 rows over 365 days; `period(year)` completes in under 500 ms (measured with `Stopwatch`; a generous bound);
  - `watch` emits again after a new listen and coalesces bursts.
- [ ] **Step 2: Run** `flutter test test/stats/stats_repository_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, and wire `StatsRepository(db)` in `main.dart`.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: listening stats queries and providers`.

### Task 4: The stats page

**Files:**
- Create: `lib/ui/stats/stats_page.dart`, `lib/ui/stats/stats_chart.dart`
- Modify: `lib/router.dart` (route `/home/stats` inside the Home branch, so the shell and player stay visible on both phone and desktop)
- Test: `test/ui/stats_page_test.dart`, `test/ui/stats_chart_test.dart`

**Interfaces:**
- Consumes: `periodStatsProvider`, `statsPeriodProvider`, `showSongMenu`/`SongMenuButton` and `MenuSong.track` (Plan 6), `playerServiceProvider.playQueue`, and `context.goYtmArtist` for the artist tap.
- Produces:
  - `class StatsPage extends ConsumerWidget`
  - `class StatsChart extends StatelessWidget { const StatsChart({required this.buckets, this.compact = false, super.key}); }`
  - `String formatMinutes(Duration d)`: for example `'1,234 min'` for at least 1 minute, and `'0 min'` otherwise.
  - Keys: `stats.period.<name>`, `stats.total`, `stats.change`, `stats.chart`, `stats.artists.more`, `stats.songs.more`, `stats.empty`.

**Behaviour** (the spec's "The stats page" section gives the copy and layout):
- The period picker is a segmented row of four choices.
- The total is shown large. The change line reads `'+12% vs the previous 7 days'`, or `'−8% vs …'` with a true minus sign; it is hidden when `previousTotal` is null.
- **Chart:**
  - one bar per bucket, with height proportional to its share of the largest bucket;
  - empty buckets show a 2 px faint baseline;
  - bar colour `colors.accent`, which must meet 3:1 against the page background (non-text AA);
  - hovering (desktop) or tapping (phone) a bar shows a tooltip with the date range and minutes;
  - no animation while paused or under reduced motion.
- **Top artists:**
  - rows show the rank, a cover of `artworkRef` (the existing `Artwork` widget, seeded by name), the name and "N plays";
  - 5 show, and **Show top 10** expands the list;
  - tapping an artist resolves `sampleTrackId` through the library and the same rule the song menu uses for Go to artist; when no artist page is known, the tap does nothing.
- **Top songs:**
  - rows show the rank, cover, title, artist, "N plays" and a `SongMenuButton`;
  - tapping plays the song (`playQueue([track])`, looked up by id);
  - a song no longer in the library shows its snapshot, its tap does nothing, and its menu is omitted.
- **Empty:** "Nothing played in this period yet" (`stats.empty`), with no chart or lists.

- [ ] **Step 1: Write the failing widget tests**, using `test/helpers/ui_harness.dart` with `statsRepositoryProvider` overridden by a fake that returns scripted `PeriodStats`:
  - the picker switches periods and the provider is called with each;
  - the total and change text are right, including a negative change and the hidden case;
  - the chart draws N bars (a test hook exposing the bar rects, or a `CustomPaint` size/semantics check);
  - tapping a bar shows a tooltip with its minutes;
  - top 5, then Show top 10 gives 10;
  - tapping a song calls `playQueue` with that track;
  - a removed song has no menu and its tap does nothing;
  - an artist with a known YouTube id navigates, and one without does nothing;
  - the empty state shows the message only;
  - at 400×800 and 1280×800 nothing overflows;
  - reduced motion leaves no running animations.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: listening stats page`.

### Task 5: The Home card

**Files:**
- Create: `lib/ui/stats/listening_card.dart`
- Modify: `lib/ui/home/home_page.dart` (put the card below the quick tiles and above "Your playlists"; when there are no playlists, put it after `_EmptyHome`)
- Test: `test/ui/listening_card_test.dart`, and a Home placement test in the existing Home tests

**Interfaces:**
- Consumes: `periodStatsProvider(StatsPeriod.week)`, `StatsChart(compact: true)` and the `/home/stats` route.
- Produces: `class ListeningCard extends ConsumerWidget`, with keys `home.listening`, `home.listening.minutes` and `home.listening.top`.

**Behaviour:**
- The title is **Your listening**.
- The card shows the week's minutes and a compact 7-bar chart. When there is a top artist it adds "Most played: <name> · N plays".
- With no listens it shows "Your listening stats will show up here" at the same height.
- Tapping it sets `statsPeriodProvider` to `week` and pushes `/home/stats`.
- On a phone the card is no taller than about 120 px, so the playlists stay in view.

- [ ] **Step 1: Write the failing tests:**
  - the content and empty texts;
  - the top line is hidden without a top artist;
  - a tap navigates to the stats page on week;
  - on Home at 400×800 the card sits between the tiles and "Your playlists", and "Your playlists" is still visible in the first viewport when there are 4 or more playlists;
  - no overflow at 400×800 and 1280×800.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Your listening card on Home`.

### Task 6: Docs, checklist, builds

**Files:**
- Modify: `docs/PROGRESS.md`, `docs/manual-test-checklist.md`
- Create: `docs/plan-9-session-log.md`

- [ ] **Step 1: Add a "Plan 9: listening stats" section** to the manual checklist, with one check for each of these, covering the phone, Linux and Windows:
  - play a song for 1 minute, then check the card's minutes and plays;
  - pause for a minute and check the minutes don't grow;
  - skip after 10 s: the minutes grow but there's no play;
  - repeat-one twice gives 2 plays;
  - each period switches and the chart bars look right;
  - Show top 10 works;
  - tapping a top song plays it;
  - tapping an artist goes to their page when known;
  - a featured-artist song counts for the main artist;
  - force-quit mid-song: at most about 30 s is lost;
  - the card is compact on the phone, and the playlists stay visible.
- [ ] **Step 2: Update PROGRESS.md** (the Plan 9 status, rulings, and the next step: device sync and packaging) and write the session log in the Plan 8 log's style.
- [ ] **Step 3: Verify:**
  - run `flutter analyze`, `flutter test`, `flutter build apk --release` and `flutter build linux --release`; expected: all succeed, and note the APK size;
  - run `git log -p <base>..HEAD | grep -nE "SAPISID|__Secure-|LOGIN_INFO"`; expected: no real values.
- [ ] **Step 4: Commit** `docs: Plan 9 verification, checklist and progress`.
