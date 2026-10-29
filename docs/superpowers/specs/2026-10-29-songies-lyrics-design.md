# Songies: synced lyrics — design

**Status:** approved in conversation · 2026-10-29
**Becomes:** Plan 8, branch `plan-8-lyrics` (made from `plan-7-youtube-login`). Listening statistics are Plan 9; device sync and packaging follow.
**Builds on:** the main design (`2026-10-21-songies-design.md`, §10 Lyrics, which this document replaces), the YouTube Music design (`2026-10-25-songies-youtube-music-design.md`) and Plans 1–7. Read `docs/innertube-notes.md` for how Songies talks to YouTube.

## Why

The user wants lyrics for whatever is playing, at three kinds of moment, all of them ("a bit of everything"):

- **Singing along**, with Now Playing open, often on the phone at arm's length.
- **Glancing at them on desktop** while doing something else, in a panel left open next to the rest of the app.
- **Looking something up**: finding a line and jumping the song to it.

The main design's §10 was written before YouTube Music came into Songies. Most of what the user plays now streams from YouTube Music, so the sources are revised here.

**Success:** for most songs the user plays, opening Lyrics shows timed lyrics that follow the song. Where only plain text exists, it shows that. Where nothing exists, it says so quietly and costs nothing.

## Goals

1. **A Lyrics view on every platform:** a third choice on Now Playing on the phone, and a right-side panel on desktop.
2. **Timed lyrics that follow the song:** the current line is highlighted and kept in view, and tapping a line seeks to it.
3. **Plain lyrics when no timed ones exist.**
4. **Every lookup is made once:** results are kept, including "none", so a song never needs looking up twice.

## Non-goals

The user confirmed all of these can wait:

- translations and romanisation;
- word-by-word (karaoke) highlighting. Highlighting is line by line;
- editing or correcting lyrics in Songies;
- lyrics on the lock screen, in the media notification or in Windows' media overlay;
- a timing offset control for lyrics that drift.

## Anti-goals (what would make this a failure even if it works)

- **Idle work.** Lyrics are looked up only while the Lyrics view is open. There is no background fetching, polling or library-wide pre-fetch.
- **Lyrics for the wrong song.** A wrong version's lyrics are worse than none, hence the duration rule below.
- **Errors in the user's face.** A failed or empty lookup shows a calm message, never an error dialog or a red banner.
- **Motion that doesn't respect the user.** Reduced motion is honoured, and nothing animates while playback is paused (the Plan 4 rule).
- **Slowing down playback.** Lyrics work never delays starting, skipping or seeking.

## Where lyrics come from

The lookup goes through these sources in order and stops at the first **timed** result. If no source has timed lyrics, the first plain result is used. If nothing has any, the result is "none".

1. **The song's own file** (local tracks, and downloaded YouTube songs if their file carries lyrics): first a sidecar `.lrc` with the same name next to the file, then lyrics embedded in the file's tags (ID3 `SYLT`/`USLT`, Vorbis `LYRICS`, MP4 `©lyr`). Embedded text that contains LRC timestamps counts as timed.
2. **LRCLIB, exact match:** `GET https://lrclib.net/api/get` with `artist_name`, `track_name`, `album_name` (when known) and `duration` in whole seconds. It is accepted only if LRCLIB's duration is within **±2 s** of the track's.
3. **LRCLIB search:** `GET https://lrclib.net/api/search`, keeping only results within ±2 s. Prefer a result with `syncedLyrics`, then one with `plainLyrics`. An `instrumental: true` result counts as "none".
4. **YouTube Music's own lyrics**, for YouTube songs only: the lyrics tab that the `next` response points to, then `browse` with that id. These are usually plain text with a source credit line. Some clients return timed lyrics; whether Songies can get them is settled by a live probe at the start of the build (see Verification). If timed lyrics aren't reachable without a sign-in or a fragile client, the plain route is enough.

**Details:**

- **Requests:**
  - every LRCLIB request sends `User-Agent: Songies/<version> (https://github.com/DenisMartonak/Songie)`, as LRCLIB asks;
  - each source has a short timeout of about 10 s;
  - a source that fails (network error, timeout or a bad response) counts as "no result from this source" and the lookup moves on. A failure in every source is not cached as "none" (see Caching).
- **Timed beats plain, wherever it's from** (my call): a plain `.lrc` or plain embedded lyrics don't stop the lookup. If a later source has timed lyrics, those are shown, and the credit names that source.
- **Matching inputs:**
  - Local songs use the title, artist, album and duration stored for the track (from its tags, or the filename fallback the scanner already uses). If the artist is empty, the online sources are skipped (my call), because a title-only search too easily finds the wrong song.
  - YouTube songs use their YouTube Music title, artists and album when Songies has them. A title's "(Official Video)"-style suffixes and "- Topic" artist suffixes are stripped before searching.
  - Songs with no known duration skip the ±2 s rule, and step 2 is skipped for them.
- **YouTube Music requests:** they keep Plan 5's identities and Plan 7's rules. They go out signed out, like search, unless the probe shows the lyrics need the sign-in. In that case they go signed in only when the user is signed in.

## Caching

- **Where:** results are stored in a new `lyrics` table, keyed by track id, with columns `kind` (`synced` / `plain` / `none`), `body`, `source` (`file` / `lrclib` / `youtube`) and `fetched_at`.
- **Syncing:** the table carries the usual sync columns (stamped writes), as the main design planned, so device sync can share it later. It is not used until then.
- **Not stored:**
  - results from the song's own file are read fresh each time, since the file is the truth and may change;
  - a lookup in which **any** online source failed (network error, timeout, bad response) and none found lyrics stores nothing (my call), so a later open simply tries again. "None" is stored only when every source answered cleanly with nothing.
- **Keyed by track id only** (my call). If a song's details change, **Search again** is the way out.
- **Retrying "none":** a "none" is retried after **30 days**, or straight away from **Search again**. Search again ignores a cached result of any kind and redoes the lookup.
- **Offline:** lyrics already stored show as usual. Anything else shows "Lyrics need a connection" with no spinner.

## When lookups happen

- **Opening the view:** opening Lyrics (phone) or the lyrics panel (desktop) looks up the current song if it has no stored result.
- **While it stays open:** each new current song is looked up, and so is the song the player will play next (following shuffle and repeat), so skipping shows lyrics at once.
- **When it's closed:** no lookups happen.
- **No pile-up:** a lookup for a song that is no longer current or next may finish and be stored, but it never replaces what's shown.

## What it looks like

### Phone

- Now Playing's existing Player / Queue switch becomes **Player · Lyrics · Queue**.
- Lyrics fill the page in large, bold text:
  - the current line is at full strength;
  - the lines around it are dimmed;
  - the current line sits a little above the middle.
- A slim strip at the top keeps the song title, artist and play/pause in reach.
- Colours come from the active theme and the cover palette, like the rest of Now Playing, and meet the AA contrast rule.

### Desktop

- A **Lyrics** button in the player bar, next to Queue, toggles a right-side panel.
  - It stays open while the user moves around the app, and its open state is remembered for the session only, not across restarts (my call).
  - It works whether the queue is shown or not; the builder decides how the two share the right side.
- Smaller, quieter text than the phone view, following the song the same way.

### Behaviour on both

- **Following the song:** for timed lyrics, the highlight follows playback position, and the view scrolls smoothly to keep the current line in place. Before the first timed line, nothing is highlighted.
- **Tapping a line** seeks to that line's time (timed lyrics only).
- **Scrolling by hand** pauses following for **5 s** after the last touch, then the view glides back to the current line.
- **Reduced motion:** the view jumps instead of gliding, and the highlight changes without animation.
- **Paused playback:** nothing moves.
- **Plain lyrics:** shown in full, readable size, scrollable, with no highlight and no tapping to seek.
- **Loading:** a soft placeholder in the text area, using the existing Shimmer. It obeys reduced motion and the no-animation-while-paused rule.
- **No lyrics:** "No lyrics found for this song" with a **Search again** button.
- **Offline:** "Lyrics need a connection".
- **Credit:** a small line at the end of the lyrics, "Lyrics from LRCLIB", "Lyrics from YouTube Music" (plus YouTube's own credit line when given) or "Lyrics from the file".

## LRC parsing

- Line timestamps are `[mm:ss.xx]`, `[mm:ss.xxx]` or `[mm:ss]`.
- A line can carry several timestamps, which repeat it at each time.
- Metadata tags (`[ar:]`, `[ti:]`, `[length:]`) are ignored. An `[offset:±ms]` tag is applied.
- Word-level `<mm:ss.xx>` stamps (enhanced LRC) are stripped to plain lines.
- Lines with a timestamp but no text are kept as blank pauses.
- Lyrics whose timestamps can't be parsed at all are treated as plain text.

## Verification

- **Probe:** the build starts with a live probe, like Plan 5's: a few well-known songs through each source. It records:
  - LRCLIB's response shape;
  - which YouTube Music route returns lyrics, and whether any returns timed ones, signed out.
- **Fixtures:** they are hand-made or recorded and trimmed, following the earlier plans' rules. Lyrics fixtures use **public-domain or invented text, never copyrighted lyrics**, because the repo is public.
- **No network in tests:** tests never touch the network.

## Constraints

- **Stack:** Flutter and Dart only. Any new package needs a reason. HTTP uses the existing client helpers.
- **Rules from earlier plans still hold:**
  - no idle work;
  - tests never touch the network, the real home directories, the keyring or browser profiles;
  - every synced write is stamped;
  - Motion tokens, reduced motion, nothing animating while paused, and AA contrast;
  - a failing YouTube route never errors;
  - nothing identifying the user's account is committed.
- **Targets:** Android (minSdk 24), Windows and Linux. All three ship together.

## Left to the builder

- How the desktop panel and the queue share the right side.
- Exact type sizes, spacing and the dim level of non-current lines, within the theme and contrast rules.
- Whether downloaded YouTube files are checked for embedded lyrics (yt-dlp usually writes none).
- Whether to use the YouTube Music timed route, based on the probe. If the probe finds no usable YouTube Music lyrics route signed out, source 4 is dropped and the build carries on with the file and LRCLIB, recording why in `docs/innertube-notes.md` (my call).
- The `lyrics` table follows the existing synced tables' pattern (`SyncColumns`, stamped through `SyncStamp`, a schema migration).

"Looking something up" means tap-to-seek and scrolling. There is no search inside the lyrics (my call).
