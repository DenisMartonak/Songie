# Song Menu Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A song menu with a header, three action tiles and a short list (bottom sheet on phone, floating card at the pointer on desktop), and an Add to playlist sheet with checkboxes that shows and edits where a song lives.

**Architecture:** The menu keeps its entry list and action switch in `showSongMenu`; only its two presenters (`_sheet`, `_popup`) are replaced by one `SongMenuPanel` widget shown in a sheet or an anchored card. Add to playlist becomes a single-song checkbox sheet that reads membership through one new repository query and saves only the difference.

**Tech Stack:** Flutter, Riverpod, drift. Tests: `flutter_test` with `UiHarness` / `uiTest`, `test/helpers/test_db.dart`.

**Spec:** `docs/superpowers/specs/2026-11-15-song-menu-redesign-design.md`

Reference images: menu `/tmp/claude-1000/-home-dencho-Code-Claude-Songie/470b1a6c-a958-4ece-b338-ab2db62b3f98/images/3.png`, Add to playlist `/tmp/claude-1000/-home-dencho-Code-Claude-Songie/470b1a6c-a958-4ece-b338-ab2db62b3f98/images/4.png` (theme colors replace theirs).

Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH` first. Never boot the Android emulator.

## Global Constraints

- Colors only from the theme (`SongiesColors`, `ColorScheme`). Reduced motion as today (`Motion`).
- Every menu action keeps exactly today's availability rules and behavior (room guest, Play on devices, playable YouTube, downloads, artist/album pages, remove from playlist).
- Menu copy: tiles `Queue`, `Playlist`, `Radio`; rows `Play on <device>`, `Add to queue on <device>`, `Go to artist`, `Go to album`, `Download` / `Remove download`, `Remove from this playlist` (error color, below a divider). Star tooltip `Add to Favorites` / `Remove from Favorites`.
- Sheet copy: title `Add to playlist`; footer `None selected` / `1 selected` / `N selected`; button `Save`; search hint `Search playlists`.
- Save island copy: `Added to <name>` / `Added to N playlists`; `Removed from <name>` / `Removed from N playlists`; both → joined with ` · `; nothing changed → no island; failure → `Couldn't save to <name>` (failure kind).
- Keys kept: `songMenu.sheet`, entry keys by action name (`_entryKey`), `addToPlaylist.sheet`, `addToPlaylist.new`, `addToPlaylist.<id>`. New: `songMenu.card`, `songMenu.star`, `songMenu.tile.<action name>`, `addToPlaylist.save`, `addToPlaylist.search`, `addToPlaylist.favorites`, `addToPlaylist.check.<id>`.
- Wide = window width ≥ 840 for the Add to playlist presentation (dialog, max width 480); phone = bottom sheet up to 85 % height. The menu chooses card vs sheet exactly as today (anchor given → card).

## Review Focus

1. **A song that is in a playlist twice**: its box is ticked; unticking + Save removes every copy; leaving it ticked changes nothing. (Task 1 test + Task 2 test.)
2. **Favorites appears once**: the Favorites playlist (`kFavoritesPlaylistId`) is the pinned row only, not also in the list; ticking it stars, unticking un-stars, and the menu's star agrees next time it opens. (Task 2 test.)
3. **Right-click near the bottom-right corner**: the card stays fully on screen. (Task 3 test.)
4. **A YouTube Music result not yet in the library**: Playlist tile stores it first; if storing fails, `Couldn't add that song` shows and no sheet opens. (Task 3 test.)
5. **Followed playlists**: never listed; `removeTrack` refuses them. (Task 1 + Task 2 tests.)

---

### Task 1: Membership query and removing a track from a playlist

**Files:**
- Modify: `lib/library/library_repository.dart` (next to `trackIdsIn`, `removeEntry`)
- Test: the existing library repository test file (`grep -rln "trackIdsIn" test/library`)

**Interfaces:**
- Produces:
  - `Future<Set<String>> playlistIdsContaining(String trackId)` — ids of live playlists with a live entry of `trackId` (Favorites included if starred).
  - `Future<Result<int>> removeTrack(String playlistId, String trackId)` — tombstones every live entry of `trackId` in `playlistId` (the same way `removeEntry` does, via `_tombstoneEntry`), returns how many; read-only error for a followed playlist; `Ok(0)` when none.

- [ ] **Step 1: Write failing tests:** `playlistIdsContaining finds every playlist holding the track` (two playlists + one without → exactly the two; a removed entry doesn't count; a deleted playlist doesn't count); `removeTrack removes every copy` (track added twice → `Ok(2)`, `trackIdsIn` no longer has it, other tracks untouched); `removeTrack refuses a followed playlist` (`Err`, entries unchanged); `removeTrack with nothing to remove is Ok(0)`.
- [ ] **Step 2: Run** `flutter test <that file>` → fail.
- [ ] **Step 3: Implement** both methods with `guardDb` like their neighbors.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(library): which playlists hold a song; remove a song from one (SON-42)`.

### Task 2: Add to playlist sheet with checkboxes

**Files:**
- Modify (rewrite): `lib/ui/library/add_to_playlist_sheet.dart`
- Modify: `lib/ui/widgets/song_menu.dart` (only the call site: pass one track id)
- Test: `test/ui/library/add_to_playlist_sheet_test.dart` (new); update `test/ui/song_menu_test.dart`, `test/ui/island/island_messages_test.dart`, `test/ui/playlists/playlist_sharing_ui_test.dart`, `test/ui/ytm/ytm_song_row_test.dart` where they drive the old sheet.

**Interfaces:**
- Consumes: `playlistIdsContaining`, `removeTrack` (Task 1); `addTracks`, `createPlaylist`; `FavoritesRepository.star/unstar/watchIds`; `playlistsProvider`; `showPlaylistNameDialog`; `PlaylistArt`.
- Produces: `Future<void> showAddToPlaylistSheet(BuildContext context, WidgetRef ref, String trackId)` (was `List<String> trackIds`); `String? playlistSaveMessage({required List<String> added, required List<String> removed})` (pure, top-level, for the island copy; null when both empty).

- [ ] **Step 1: Write failing tests:**
  - `playlistSaveMessage` cases: one added → `Added to Rock`; three added → `Added to 3 playlists`; one removed → `Removed from Rock`; one each → `Added to Rock · Removed from Jazz`; none → null.
  - `boxes start ticked where the song is` (song in `Rock` and starred → `addToPlaylist.check.<rockId>` and favorites checked; `Jazz` unchecked; footer `2 selected`).
  - `Favorites is pinned once` (`addToPlaylist.favorites` exists; no `addToPlaylist.check.favorites` row in the list).
  - `followed playlists are not listed`.
  - `Save adds, removes and stars only what changed` (tick Jazz, untick Rock, untick Favorites → Jazz holds it, Rock doesn't, not starred; Favorites counts as a playlist named `Favorites`, so the island reads `Added to Jazz · Removed from 2 playlists`).
  - `a song twice in Rock: untick + Save removes both` (Review Focus 1).
  - `closing without Save changes nothing`.
  - `+ creates a playlist and shows it ticked` (name dialog → `New one` row ticked; after Save the song is in it).
  - `search filters by name` (type `ro` → only `Rock` row; Favorites row hidden unless it matches).
  - `wide window shows a dialog, phone a sheet` (1000 px → `Dialog` ancestor of `addToPlaylist.sheet`; 400 px → bottom sheet).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** State: `initial` and `ticked` sets of playlist ids (Favorites as `kFavoritesPlaylistId`), loaded on open from `playlistIdsContaining`. Header: title, search `IconButton` (key `addToPlaylist.search`) that swaps the title for a `TextField`, and a round `+` (key `addToPlaylist.new`). Rows: Favorites (accent-colored square tile with a star; key `addToPlaylist.favorites`), then playlists by the existing order minus Favorites and followed ones, each a `Pressable` row (key `addToPlaylist.<id>`) toggling a `Checkbox` (key `addToPlaylist.check.<id>`). Footer: divider, count text, `FilledButton` Save (key `addToPlaylist.save`). Save: for each newly ticked → `addTracks` (Favorites → `star`), for each unticked → `removeTrack` (Favorites → `unstar`); collect names; show `playlistSaveMessage`; any failure shows `Couldn't save to <name>` for the first failing one and still applies the others.
- [ ] **Step 4: Run** the new and updated tests, then the full `flutter test` and `flutter analyze` → pass.
- [ ] **Step 5: Commit** `feat(playlists): add to several playlists with checkboxes (SON-42)`.

### Task 3: Song menu panel (sheet and card)

**Files:**
- Modify: `lib/ui/widgets/song_menu.dart` (replace `_sheet` and `_popup` with `SongMenuPanel` + two presenters; keep `showSongMenu`'s entry building and action switch)
- Test: `test/ui/song_menu_test.dart` (and other tests that open the menu: `grep -rln "Song options\|songMenu\." test`)

**Interfaces:**
- Consumes: `showAddToPlaylistSheet(context, ref, String trackId)` (Task 2); `ProfileArt({String? url, String? artworkRef, required String seed, required double size, double? radius})` from `lib/ui/profile/profile_stats.dart` for the cover (move it to `lib/ui/widgets/profile_art.dart` and re-export if importing `ui/profile` from `ui/widgets` creates a cycle).
- Produces: `class SongMenuPanel extends StatelessWidget { const SongMenuPanel({required MenuSong song, required bool favorite, required List<_Entry> entries, required Set<SongMenuAction> disabled, required ValueChanged<_Entry> onChosen}); }` (private types may stay private in the same file).

- [ ] **Step 1: Write/adjust failing tests:**
  - `header shows cover, title, artist and the star` (`songMenu.star` icon filled when favorite; tapping it toggles Favorites and closes the menu).
  - `tiles: Queue, Playlist, Radio for a playable YouTube song` (`songMenu.tile.addToQueue`, `songMenu.tile.addToPlaylist`, `songMenu.tile.startRadio`); `a local file has two tiles` (no radio tile).
  - `a room guest's local file greys the Queue tile` (disabled, as today's row).
  - `Play on <device> and Add to queue on <device> are rows under the tiles`.
  - `Remove from this playlist sits below a divider in the error color`.
  - `right-click opens a card at the pointer` (`songMenu.card` near the tap point); `bottom-right right-click keeps the card on screen` (Review Focus 3: card rect inside the screen at 1280×800, tap at (1270, 790)).
  - `long-press opens the sheet` (`songMenu.sheet`).
  - `Playlist tile on an unstored YouTube Music song stores it, then opens the sheet; a store failure shows "Couldn't add that song"` (Review Focus 4).
  - Existing action tests keep passing (each action still does the same thing).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** Tile entries = `addToQueue`, `addToPlaylist`, `startRadio` (those present, in that order); `favorite` becomes the header star; `removeFromPlaylist` goes below a `Divider`; all others are list rows in today's order. Tiles: equal-width `Expanded` cards (`colors.surface`-tone, theme radius, icon above label). Card: a `PopupRoute` (or `showGeneralDialog` with transparent barrier) laying out `SongMenuPanel` (width 360, max height 80 % of screen, scrollable) at the anchor with `CustomSingleChildLayout`, flipped/clamped to stay inside the overlay; same open/close animation style as today. Sheet: today's `showModalBottomSheet` setup plus a drag handle.
- [ ] **Step 4: Run** the full `flutter test` and `flutter analyze` → pass.
- [ ] **Step 5: Builds:** `flutter build linux`, then `flutter build apk --debug`, then `cd android && ./gradlew --stop`.
- [ ] **Step 6: Commit** `feat(ui): song menu with header, tiles and a card on desktop (SON-42)`.
