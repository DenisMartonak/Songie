# Spotify Playlist Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paste a public Spotify playlist link into the import dialog; Songies reads it (embed page, then a hidden browser past 100 songs), matches each song on YouTube Music, creates a local playlist, and offers a review of unsure and missing songs.

**Architecture:** `lib/spotify/` holds pure pieces (link parsing, embed JSON parsing, page-row parsing, match scoring) plus two readers: `EmbedReader` (HTTP GET of the embed page) and `PageReader` (a hidden web view that scrolls the playlist page and returns rows). `SpotifyImportService` orchestrates reading → matching (via `YtmService.search` and `YtTrackStore.upsert`) → creating the playlist with `LibraryRepository`. The import dialog routes by link type.

**Tech Stack:** Flutter 3.47.8, `http` via `httpDownload`, `flutter_inappwebview` headless web view (Android, Windows), a new hidden-browser component on Linux (chosen in Task 1), Riverpod, drift.

**Spec:** `docs/superpowers/specs/2026-11-01-spotify-import-design.md`

## Global Constraints

- Links: `https://open.spotify.com/playlist/<id>`, `https://open.spotify.com/intl-xx/playlist/<id>`, query strings ignored, `spotify:playlist:<id>`. Album/track links → `Only Spotify playlist links can be imported`.
- Errors: private/deleted/invalid → `This Spotify playlist isn't public, or the link is wrong`. Cut at 100 → `Imported the first 100 of <N> songs — Spotify's page couldn't be read past that.`
- Progress text: `Reading songs… <n> / <N>`, then `Matching… <n> / <N>`. Dialog stays open with Cancel; cancelling offers "Keep the <k> matched so far" or discard.
- Result: `source: 'local'`, no `ytPlaylistUrl` (so no sync button), name and cover from Spotify, songs in Spotify's order; YouTube Music's song names.
- Review sheet after import: `"<m> of <N> matched"`, unsure and missing listed; per song: preview, pick from top 5 results, or remove.
- Matching pace: at most 3 searches in flight.
- No Spotify account, no Spotify API. The hidden browser keeps no data after the import.
- Fixtures use invented song and artist names.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`; the two stats "under 500 ms" tests fail only under full-suite load.

## Review Focus

- A playlist with the same song twice: both positions keep it (two entries, one track). → Task 4.
- A Spotify title with "(feat. X)" or "- Remastered 2011": still a sure match for the plain YouTube title. → Task 3.
- Spotify's page changes so no rows are found: import continues with the first 100 and the cut message. → Task 2.
- Network drops halfway through matching: the songs not yet searched become "missing" and the user can keep the rest. → Task 4.
- The hidden browser hangs: a 60 s overall timeout ends reading, the browser is disposed. → Task 2.

---

### Task 1: Link parsing, embed reading, and the Linux hidden-browser choice

**Files:** Create `lib/spotify/spotify_links.dart`, `lib/spotify/embed_reader.dart`, `lib/spotify/spotify_models.dart`; Test `test/spotify/spotify_links_test.dart`, `test/spotify/embed_reader_test.dart`, fixture `test/fixtures/spotify/embed_invented.html`; Create `docs/spotify-notes.md`

**Interfaces — Produces:**
- `sealed class SpotifyLink`: `SpotifyPlaylistLink(String id)`, `SpotifyOtherLink()`; `SpotifyLink? parseSpotifyLink(String input)` (null = not Spotify).
- `class SpotifySong { final String title; final List<String> artists; final Duration? length; }`, `class SpotifyPlaylist { final String name; final Uri? cover; final List<SpotifySong> songs; final int? total; }`
- `SpotifyPlaylist parseEmbed(String html)` (reads `__NEXT_DATA__`: name, cover, `trackList[].title/subtitle/duration`; subtitle split on `, `); throws `FormatException` when absent.
- `class EmbedReader { EmbedReader(Future<List<int>> Function(Uri) get); Future<Result<SpotifyPlaylist>> read(String id); }` — 404 or no data → `FailureKind.notFound`.
- [ ] **Step 1: Failing tests:** each link form parses to the id; `open.spotify.com/album/x` → `SpotifyOtherLink`; YouTube links → null; the fixture parses to its name, 3 songs, artists split, length in ms; garbage HTML → `FormatException`; 404 → `notFound`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Linux component spike (no product code):** evaluate a hidden WebKitGTK web view for Linux (a package offering offscreen/headless WebKitGTK, or a small native plugin around `WebKitWebView` in an offscreen `GtkWindow`). Record in `docs/spotify-notes.md`: the choice, added size, and a 20-line proof that it loads a page and runs a script hidden. If nothing works, stop and ask the user (their decision was a truly hidden browser).
- [ ] **Step 6: Commit** `feat: Spotify link parsing and embed reading`

### Task 2: Reading past 100 with a hidden browser

**Files:** Create `lib/spotify/page_reader.dart`, `lib/spotify/page_rows.dart` (pure row parsing), the Linux component from Task 1 (`packages/` or `linux/` plugin); Test `test/spotify/page_rows_test.dart`, `test/spotify/page_reader_test.dart` (fake web view)

**Interfaces — Produces:**
- `abstract class HiddenBrowser { Future<void> load(Uri url); Future<Object?> eval(String js); Future<void> dispose(); }` with `InAppHeadlessBrowser` (Android/Windows, `HeadlessInAppWebView`, throwaway environment) and the Linux one.
- `List<({int index, SpotifySong song})> parseRows(Object? evalResult)` — the scroll script returns rendered rows as JSON `[{i, title, artists, length}]`.
- `class PageReader { PageReader(HiddenBrowser Function() create, {Duration timeout = const Duration(seconds: 60)}); Future<Result<List<SpotifySong>>> readAll(String id, {required int expected, void Function(int read)? onProgress}); }` — loads `open.spotify.com/playlist/<id>`, repeatedly scrolls the list container and collects rows by index until `expected` or no new rows for 3 rounds; always disposes the browser.
- [ ] **Step 1: Failing tests:** `parseRows` on recorded eval output keeps order by `i` and de-duplicates by `i`; fake browser returning rows 0–49, then 40–99, then 90–149 → 150 songs; fake returning nothing new → stops after 3 rounds with what it has; fake that never answers → `Err` after the timeout, `dispose` called.
- [ ] **Step 2–4:** Run → FAIL; implement; run → PASS.
- [ ] **Step 5: Commit** `feat: read long Spotify playlists with a hidden browser`

### Task 3: Match scoring

**Files:** Create `lib/spotify/matcher.dart`; Test `test/spotify/matcher_test.dart`

**Interfaces — Produces:** `enum MatchGrade { sure, unsure, missing }`; `({YtmSong? best, MatchGrade grade, List<YtmSong> alternatives}) pickMatch(SpotifySong s, List<YtmSong> results)` — normalise titles (strip "(feat. …)", "- Remastered …", "(Radio Edit)" on both sides), score artist overlap, title similarity, length within 5 s, prefer song results over videos, penalise live/cover/remix/karaoke/instrumental words absent from the Spotify title. `alternatives` = top 5 by score.
- [ ] **Step 1: Failing tests** (invented songs): exact title+artist+length → `sure`; "Song (feat. B) - Remastered 2011" vs "Song" by the same artist → `sure`; only a "Song (Live)" result → `unsure`; a different artist with the same title → `unsure`; no results → `missing`, `best` null; a Spotify title containing "Remix" accepts a remix result as `sure`.
- [ ] **Step 2–4:** Run → FAIL; implement; run → PASS.
- [ ] **Step 5: Commit** `feat: match Spotify songs to YouTube Music`

### Task 4: The import service

**Files:** Create `lib/spotify/spotify_import_service.dart`; Modify `lib/providers.dart`, `lib/main.dart`; Test `test/spotify/spotify_import_service_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3; `YtmService.search(query, YtmSearchKind.songs)`, `YtTrackStore.upsert`, `LibraryRepository.createPlaylist`/`addTracks`, the art cache for the cover.
- Produces: `class SpotifyImportService { Future<Result<SpotifyImportResult>> import(String id, {void Function(SpotifyImportProgress p)? onProgress, CancelToken? cancel}); }`, `class SpotifyImportResult { final String playlistId; final int total; final List<SpotifyReviewItem> review; final bool cutAt100; }`, `class SpotifyReviewItem { final int position; final SpotifySong song; final MatchGrade grade; final String? entryId; final List<YtmSong> alternatives; }`.
- Reads the embed; if `total > songs.length` or `songs.length == 100`, runs `PageReader` and merges by position (embed wins for 0–99); on page failure keeps 100 and sets `cutAt100`. Matches with at most 3 searches in flight; creates the playlist only after matching (or on "keep so far" when cancelled).
- [ ] **Step 1: Failing tests** (fakes): a 3-song playlist → playlist named as Spotify, 3 entries in order, `source == 'local'`, `ytPlaylistUrl == null`; a duplicate song → two entries, one track; 150 songs with a failing page reader → 100 entries, `cutAt100`; search errors for songs 50+ → those are `missing` in `review`; cancel at 40 → no playlist unless `keepPartial`; never more than 3 searches concurrently.
- [ ] **Step 2–4:** Run → FAIL; implement; run → PASS.
- [ ] **Step 5: Commit** `feat: Spotify playlist import service`

### Task 5: Import dialog and review sheet

**Files:** Modify `lib/ui/library/import_dialog.dart` (route by `parseSpotifyLink`; progress text; Cancel with keep/discard), `lib/youtube/share_intents.dart` (Spotify links in shared text); Create `lib/ui/library/spotify_review_sheet.dart`; Modify `docs/manual-test-checklist.md` (Spotify section: short playlist, 150-song playlist on each platform, private link); Tests `test/ui/import_dialog_test.dart`, `test/ui/spotify_review_sheet_test.dart`

- [ ] **Step 1: Failing tests:** pasting a Spotify playlist link shows `Reading songs…` then `Matching…` and ends on the review sheet titled `"2 of 3 matched"`; a YouTube link takes today's path; an album link shows `Only Spotify playlist links can be imported`; a private link shows the private/invalid message; the review sheet's "Remove" deletes that entry, "pick another" replaces the entry's track; the new playlist's page has no sync button.
- [ ] **Step 2–4:** Run → FAIL; implement; run the full suite `flutter analyze && flutter test` → clean; all pass except the two known stats timing tests.
- [ ] **Step 5: Commit** `feat: import Spotify playlists from the import dialog`
