# Songies: listening statistics — design

**Status:** agreed in conversation · 2026-10-29
**Becomes:** Plan 9, branch `plan-9-stats` (made from `plan-8-lyrics`). Device sync and packaging follow.
**Builds on:** the main design (`2026-10-21-songies-design.md`), the YouTube Music design (Plan 5's play rule, `kPlayThreshold`) and Plans 1–8.

## Why

The user wants to see how they listen: how much, and to whom and what, over a period they choose. Today Songies remembers only the last 200 songs that started (for Home's "Recently played"). It has no listening time, so nothing older can be rebuilt. **Stats start counting when this ships.**

**Success:** the user opens the Home card or the stats page and sees, for 7 days, 1 month, 6 months or 12 months, their minutes listened, a chart of when, and their top artists and songs. The numbers match what they actually heard.

## What the user decided

- **Periods:** 7 days, 1 month, 6 months, 12 months, chosen at the top of the page.
- **Total minutes listened** for the period.
- **Top artists by plays, not minutes:** an artist played 40 times beats one played 10 times. This means plays, not the number of different songs.
- **The main artist only:** featured artists are dropped (see "Main artist").
- **Top 5, expandable to top 10**, for both artists and songs.
- **Top songs by plays.**
- **A chart of listening over the period.**
- **A card on Home** leads to the stats.

## Goals

1. Record real listening, on every platform, from every song source: local files, downloaded YouTube songs and streamed YouTube songs.
2. A stats page with the period picker, total minutes, a chart, top artists and top songs.
3. A Home card summarising the last 7 days, which opens the stats page.

## Non-goals

- Rebuilding stats from before this ships.
- Sharing, exporting or a year-end "Wrapped" story.
- Stats per playlist, album or genre, or listening streaks.
- Sending stats anywhere. They never leave the device. Device sync, a later plan, will carry them between the user's own devices.

## Anti-goals (what would make this a failure even if it works)

- **Numbers that don't match reality.** Paused, buffering or errored time counted as listening, a skipped song counted as a play, or a song counted twice.
- **A slow page or a slow Home.** The page and the card must appear at once, even with a year of history.
- **Idle work.** Recording happens only as a side effect of playback. There are no timers while nothing plays and no background jobs.
- **A cluttered Home.** The card is one compact card. It never pushes playlists or "Recently played" out of view on a phone.

## What counts

- **A listen** is one stretch of one song in the queue: from when the player starts it until it ends, is skipped, is replaced, or the app stops.
  - **Pausing doesn't end a listen** (my call): pause and resume keep adding to the same listen.
  - **Seeking never starts a new listen,** not even a seek back to 0:00.
  - **A new listen begins each time the player starts a song:** the next song, "previous", a repeat-one restart after the song finished, or tapping the same song again.
- **Heard time** is the time the song was actually playing (`playing` true and not buffering). Paused time, buffering, seeking jumps and failed starts add nothing. A seek counts only the time actually played, not the distance jumped.
- **A play** is a listen whose heard time reaches the existing rule: `kPlayThreshold` (30 s), or the whole length when the song is shorter (`play_rules.dart`). That's the same rule Plan 5 uses for YouTube's history.
- **Minutes** are the heard time of **all** listens, including ones too short to be a play.
- A listen with zero heard time is not recorded.
- **Saving a listen:**
  - each listen is saved when it ends;
  - while it runs, its progress is also saved about every 30 s of heard time (my call), so a crash or force-quit loses at most that much;
  - a listen whose final save was missed keeps its last saved progress.

## Main artist

A song is credited to its **main artist** only. The rule is applied when the listen is recorded and kept with it, so later edits don't rewrite history:

- **YouTube songs** (`source 'yt'`): the stored artist line is YouTube's artist names joined by ", ". The main artist is everything before the first ", ". YouTube treats a band name such as "Simon & Garfunkel" as one artist, so this is safe.
- **Local files:** the artist tag is cut at the first of these separators (case-insensitive): `, `, `;`, ` / `, ` feat. `, ` feat `, ` ft. `, ` ft `, ` featuring `, plus the same forms inside brackets, such as `(feat. …)`. It is never cut at `&`, `+` or ` x `, so band names stay whole (my call; the cost is that a file duet tagged "A & B" counts as one name).
- **Comparing names:** trimmed and compared ignoring case, so "daft punk" and "Daft Punk" are one artist. The name shown is the one most recently recorded.
- **Empty or unknown artist:** the song still counts toward minutes and top songs, but is left out of top artists.

## The stats page

From top to bottom:

1. **Period picker:** 7 days · 1 month · 6 months · 12 months. The default is 7 days, and the choice is remembered for the session.
   - "7 days" means the last 7 calendar days including today, in local time. 1 month is 30 days, 6 months is 182 days and 12 months is 365 days, counted the same way (my call: fixed lengths keep comparisons fair).
2. **Total minutes** for the period, large. Under it, a quiet comparison with the period just before, such as "+12% vs the previous 7 days". It is hidden when the previous period has nothing.
3. **Chart:** a bar chart of minutes over the period.
   - Each bar is one day for 7 days (7 bars) and 1 month (30 bars).
   - For 6 months each bar is a rolling 7-day block ending today (26 bars).
   - For 12 months each bar is a calendar month; the oldest bar is partial and covers only the days inside the period (my call).
   - Hovering (desktop) or tapping (phone) a bar shows its date range and minutes.
   - Empty bars are drawn as a faint baseline.
   - The bars use the theme's accent and meet the AA rules for non-text contrast.
4. **Top artists**, ranked by plays. Ties are broken by minutes, then by name.
   - Each row shows the rank, the name, and "N plays". Its picture is the cover of that artist's most-played song in the period.
   - The top 5 show, and **Show top 10** expands the list.
   - Tapping an artist goes to their YouTube Music artist page when Songies knows it (the same rule as the song menu's "Go to artist"). Otherwise it does nothing (my call).
   - The artist page is found at tap time from that artist's most-played song that is still in the library. No artist id is stored with listens.
5. **Top songs**, ranked by plays, with ties broken by minutes.
   - Each row shows the rank, cover, title, main artist and "N plays". The top 5 show, and **Show top 10** expands the list.
   - Tapping plays the song, and long-press, right-click or ⋯ opens the usual song menu (Plan 6).
   - A song since removed from the library still shows its last recorded title and artist, and its menu offers only what still applies.
6. **Empty period:** "Nothing played in this period yet", with no chart or lists.

**Placement:** on the phone it's a full page pushed from Home. On desktop it's a page in the main pane, reached from the Home card; there's no new sidebar entry (my call).

## The Home card

- Titled **Your listening**. It shows the last 7 days' minutes and a tiny 7-bar chart, plus "Most played: <artist> · N plays" when there is a top artist.
- Tapping it opens the stats page on 7 days.
- With no listening yet: "Your listening stats will show up here", in the same compact size.
- **Where it goes:** below the quick tiles and above "Your playlists" (my call). It is one card wide on the phone, and the same compact card on desktop.

## Data

- **Where listens are stored:** in a new `listens` table, one row per listen, with:
  - the track id;
  - when the listen started;
  - heard milliseconds;
  - whether it counts as a play;
  - the main artist (display name);
  - a title snapshot, artist snapshot and a cover reference, so removed songs still show.
- **Syncing:** the table carries the usual sync columns, so device sync can later merge listens from several devices; listens are only ever added. Until then it is device-local in practice.
- **Same song:** a song is identified by its track id. A streamed YouTube song and its later download are the same track row, so they count as one.
- **Cover:** the cover reference is the track's art-cache ref at the time of the listen. If that image is gone, the usual placeholder shows.
- **Times:** `started_at` is stored in UTC. Days, weeks and months are worked out in local time when the stats are shown, and a listen counts wholly on the day it started (my call).
- **Writes:**
  - a listen's row is written when it starts having heard time, then updated in place at each checkpoint and at the end;
  - every write is stamped, like other synced rows (my call);
  - "only ever added" means the user never edits or deletes listens; pruning is a device-local cleanup.
- **Pruning:** rows older than 730 days are deleted when the app starts. This is one cheap indexed delete (my call; it keeps 12 months plus the previous 12 months for the comparison).
- **Unchanged:** the existing `play_history` (the last 200 starts, for "Recently played") stays as it is.
- **Speed:** stats are computed by indexed queries on `started_at`, so a year of listens (tens of thousands of rows) still answers at once. Pre-computed summaries are not needed at this size; the builder adds one only if a test with a year of data shows the page is slow.

## Constraints

- **Stack:** Flutter and Dart only. A charting package needs a reason; a small custom painter is the default.
- **Rules from earlier plans still hold:**
  - no idle work;
  - every synced write is stamped;
  - Motion tokens, reduced motion, nothing animating while playback is paused, AA contrast;
  - tests never touch the network or real home directories.
- **Platforms:** Android (minSdk 24), Windows and Linux ship together.
- **Privacy:** stats never leave the device in this plan.

## Left to the builder

- Exact chart styling, row layout and the card's look, within the theme.
- How recording hooks into `PlayerService`: its state stream, or a small listener owned by `main.dart`, as `PlayReporter` does.
- Whether to store `heard_ms` updates in place (one row per listen, updated while it runs) or to write once at the end with a crash-safe checkpoint. The behaviour above is the requirement.
