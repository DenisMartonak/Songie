# Favorites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A built-in, synced, downloadable Favorites playlist with a one-tap star on the playing song and on every song row.

**Architecture:** Favorites is an ordinary `playlists` row with the fixed id `favorites`, and each favorite is an ordinary entry with the deterministic id `fav-<trackId>`. Fixed ids make two devices' Favorites the same rows, so sync's last-writer-wins settles star/un-star per song with no new protocol; the sync applier and merger get three small Favorites rules (never deleted or renamed, one entry per song, no conflict dialog). The UI reads one `favoriteIdsProvider` (a `Set<String>` of track ids) and renders a shared `FavoriteStar` widget.

**Tech Stack:** Flutter 3.47.8 / Dart, Riverpod, drift, the Plan 10 sync engine.

**Spec:** `docs/superpowers/specs/2026-11-01-favorites-design.md`

## Global Constraints

- Playlist id `favorites` (`kFavoritesPlaylistId`), name `Favorites`, `source: 'local'`. Entry id `fav-<trackId>`.
- Favorites can't be renamed or deleted; hide those items for it everywhere.
- A new star lands first (position before the current first entry); user reordering still works and syncs.
- Starring a song not in the library stores it first via `YtTrackStore.upsert`, as Add to playlist does.
- Star: `Icons.star_outline_rounded` (not a favorite, muted colour) / `Icons.star_rounded` (favorite, accent colour). Tooltip `Add to Favorites` / `Remove from Favorites`. Menu items use the same labels.
- Nothing is sent to YouTube.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`. The two `stats_repository_test.dart` "under 500 ms" tests fail only under full-suite load; not regressions.

## Review Focus

- Star → un-star → star again on one device: one live entry, at the top. → Task 1.
- Device A stars song S while device B un-stars S, then they sync: the later change wins on both, no dialog. → Task 2.
- An old (1.1.x) peer sends Favorites deleted or renamed: after applying, Favorites is live and named `Favorites` again, with a fresh stamp so it propagates back. → Task 2.
- An old peer adds S to Favorites under a random entry id while `fav-S` exists: one live entry remains. → Task 2.
- Starring a YouTube Music search result that isn't in the library and has no network: the star stays outlined and a "Couldn't add that song" snack shows; nothing half-written. → Task 4.

---

### Task 1: Favorites in the library repository

**Files:**
- Create: `lib/library/favorites.dart`
- Modify: `lib/library/library_repository.dart` (playlist summaries order; `renamePlaylist`/`deletePlaylist` refuse Favorites)
- Modify: `lib/main.dart` (call `ensureFavorites` at startup)
- Test: `test/library/favorites_test.dart`

**Interfaces:**
- Produces:
  - `const kFavoritesPlaylistId = 'favorites';`, `String favoriteEntryId(String trackId) => 'fav-$trackId';`
  - `class FavoritesRepository { FavoritesRepository(AppDatabase db, SyncStamp stamp); Future<Result<void>> ensureFavorites(); Future<Result<void>> star(String trackId); Future<Result<void>> unstar(String trackId); Future<Result<bool>> toggle(String trackId); Stream<Set<String>> watchIds(); }` — `toggle` returns the new state (true = now a favorite).
  - `star` writes entry `fav-<trackId>` live (insert, or un-delete) with `position = keyBetween(null, <current first live position>)`, fresh stamp; a no-op when already live. `unstar` marks it deleted with a fresh stamp.
  - `ensureFavorites` creates the playlist row if missing; if it exists deleted or renamed, writes it back live as `Favorites` with a fresh stamp.
  - `watchPlaylistSummaries` puts `favorites` first, others in their current order.

- [ ] **Step 1: Write the failing tests** (`test/library/favorites_test.dart`, in-memory db via `testDb()`)
  - `ensureFavorites` on an empty db → playlist `favorites` named `Favorites`, live; calling again changes nothing (same clock).
  - `ensureFavorites` when the row is deleted or named `Faves` → live and `Favorites`, clock changed.
  - `star('a')` then `star('b')` → live entries `fav-a`, `fav-b`, with `fav-b`'s position sorting before `fav-a`'s.
  - `star('a')` twice → one entry, clock unchanged by the second call.
  - `star('a')`, `unstar('a')`, `star('a')` → one live entry `fav-a`, first in order.
  - `toggle('a')` → `Ok(true)`, again → `Ok(false)`.
  - `watchIds()` emits `{}`, then `{'a'}` after `star('a')`.
  - `renamePlaylist('favorites', 'x')` and `deletePlaylist('favorites')` → `Err` (`FailureKind.invalidInput`), row unchanged.
  - `watchPlaylists()` lists Favorites first even when another playlist was created earlier.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/library/favorites_test.dart`. Expected: FAIL (`favorites.dart` missing).

- [ ] **Step 3: Implement** `lib/library/favorites.dart` and the repository changes; in `main.dart` call `FavoritesRepository(db, stamp).ensureFavorites()` right after the library opens, and provide it as `favoritesRepositoryProvider` (overridden in `main.dart`, `_unwired` default) plus `favoriteIdsProvider = StreamProvider<Set<String>>` watching `watchIds()`. Add both overrides to `test/helpers/ui_harness.dart`.

- [ ] **Step 4: Run the tests.** Run: `flutter test test/library`. Expected: PASS.

- [ ] **Step 5: Commit** `feat: a built-in Favorites playlist`

### Task 2: Sync rules for Favorites

**Files:**
- Modify: `lib/sync/row_applier.dart` (`_claimPlaylist`, `_claimEntry`)
- Modify: `lib/sync/merger.dart` (`merge`: Favorites rows never group into a clash)
- Test: `test/sync/row_applier_test.dart`, `test/sync/merger_test.dart` (extend)

**Interfaces:**
- Consumes: `kFavoritesPlaylistId`, `favoriteEntryId` (Task 1).
- Produces: no new API.
  - `_claimPlaylist`: an incoming `favorites` row that is deleted or not named `Favorites` is applied live and named `Favorites`, then restamped so the fix propagates.
  - `_claimEntry`: Favorites entries follow the live-YouTube rule (one live entry per song; `_best` picks the winner, preferring id `fav-<trackId>` when it is among the candidates).
  - `Merger.merge`: rows whose playlist is `favorites` go to `settled` via `_settle` (last writer wins), never to a `PlaylistClash`.

- [ ] **Step 1: Write the failing tests**
  - Applier: apply a `favorites` playlist row with `deleted: true` → stored row live, name `Favorites`, clock newer than the incoming one.
  - Applier: apply one named `Faves` → stored name `Favorites`.
  - Applier: with `fav-s` live, apply a live entry `e-random` (playlist `favorites`, track `s`) → exactly one live entry for `s`, and it is `fav-s`.
  - Merger: mine has `fav-s` live (clock older), theirs has `fav-s` deleted (clock newer), and both sides changed it → `clashes` empty, settled row deleted.
  - Merger: an ordinary playlist with the same shape still yields a clash (unchanged behaviour).

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/sync`. Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run.** Run: `flutter test test/sync test/library`. Expected: PASS.

- [ ] **Step 5: Commit** `feat: Favorites sync: never deleted, one entry per song, no conflict dialog`

### Task 3: The star widget, player bar and Now Playing

**Files:**
- Create: `lib/ui/widgets/favorite_star.dart`
- Modify: `lib/ui/shell/player_bar.dart` (`_NowPlaying`: star after the title column)
- Modify: `lib/ui/now_playing/now_playing_header.dart` (star beside the title)
- Test: `test/ui/favorite_star_test.dart`

**Interfaces:**
- Consumes: `favoriteIdsProvider`, `favoritesRepositoryProvider` (Task 1).
- Produces: `class FavoriteStar extends ConsumerWidget { const FavoriteStar({required MenuSong song, double size = 20, super.key}); }` — filled when `song.track?.id` is in `favoriteIdsProvider`; tap calls `toggleFavorite(context, ref, song)`.
  - `Future<void> toggleFavorite(BuildContext context, WidgetRef ref, MenuSong song)` in the same file: resolves the track (stored via `YtTrackStore.upsert` for a `MenuSong.ytm`; on failure shows `Couldn't add that song` and returns), then `FavoritesRepository.toggle`.
  - For a `MenuSong.ytm`, "is favorite" looks the song up by video id (`YtTrackStore.find`) through a small `FutureProvider.family` so rows of songs already in the library show filled.

- [ ] **Step 1: Write the failing tests** (`UiHarness`)
  - A `FavoriteStar` for a library track shows `Icons.star_outline_rounded` with tooltip `Add to Favorites`; tapping it → `Icons.star_rounded`, tooltip `Remove from Favorites`, and the db has live `fav-<id>`.
  - Tapping again → outline, entry deleted.
  - Player bar while playing shows a `FavoriteStar` for the current track (find by type within `PlayerBar`); tapping it stars the playing song.

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Run: `flutter test test/ui/favorite_star_test.dart test/ui/shell_test.dart test/ui/player_bar_menu_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: a star on the playing song`

### Task 4: Stars on every song row, and the song menu

**Files:**
- Modify: `lib/ui/search/search_page.dart` (`_SongRow`), `lib/ui/playlist/playlist_page.dart` (`_TrackRow`), `lib/ui/ytm/ytm_song_row.dart` (`YtmSongRow`, used by Home shelves, album and artist pages), `lib/ui/now_playing/now_playing_queue.dart` (queue rows), `lib/ui/stats/stats_page.dart` (`_SongRow`)
- Modify: `lib/ui/widgets/song_menu.dart` (new `SongMenuAction.favorite` item, first after Add to playlist)
- Test: extend `test/ui/song_menu_test.dart`, and one row test per page file's existing test

**Interfaces:**
- Consumes: `FavoriteStar`, `toggleFavorite` (Task 3).
- Produces: `SongMenuAction.favorite`, labelled `Add to Favorites` / `Remove from Favorites` by current state.

- [ ] **Step 1: Write the failing tests**
  - Each of the five row kinds shows exactly one `FavoriteStar` per row, placed just before its ⋯ button.
  - Song menu for a non-favorite shows `Add to Favorites`; choosing it stars the song; the menu then shows `Remove from Favorites`.
  - Starring a `MenuSong.ytm` whose `YtTrackStore.upsert` fails (fake store returning `Err`) → star stays outlined, snack `Couldn't add that song`, no `fav-` entry.
  - On the Favorites playlist page, un-starring a row removes that row.

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Run: `flutter test test/ui`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: stars on every song row and in the song menu`

### Task 5: Favorites in the library and on its page

**Files:**
- Modify: `lib/ui/library/library_page.dart` (star tile for Favorites)
- Modify: `lib/ui/playlist/playlist_page.dart` (star header art; hide Rename and Delete for Favorites)
- Modify: `lib/ui/library/add_to_playlist_sheet.dart` (Favorites listed first with its star)
- Modify: `docs/manual-test-checklist.md` (a Favorites section: star on bar, rows, menu; sync between two devices; download the playlist)
- Test: extend `test/ui/library_page_test.dart`, `test/ui/playlist_page_test.dart` (check names with `ls test/ui`)

- [ ] **Step 1: Write the failing tests**
  - Library: the first playlist tile is `Favorites` and shows `Icons.star_rounded` instead of a cover.
  - Favorites page: the page menu has no `Rename` and no `Delete`; the download switch is present.
  - An ordinary playlist page still has `Rename` and `Delete`.

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite.** Run: `flutter analyze && flutter test`. Expected: clean; all pass except the two known stats timing tests.
- [ ] **Step 5: Commit** `feat: Favorites pinned in the library with a star`
