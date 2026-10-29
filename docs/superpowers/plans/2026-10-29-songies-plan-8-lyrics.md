# Songies Plan 8: Synced Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show timed (or plain) lyrics for the playing song: a Lyrics tab on Now Playing and a right-side lyrics panel on desktop. Lyrics are looked up from the song's file, LRCLIB and YouTube Music, and kept once found.

**Architecture:**
- A pure `lib/lyrics/` core holds the model, the LRC parser and the search-text cleanup.
- Three sources each answer *found / nothing / failed*: the song's file, LRCLIB, and YouTube Music via `YtmService.lyrics`.
- A `LyricsService` runs them in order (timed wins), applies the caching rules and stores results in a new synced `lyrics` table.
- One `LyricsView` widget renders every state at two densities, `large` for the phone tab and `compact` for the desktop panel. Lookups are driven only by an open view.

**Tech Stack:** Flutter 3.47.8 (`~/development/flutter/bin`, not on PATH), Dart 3.13, Riverpod 3, drift, `audio_metadata_reader`, `dart:io` `HttpClient`.

**Spec:** `docs/superpowers/specs/2026-10-29-songies-lyrics-design.md`. Read it before any task. Where this plan and the spec disagree, the spec wins.

## Global Constraints

- **Network rules:**
  - Lookups happen only while a Lyrics view (phone tab, desktop panel or the desktop Now Playing dialog's Lyrics tab) is open. There is no background fetching, polling or library-wide pre-fetch.
  - Tests never touch the network, the real home directories, the keyring or browser profiles. Every HTTP call goes through an injectable function.
- **LRCLIB requests:**
  - every request sends `User-Agent: Songies/1.0.0 (https://github.com/DenisMartonak/Songie)`. Build it from `appVersion` in `lib/ui/settings/settings_page.dart`; move that constant to `lib/core/app_version.dart` and re-export it if needed;
  - the timeout is 10 s per source request;
  - a duration match means within ±2 s, in whole seconds.
- **Fixtures** contain only invented or public-domain lyric text, never copyrighted lyrics, and nothing identifying an account. The repo is public.
- **Sync columns:**
  - the `lyrics` table uses `SyncColumns`, with `id` equal to the track id (one row per track);
  - every write is stamped through `SyncStamp.next()`;
  - the schema goes from 5 to 6.
- **Earlier rules still hold:**
  - Motion tokens (`Motion.of(context)`): everything is zero under reduced motion, and nothing animates while playback is paused;
  - AA contrast through the theme's `SongiesColors`;
  - a failing YouTube route never errors.
- **YouTube Music requests** go out signed out (no `session:`). This changes only if Task 1's probe shows that lyrics need the sign-in, in which case it's recorded as a ruling.
- **Commits** end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01PjntrucDy7bCG4aSheCsV1`
- **Checks before each commit:** `flutter analyze` is clean and `flutter test` passes. Use `dart format` on touched files only, never on whole directories.

## Review Focus

1. **The song changes while a lookup is in flight.** The old song's result must never be shown for the new one; it may still be stored. Test: `LyricsView` with a slow fake service, switch the current track, finish the old lookup, and expect the new track's state.
2. **Seeking backward, or a position before the first timed line.** The highlight moves back, and before the first line nothing is highlighted. Test: `currentLineIndex` for a position before line 0, and after a backward seek (Task 2), plus a widget test that seeks back (Task 7).
3. **Offline, then online.** Offline with nothing stored shows "Lyrics need a connection" and stores nothing; reopening when online looks it up. Test in Task 6 (service), and a view test in Task 7.
4. **Long lyrics and long lines on a 400 px phone and in a 320 px desktop panel.** No overflow, and the current line stays in view. Widget test in Task 7 at both sizes.
5. **The same song requested twice at once** (the current and the next are the same with repeat-one, or a double open). There is one lookup, not two. Test: `LyricsService` in-flight de-duplication in Task 6.

---

### Task 1: Live probe, notes and fixtures

**Files:**
- Create: `tool/lyrics_probe.dart`
- Create: `test/fixtures/lyrics/lrclib_get.json`, `lrclib_search.json`, `ytm_next_lyrics_tab.json`, `ytm_browse_lyrics_plain.json`, plus `ytm_browse_lyrics_timed.json` only if the probe finds a timed route
- Modify: `docs/innertube-notes.md` (new "Lyrics" section)

**Interfaces:**
- Produces:
  - the fixtures that Tasks 4 and 5 parse;
  - a written ruling in `docs/innertube-notes.md` on (a) which `next` path holds the lyrics tab browse id, (b) the `browse` response shape for lyrics text and source credit, and (c) whether any client returns timed lyrics signed out.

- [ ] **Step 1: Write `tool/lyrics_probe.dart`**, a dev-only CLI like `tool/innertube_probe.dart`, never imported by `lib/` or tests:
  - It runs as `dart run tool/lyrics_probe.dart --out <dir>`, and refuses an `--out` inside the repo.
  - For two well-known songs (pick songs with a YouTube video id and an LRCLIB entry), it calls LRCLIB `/api/get` and `/api/search`, then WEB_REMIX `next` and the lyrics-tab `browse`.
  - If `docs/innertube-notes.md` or yt-dlp/ytmusicapi name a timed-lyrics client, it tries that too: ytmusicapi `get_lyrics(timestamps=True)` uses the ANDROID_MUSIC client and reads `timedLyricsModel`.
  - It prints a summary of each response's shape (keys, paths, counts, whether `syncedLyrics` is present) and writes the raw responses to `--out`.
- [ ] **Step 2: Run it** with `export PATH=$HOME/development/flutter/bin:$PATH && dart run tool/lyrics_probe.dart --out /tmp/claude-1000/lyrics-probe`. Expected: both LRCLIB endpoints answer 200, and `next` has a lyrics tab.
- [ ] **Step 3: Hand-craft the fixtures** from the recorded shapes.
  - Keep only the paths the parsers read, plus enough siblings to keep the parser honest.
  - **Replace every lyric line with invented text** (for example "First invented line"). Synced fixtures keep realistic `[mm:ss.xx]` stamps.
  - `lrclib_search.json` holds at least:
    - one result outside ±2 s;
    - one plain-only result;
    - one synced result;
    - one `instrumental: true` result.
- [ ] **Step 4: Document it** in `docs/innertube-notes.md` → "Lyrics": the endpoints, paths, credit-line location, the timed-route finding with a ruling (use it or not), and the probe date.
- [ ] **Step 5: Commit** `tool/lyrics_probe.dart`, the fixtures and the notes: `feat: lyrics probe, notes and fixtures`.

### Task 2: Lyrics core (model, LRC parser, search text)

**Files:**
- Create: `lib/lyrics/lyrics.dart`
- Create: `lib/lyrics/lrc.dart`
- Test: `test/lyrics/lrc_test.dart`, `test/lyrics/lyrics_test.dart`

**Interfaces:**
- Produces:
  - `enum LyricsKind { synced, plain, none }`
  - `enum LyricsSource { file, lrclib, youtube }`
  - `class LyricLine { const LyricLine(this.time, this.text); final Duration time; final String text; }`
  - `class TrackLyrics { const TrackLyrics({required this.kind, required this.source, this.lines = const [], this.text = '', this.credit}); final LyricsKind kind; final LyricsSource? source; final List<LyricLine> lines; final String text; final String? credit; }`. Here `lines` is used for `synced`, `text` for `plain`, and `credit` holds YouTube's own credit line. Value equality applies.
  - `TrackLyrics.fromStored(String kind, String body, String? source)` and `({String kind, String body}) toStored()`. Synced lyrics are stored as LRC text, plain as text, none as `''`. The credit is stored as a trailing `[by:<credit>]` LRC tag for synced lyrics, and as a final line prefixed `\u0000credit:` for plain.
  - `List<LyricLine>? parseLrc(String text)`: null when no line timestamp parses.
  - `String toLrc(List<LyricLine> lines)`: `[mm:ss.xx]text`, one per line.
  - `int currentLineIndex(List<LyricLine> lines, Duration position)`: the last line with `time <= position`, or `-1`. Binary search.
  - `String searchTitle(String title)` and `String searchArtist(String artist)`.

- [ ] **Step 1: Write the failing tests:**
  - `parseLrc`:
    - `[00:12.34]a` gives `12.34 s`;
    - `[01:02.345]b` gives `62.345 s`;
    - `[00:05]c` gives `5 s`;
    - `[00:01.00][00:09.00]x` gives two lines;
    - `[ar:A]`, `[ti:T]` and `[length:3:00]` are ignored;
    - `[offset:+500]` makes all times 500 ms *earlier* (the LRC convention: a positive offset shifts lyrics up);
    - `[00:01.00]<00:01.00>w1 <00:01.50>w2` gives the text `w1 w2`;
    - `[00:03.00]` gives a blank line;
    - the output is sorted by time;
    - `'just text\nno stamps'` gives null.
  - `currentLineIndex` on lines at 5 s, 10 s and 15 s:
    - 0 s gives -1;
    - 5 s gives 0;
    - 12 s gives 1;
    - 99 s gives 2;
    - a backward seek from 12 s to 6 s gives 0.
  - `searchTitle`:
    - `'Song (Official Video)'` gives `'Song'`;
    - `'Song [Official Music Video]'` gives `'Song'`;
    - `'Song (Lyric Video)'` gives `'Song'`;
    - `'Song (Official Audio)'` gives `'Song'`;
    - `'Song (feat. X)'` stays `'Song (feat. X)'`.
  - `searchArtist`:
    - `'Name - Topic'` gives `'Name'`;
    - `'NameVEVO'` gives `'Name'`.
  - `TrackLyrics` survives a `toStored` / `fromStored` round trip for synced with a credit, plain with a credit, and none.
- [ ] **Step 2: Run** `flutter test test/lyrics`. Expected: it fails to compile (no `lib/lyrics`).
- [ ] **Step 3: Implement** both files. Use one regex for line stamps, `\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]`. A fraction of 1–3 digits scales to milliseconds by its length.
- [ ] **Step 4: Run** `flutter test test/lyrics`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: lyrics model, LRC parser and search text`.

### Task 3: The `lyrics` table and its store

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart` (schema 6), then regenerate `lib/data/database.g.dart` with `dart run build_runner build --delete-conflicting-outputs`
- Create: `lib/lyrics/lyrics_store.dart`
- Test: `test/lyrics/lyrics_store_test.dart`, plus a migration test following the existing migration tests (`grep -rln "schemaVersion\|from < 5" test`)

**Interfaces:**
- Consumes: `TrackLyrics`, `LyricsKind`, `LyricsSource` (Task 2), `SyncStamp`, and `guardDb` (`lib/data/db_guard.dart`).
- Produces:
  - Table `@DataClassName('LyricsRow') class Lyrics extends Table with SyncColumns`, with `TextColumn kind`, `TextColumn body`, `TextColumn source` (nullable; `file`/`lrclib`/`youtube`) and `DateTimeColumn fetchedAt`. The id is the track id.
  - `class StoredLyrics { final TrackLyrics lyrics; final DateTime fetchedAt; }`
  - `class LyricsStore { LyricsStore(AppDatabase db, SyncStamp stamp); Future<StoredLyrics?> read(String trackId); Future<void> write(String trackId, TrackLyrics l, DateTime fetchedAt); }`. `read` returns null for no row or a tombstoned row. `write` upserts one stamped row, never stores `LyricsSource.file`, and never throws: failures are logged with `AppLog.w`.

- [ ] **Step 1: Write the failing tests:**
  - a round trip of a synced, a plain and a none result, including `fetchedAt`;
  - a second write to the same track replaces the first, with a newer `clock`, and still one row;
  - a `TrackLyrics` with `source: LyricsSource.file` writes nothing;
  - `read` of an unknown id gives null;
  - migration: a v5 database opens at v6 with an empty `lyrics` table.
- [ ] **Step 2: Run** `flutter test test/lyrics/lyrics_store_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Add the table to `@DriftDatabase(tables: …)`, set `schemaVersion => 6`, add `if (from < 6) await m.createTable(lyrics);`, and regenerate.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: synced lyrics table and store`.

### Task 4: File and LRCLIB sources

**Files:**
- Create: `lib/lyrics/lyrics_sources.dart` (the answer type), `lib/lyrics/file_lyrics.dart`, `lib/lyrics/lrclib.dart`
- Modify: `lib/library/tag_reader.dart` (add `lyrics` to `TrackTags`, read it in `_read` from `m.lyrics`)
- Test: `test/lyrics/file_lyrics_test.dart`, `test/lyrics/lrclib_test.dart`

**Interfaces:**
- Consumes: Task 2's model and parser, the Task 1 fixtures, `TagReader`.
- Produces:
  - `sealed class SourceAnswer`, with `final class Found extends SourceAnswer { final TrackLyrics lyrics; }`, `final class Nothing extends SourceAnswer {}` and `final class Failed extends SourceAnswer { final Object error; }`.
  - `class LyricsQuery { final String title; final String artist; final String? album; final int? durationSec; final String? videoId; }`. It is built by the service from a `Track`, with `searchTitle` / `searchArtist` applied.
  - `typedef HttpGet = Future<({int status, String body})> Function(Uri uri, Map<String, String> headers);`, with `Future<({int status, String body})> ioHttpGet(Uri, Map<String, String>)` implemented with `HttpClient` and a 10 s overall timeout.
  - `class LrclibSource { LrclibSource(HttpGet get, {required String userAgent}); Future<SourceAnswer> exact(LyricsQuery q); Future<SourceAnswer> search(LyricsQuery q); }`.
  - `class FileLyricsSource { FileLyricsSource(TagReader tags); Future<SourceAnswer> read(String? audioPath); }`. It reads the sidecar `<path without extension>.lrc` first, then the tags. A null path, or no file, gives `Nothing`.
- **LRCLIB rules:**
  - `exact` is skipped (`Nothing`) when `durationSec` is null.
  - `/api/get` answers:
    - 200 → check ±2 s, then `syncedLyrics` → synced (through `parseLrc`; if that gives null, plain), else `plainLyrics` → plain;
    - 404 → `Nothing`;
    - other statuses, a timeout, a socket error or bad JSON → `Failed`.
  - `search` uses `track_name` and `artist_name` and keeps results within ±2 s, or all results when the duration is null. It prefers the first result with synced lyrics, then the first with plain. An `instrumental: true` match gives `Nothing`.

- [ ] **Step 1: Write the failing tests:**
  - **LRCLIB, with a fake `HttpGet` that records URIs and headers:**
    - the User-Agent header equals the given string;
    - the `/api/get` query carries `artist_name`, `track_name`, `album_name` (left out when null) and `duration` as an integer;
    - 200 with a duration 3 s off gives `Nothing`;
    - 200 synced gives synced lines from the fixture;
    - 200 with plain only gives plain;
    - 404 gives `Nothing`;
    - 500 gives `Failed`;
    - a thrown `SocketException` gives `Failed`;
    - malformed JSON gives `Failed`;
    - `search` on `lrclib_search.json` picks the synced in-window result over an earlier plain one, and ignores the out-of-window one;
    - an instrumental result gives `Nothing`.
  - **File source, with a temp dir from `Directory.systemTemp.createTemp` and a fake `TagReader`:**
    - a sidecar `.lrc` with stamps gives synced from `LyricsSource.file`;
    - a sidecar without stamps gives plain;
    - no sidecar plus tag lyrics with stamps gives synced;
    - no sidecar and no tag lyrics gives `Nothing`;
    - a null path gives `Nothing`;
    - a tag reader that throws gives `Nothing` (a file without tags is not a failure).
- [ ] **Step 2: Run** `flutter test test/lyrics`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: file and LRCLIB lyrics sources`.

### Task 5: YouTube Music lyrics

**Files:**
- Modify: `lib/innertube/ytm_service.dart` (add `lyrics`), `lib/innertube/ytm_parse.dart` (parsers)
- Test: `test/innertube/ytm_lyrics_test.dart`

**Interfaces:**
- Consumes: the Task 1 fixtures and ruling, `InnertubeClient.call`, `kWebRemix`, and the `SourceAnswer` / `TrackLyrics` types.
- Produces:
  - `Future<Result<TrackLyrics?>> YtmService.lyrics(String videoId)`. It returns `Ok(null)` when there is no lyrics tab or the tab has no text, `Ok(TrackLyrics)` for plain lyrics (with `credit` set from the footer), and synced only if Task 1 ruled the timed route in. A request failure is `Err`.
  - `String? lyricsBrowseId(Map<String, Object?> nextJson)`
  - `TrackLyrics? parseLyricsBrowse(Map<String, Object?> json)`
  - `class YtmLyricsSource { YtmLyricsSource(YtmService s); Future<SourceAnswer> fetch(String? videoId); }`. A null id gives `Nothing`, `Ok(null)` gives `Nothing`, `Ok(l)` gives `Found(l)`, and `Err` gives `Failed`.
- `next` is called with `{'videoId': id, 'isAudioOnly': true}` (adjust to whatever Task 1 found works), then `browse` with `{'browseId': lyricsBrowseId}`.

- [ ] **Step 1: Write the failing tests:**
  - `lyricsBrowseId` finds the id in `ytm_next_lyrics_tab.json`, and gives null on the `next_radio.json` fixture if it has no lyrics tab (or on a copy with the tab removed);
  - `parseLyricsBrowse` gives plain text and credit from `ytm_browse_lyrics_plain.json`, and null on `{}`;
  - `YtmService.lyrics` over a fake transport (as in the existing `ytm_service` tests) calls `next` then `browse`;
  - a `next` failure gives `Err`;
  - `YtmLyricsSource` maps each case as listed above.
- [ ] **Step 2: Run** `flutter test test/innertube/ytm_lyrics_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, reusing the path helpers already in `ytm_parse.dart`.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: YouTube Music lyrics`.

### Task 6: LyricsService (order, caching, de-duplication) and providers

**Files:**
- Create: `lib/lyrics/lyrics_service.dart`
- Modify: `lib/player/player_service.dart` (add `PlayerState.upNext`), `lib/providers.dart`, `lib/main.dart` (wiring)
- Test: `test/lyrics/lyrics_service_test.dart`, plus `upNext` cases in `test/player/player_service_test.dart`

**Interfaces:**
- Consumes: Tasks 2–5, `NetworkStatus`, and the `localFiles` table (the audio path is the `localFiles` row for the track with `state == 'done'` and a non-empty path).
- Produces:
  - `sealed class LyricsState`, with:
    - `LyricsLoading`;
    - `LyricsShown(TrackLyrics lyrics)` for synced or plain;
    - `LyricsNone()`, which offers Search again;
    - `LyricsOffline()`, meaning "Lyrics need a connection".
  - `class LyricsService { LyricsService({required AppDatabase db, required LyricsStore store, required FileLyricsSource file, required LrclibSource lrclib, required YtmLyricsSource ytm, required NetworkStatus network, DateTime Function() now = DateTime.now}); Future<LyricsState> lookup(Track t, {bool force = false}); void prefetch(Track? t); }`
  - `Track? get upNext` on `PlayerState`. It returns null with `RepeatMode.one`. Otherwise it returns the first entry after `index` whose track is not `unavailable`, wrapping to the start only with `RepeatMode.all`, and never the current entry itself.
  - Providers:
    - `lyricsServiceProvider` (`_unwired` like its neighbours, overridden in `main.dart`);
    - `lyricsProvider = FutureProvider.autoDispose.family<LyricsState, String>`, keyed by track id; it reads the track from the player state's queue, or else the db;
    - `lyricsRetryProvider`, a family `Notifier<int>` per track id that Search again bumps to force a fresh lookup.
- **`lookup` rules** (from the spec):
  1. The file source runs first, every time. A timed answer is returned at once and never stored.
  2. A stored result is used unless `force`:
     - `synced` and `plain` are always used;
     - `none` is used while `fetchedAt` is less than 30 days old.
     - A stored result never beats a timed file answer, and a plain file answer is kept only as a fallback.
  3. With an empty artist (after `searchArtist`), the online sources are skipped. The result is then the file's plain answer or `LyricsNone`, and it is not stored.
  4. If the network reports offline, the result is the file's plain answer if any, else `LyricsOffline`. Nothing is stored.
  5. The online sources run in order: LRCLIB `exact`, LRCLIB `search`, then YouTube Music (only when `t.source == 'yt'`). The first synced `Found` stops the run. The first plain `Found` is remembered.
  6. The result is the best of the file's plain answer and the online answers (synced beats plain; among plain, the earliest source in order wins).
  7. **Storing:**
     - a non-file result is stored;
     - `none` is stored only if no source answered `Failed`;
     - if every online source failed and there's no answer, the result is `LyricsOffline` with nothing stored;
     - if some sources failed and the rest answered `Nothing`, the result is `LyricsNone` with nothing stored.
  8. While a lookup for a track id is in flight, a second call (lookup or prefetch) joins the same `Future`. `force` starts a new lookup only when none is running.
  9. `lookup` never throws. An unexpected error is logged, and the result is `LyricsNone` with nothing stored.

- [ ] **Step 1: Write the failing tests**, using fake sources (each records calls and returns a scripted `SourceAnswer`), a test db and a fake `NetworkStatus`. One test per rule above. Include:
  - LRCLIB plain plus YouTube Music synced gives the YouTube synced lyrics;
  - a file plain answer plus LRCLIB synced gives LRCLIB;
  - a stored `none` from 31 days ago is looked up again, and one from 29 days ago is not;
  - `force` ignores a stored synced result;
  - two concurrent `lookup`s make one call to each source;
  - `prefetch` then `lookup` makes one call;
  - offline with a stored result shows it;
  - offline with nothing stored gives `LyricsOffline`, with no source called except the file source.
  - `upNext` tests:
    - the middle of the queue gives the next track;
    - the end with repeat off gives null;
    - the end with repeat all gives the first track;
    - repeat one gives null;
    - an unavailable next track is skipped;
    - a one-song queue with repeat all gives null.
- [ ] **Step 2: Run** `flutter test test/lyrics/lyrics_service_test.dart test/player/player_service_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, and wire `main.dart`:
  - `LyricsStore(db, stamp)`;
  - `FileLyricsSource(AudioMetadataTagReader())`;
  - `LrclibSource(ioHttpGet, userAgent: 'Songies/$appVersion (https://github.com/DenisMartonak/Songie)')`;
  - `YtmLyricsSource(ytmService)`;
  - `network`.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: lyrics service, caching and providers`.

### Task 7: LyricsView widget

**Files:**
- Create: `lib/ui/lyrics/lyrics_view.dart`
- Test: `test/ui/lyrics_view_test.dart`

**Interfaces:**
- Consumes: `lyricsProvider`, `lyricsRetryProvider`, `lyricsServiceProvider.prefetch`, `playerStateProvider` (current, position, playing, upNext), `playerServiceProvider.seek`, `Motion.of`, `Shimmer`, `SongiesColors`, and `networkStatusProvider` (for re-trying when offline turns online while open).
- Produces: `enum LyricsDensity { large, compact }`, and `class LyricsView extends ConsumerStatefulWidget { const LyricsView({this.density = LyricsDensity.large, super.key}); }`. The view shows the current track's lyrics and, while mounted, calls `prefetch(upNext)` whenever `upNext` changes.

**Behaviour** (the spec's "What it looks like" section has the full copy):
- **Synced lyrics** are a `ListView` of lines. The current line (from `currentLineIndex`) is at full `colors.text`, and the others are at about 45 % alpha, which must still meet AA contrast against the background for large text.
  - The current line is kept about 35 % from the top. The view scrolls with `Motion.of(context).emphasized` and `Motion.emphasizedCurve`, or jumps when that's zero.
  - It does not scroll while `playing` is false.
  - Tapping a line calls `seek(line.time)`.
- **Scrolling by hand** (a `ScrollStartNotification` with `dragDetails != null`, or a pointer scroll) pauses following. Following resumes 5 s after the last user scroll, by scrolling back to the current line. Use a `Timer` that is cancelled in `dispose`.
- **Plain lyrics** are a scrollable column of text with no highlight and no tap action.
- **Loading** shows four to six `Shimmer` bars.
- **`LyricsNone`** shows "No lyrics found for this song" and a `TextButton` "Search again" that bumps `lyricsRetryProvider`.
- **`LyricsOffline`** shows "Lyrics need a connection". When `networkStatus.changes` reports a connection while this is shown, the provider is invalidated.
- **Credit** is a small `colors.mutedText` line at the end: "Lyrics from LRCLIB", "Lyrics from YouTube Music", or "Lyrics from the file". For YouTube, its own credit line follows on the next line.
- **Densities:** `large` is about 26 px, w800; `compact` is about 16 px, w700. Exact values are up to the builder within the theme.
- **No track** shows nothing (`SizedBox.shrink`).

- [ ] **Step 1: Write the failing widget tests**, using the existing UI harness (`test/helpers/ui_harness.dart`), with `lyricsServiceProvider` overridden by a fake and a fake player state stream:
  - synced lyrics highlight line 1 at 12 s, and none at 0 s;
  - after a seek back to 6 s, line 0 is highlighted;
  - tapping line 2 calls `seek` with its time;
  - a user drag stops following, and after `pump(5 s)` following resumes;
  - while paused, a position change does not scroll (the scroll offset is unchanged);
  - with reduced motion (the setting the existing motion tests use), there are no running animations after a line change;
  - plain lyrics show their text, and tapping does nothing;
  - `LyricsNone` shows "Search again", which calls the service with `force: true`;
  - `LyricsOffline` shows "Lyrics need a connection";
  - the credit text appears for each source;
  - Review Focus 1: a slow lookup for track A, the current track switches to B, then A completes, and B's state is shown;
  - Review Focus 4: 60 long lines at 400×800 (`large`) and at a 320 px wide panel (`compact`) give no overflow exception, and the current line's rect is inside the viewport;
  - `prefetch` is called with `upNext`.
- [ ] **Step 2: Run** `flutter test test/ui/lyrics_view_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: lyrics view`.

### Task 8: Now Playing tab, mini strip and desktop panel

**Files:**
- Modify: `lib/ui/now_playing/now_playing_header.dart` (tabs), `lib/ui/now_playing/now_playing_page.dart`, `lib/ui/shell/player_bar.dart`, `lib/ui/shell/desktop_shell.dart`, `lib/providers.dart`
- Create: `lib/ui/lyrics/lyrics_panel.dart`, `lib/ui/lyrics/lyrics_strip.dart`
- Test: `test/ui/now_playing_lyrics_test.dart`, `test/ui/lyrics_panel_test.dart`, and update the existing tests that use `NowPlayingTabs(showQueue:…)`

**Interfaces:**
- Consumes: `LyricsView` (Task 7).
- Produces:
  - `enum NowPlayingTab { player, lyrics, queue }`
  - `NowPlayingTabs({required NowPlayingTab selected, required ValueChanged<NowPlayingTab> onChanged})`, with keys `nowPlaying.tab.player`, `nowPlaying.tab.lyrics` and `nowPlaying.tab.queue`, labelled "Now playing", "Lyrics" and "Queue".
  - `lyricsPanelOpenProvider = NotifierProvider<LyricsPanelOpen, bool>`, which is session-only and starts false.
  - The player bar button has key `playerBar.lyrics`, tooltip "Lyrics", icon `Icons.lyrics_outlined` (filled `Icons.lyrics` while open, in `colors.accent`), and sits before the Queue button.

- [ ] **Step 1: Write the failing tests:**
  - **Phone (400×800):**
    - Now Playing shows three tabs;
    - tapping Lyrics shows `LyricsView` (large) and `LyricsStrip`, which shows the title, the artist and a play/pause button that toggles the player;
    - Queue still works.
  - **Desktop Now Playing dialog:** the Lyrics tab shows `LyricsView`.
  - **Desktop shell (1280×800):**
    - `playerBar.lyrics` toggles a right-side `LyricsPanel` (`compact`, about 320 px wide) beside the main pane;
    - the panel stays open across navigation to another tab;
    - the button shows its open state;
    - with no current track, the panel shows nothing but stays toggleable.
  - Existing Now Playing tests still pass after the tabs change.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The panel is a sibling of the main pane in `DesktopShell`'s `Row`, after the `Expanded` main pane. It is animated in and out with `AnimatedSize` and `Motion.of(context).standard`, and uses the same rounded `colors.background` surface, padding and `ExcludeFocus` conventions.
  - `LyricsStrip` is a slim row (about 56 px) with the title, the artist and a play/pause `IconButton`, shown above `LyricsView` on the phone tab only.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat: lyrics tab on Now Playing and a desktop lyrics panel`.

### Task 9: Docs, checklist, builds

**Files:**
- Modify: `docs/PROGRESS.md`, `docs/manual-test-checklist.md`, `docs/superpowers/specs/2026-10-21-songies-design.md` (§10 gets a one-line pointer: "Replaced by 2026-10-29-songies-lyrics-design.md")
- Create: `docs/plan-8-session-log.md`

- [ ] **Step 1: Add a "Plan 8: lyrics" section** to the manual checklist, with one check for each of these, covering phone, desktop Linux and Windows:
  - a mainstream YouTube song shows timed lyrics;
  - tapping a line seeks;
  - scrolling pauses following for 5 s;
  - a local file with a sidecar `.lrc` uses it;
  - an obscure song shows "No lyrics found" and Search again;
  - airplane mode shows lyrics already viewed, and "Lyrics need a connection" for others;
  - reduced motion jumps;
  - while paused, nothing moves;
  - the desktop panel persists across tabs;
  - the credit line is right.
- [ ] **Step 2: Update PROGRESS.md** (Plan 8 status, rulings, and the next step: Plan 9 listening statistics) and write the session log.
- [ ] **Step 3: Verify:**
  - run `flutter analyze`, `flutter test`, `flutter build apk --release` and `flutter build linux --release`. Expected: all succeed; note the APK size;
  - run `git log -p <base>..HEAD | grep -nE "SAPISID|__Secure-|LOGIN_INFO"`. Expected: no real values;
  - check that the fixtures hold no real lyric lines (`grep -c "invented" test/fixtures/lyrics/*`, plus a manual read).
- [ ] **Step 4: Commit** `docs: Plan 8 verification, checklist and progress`.
