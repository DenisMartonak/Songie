# Saved Artists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save YouTube Music artists to the library, synced across devices.
Show monthly listeners on the artist page. Make artist names tappable
wherever a song is shown.

**Architecture:**
- A new synced drift table, `saved_artists`, whose row id is deterministic
  from the artist's browse id. It gets its own small repository and is
  registered in `SyncTable`, plus a server migration.
- One shared resolver, `ArtistLookup`, turns a `Track` or `YtmSong` into an
  artist browse id. For library YouTube tracks it uses the `next` call.
- One `ArtistLink` widget makes artist text tappable. It is used in Now
  Playing, the mini player, the player bar, and song rows.

**Tech Stack:** Flutter, Riverpod, drift (SQLite), Supabase (Postgres) cloud
sync, InnerTube (YouTube Music) client.

**Spec:** `docs/superpowers/specs/2026-11-13-saved-artists-design.md`

## Global Constraints

- **Versions:** drift `schemaVersion` 10 → **11**; `kRowFormat` 10 → **11**
  (`lib/sync/cloud/cloud_remote.dart`).
- **Wire name:** `saved_artists`.
- **Row id:** `artist:<browseId>`.
- **Copy, exactly:**
  - button: `Save` / `Saved`;
  - islands: `Saved to library` / `Removed from library`;
  - library chip: `Artists`;
  - row subtitle: `Artist`;
  - listeners line: `<count> monthly listeners`, e.g. `68M monthly listeners`.
- **Server migration:** `supabase/migrations/20261113120000_saved_artists.sql`.
- **No emulator:** run `flutter test` and `flutter analyze` only. The user
  tests on their devices.
- **Commits:** end each message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Unrelated change:** leave the stray whitespace change in
  `lib/ui/shell/mini_player.dart` out of commits unless Task 6 touches
  that file anyway.

## Review Focus

1. **Lookup fails** (offline, or a `next` error): tapping an artist name
   must still do something. It falls back to Search with the name. The
   Task 4 test pins this.
2. **Several artists, or none with a browse id** (e.g. "Various Artists"
   without links): `ArtistLookup` returns the first one *with* an id, or
   null. It never crashes on an empty list. Task 4.
3. **Save, unsave, re-save** on one device must leave exactly one row, not
   deleted. Re-saving must not keep the tombstone. Task 2.
4. **A pulled `saved_artists` row with a newer `fmt`** is parked, not
   applied, and doesn't break the pull. Task 3.
5. **Tapping a song row outside the artist text** still plays the song.
   Tapping the artist text does not play it. Task 6.

---

### Task 1: Monthly listeners on the artist page

**Files:**
- Modify: `lib/innertube/ytm_models.dart` (`YtmArtistPage`)
- Modify: `lib/innertube/ytm_parse.dart` (`parseArtistPage`, ~line 663)
- Modify: `lib/ui/ytm/artist_page.dart`
- Test: `test/innertube/ytm_browse_test.dart` (`group('artist')`),
  `test/ui/ytm/artist_page_test.dart`

**Interfaces:**
- Produces: `YtmArtistPage.monthlyListeners` (`String?`), the count part
  only, e.g. `'68M'`.

- [ ] **Step 1: Write the failing tests**
  - Parser test: in `group('artist')`, after parsing `browse_artist`, add
    `expect(page.monthlyListeners, '68M');`.
  - Second parser case: strip `monthlyListenerCount` from a copy of the
    fixture JSON, then
    `expect(page.monthlyListeners, isNull);`.
  - Widget test in `artist_page_test.dart`: a page with
    `monthlyListeners: '68M'` shows
    `find.text('68M monthly listeners')`. With `null`, nothing matching
    `monthly listeners` is shown.
- [ ] **Step 2:** Run
  `flutter test test/innertube/ytm_browse_test.dart test/ui/ytm/artist_page_test.dart`.
  Expected: FAIL (no such field).
- [ ] **Step 3: Implement**
  - Add `this.monthlyListeners` to `YtmArtistPage`.
  - In `parseArtistPage`, read
    `_runsText(_runs(dig(header, ['monthlyListenerCount'])))`. Keep the
    text before the first space (`"68M monthly audience"` → `"68M"`); an
    empty result becomes null.
  - In `ArtistPage`, pass
    `subtitle: page.monthlyListeners == null ? null : '${page.monthlyListeners} monthly listeners'`
    to `YtmHero` (it already has `subtitle`).
- [ ] **Step 4:** Re-run the tests from Step 2. Expected: PASS.
- [ ] **Step 5:** Commit:
  `feat(artist): show monthly listeners (SON-10)`.

### Task 2: `saved_artists` table and repository

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart`, regenerate
  `lib/data/database.g.dart`
- Create: `lib/library/saved_artists_repository.dart`
- Modify: `lib/providers.dart`
- Test: `test/library/saved_artists_repository_test.dart`,
  `test/data/migration_test.dart`

**Interfaces:**
- Consumes: `SyncStamp.next({String? id})` → `Stamp`, and `YtmArtist`.
- Produces:
  - drift class `SavedArtists`, data class `SavedArtist`, with columns
    `browseId` (text), `name` (text), `thumbnailUrl` (text?), `savedAt`
    (datetime), plus `SyncColumns`, and index `saved_artists_local_seq`
    on `localSeq`;
  - `String savedArtistId(String browseId) => 'artist:$browseId';`
  - `class SavedArtistsRepository`, constructor
    `SavedArtistsRepository(AppDatabase db, SyncStamp stamp)`, with:
    - `Stream<List<SavedArtist>> watchAll()`: not deleted, newest
      `savedAt` first;
    - `Stream<bool> watchIsSaved(String browseId)`;
    - `Future<Result<void>> save(YtmArtist artist)`;
    - `Future<Result<void>> unsave(String browseId)`;
    - `Future<void> refresh(YtmArtist artist)`: updates name and
      thumbnail only if the artist is saved and either one changed; a new
      stamp only then;
  - `final savedArtistsRepositoryProvider`, and
    `final savedArtistsProvider = StreamProvider<List<SavedArtist>>`.

- [ ] **Step 1: Write the failing tests**, using `testDb()` and a real
  `SyncStamp` (see how `test/library/library_repository_test.dart` builds
  one):
  - `save then watchAll has one row with id artist:UC1 and the name`.
  - `save, unsave, save leaves one row, deleted false, a newer clock each time`.
  - `unsave hides it from watchAll and watchIsSaved emits false`.
  - `refresh of an unsaved artist writes nothing`.
  - `refresh with the same name and thumbnail keeps the clock`.
  - Migration test: open a schema-10 database and upgrade to 11; the
    `saved_artists` table exists. Follow the existing pattern in
    `migration_test.dart`.
- [ ] **Step 2:** Run
  `flutter test test/library/saved_artists_repository_test.dart test/data/migration_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement**
  - Add the table to `@DriftDatabase(tables: [...])`.
  - Set `schemaVersion => 11`.
  - Add
    `if (from < 11) { await m.createTable(savedArtists); await m.createIndex(savedArtistsLocalSeq); }`.
  - Run `dart run build_runner build --delete-conflicting-outputs`.
  - Repository writes use `insertOnConflictUpdate` with a stamp from
    `_stamp.next(id: savedArtistId(browseId))`, as in
    `ThemeRepository` (`lib/theme/theme_repository.dart:241`).
  - Unsave writes the same row with `deleted: true`.
  - Wrap writes the way `ThemeRepository` does (`db_guard.dart`).
- [ ] **Step 4:** Re-run the tests from Step 2. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(library): saved artists table (SON-10)`.

### Task 3: Sync `saved_artists`

**Files:**
- Modify: `lib/sync/sync_row.dart`, `lib/sync/cloud/cloud_remote.dart`
  (`kRowFormat = 11`), and every exhaustive `switch` over `SyncTable` that
  `flutter analyze` flags
- Create: `supabase/migrations/20261113120000_saved_artists.sql`
- Modify: `docs/supabase.md`, `docs/releasing.md`
- Test: `test/sync/sync_row_test.dart`, `test/sync/cloud/` (the existing
  `rowFromServer` / pull test file)

**Interfaces:**
- Produces: `SyncTable.savedArtists` with wire name `'saved_artists'`,
  last in the enum. `clashes` stays false for it.

- [ ] **Step 1: Write the failing tests**
  - `a saved_artists row round-trips through toInsertable and the change feed`:
    follow the existing per-table case in `sync_row_test.dart`.
  - `rowFromServer parks a saved_artists row with fmt 12` gives
    `PulledRow.row == null`.
  - `rowFromServer reads a saved_artists row with fmt 11`.
- [ ] **Step 2:** Run `flutter test test/sync`. Expected: FAIL.
- [ ] **Step 3: Implement**
  - Add the enum value and `info()` arm, and set `kRowFormat = 11`.
  - SQL migration:
    - drop and re-add `sync_rows_tbl_rule` with `'saved_artists'` added;
    - `create or replace` `push_rows`, with the same body as in
      `20261106120000_cloud_sync.sql` but `'saved_artists'` added to its
      `tbl` list (line ~133);
    - grep both earlier migrations (`cloud_sync`, `listen_together`) for
      any other list of the eight names and update those too.
  - `docs/supabase.md`: add the new migration to the apply list.
  - `docs/releasing.md`: next to step 0, add a step: "apply pending
    Supabase migrations before tagging; the server refuses rows of tables
    it doesn't know, and refused rows are skipped for good."
- [ ] **Step 4:** Run `flutter test test/sync && flutter analyze`.
  Expected: PASS, no issues.
- [ ] **Step 5:** Commit: `feat(sync): sync saved artists (SON-10)`.

### Task 4: `ArtistLookup` and opening an artist

**Files:**
- Create: `lib/ui/ytm/artist_lookup.dart`
- Modify: `lib/innertube/ytm_service.dart` (only if a lighter call than
  `radio` is wanted; otherwise none)
- Modify: `lib/ui/stats/stats_page.dart` (replace
  `statsArtistPageProvider` and `_open`)
- Modify: `lib/ui/widgets/song_menu.dart` (Go to artist for library YT
  tracks)
- Modify: `test/helpers/fake_ytm.dart` (let `FakeYtmService.radio` return
  a configured `YtmRadio` or failure)
- Test: `test/ui/ytm/artist_lookup_test.dart`, `test/ui/stats_page_test.dart`,
  `test/ui/song_menu_test.dart`

**Interfaces:**
- Consumes: `YtmService.radio(String videoId)` →
  `Future<Result<YtmRadio>>`, whose `current` is a `YtmSong?` with
  `artists`; `Track` (`source`, `ytVideoId`, `artist`).
- Produces:
  - `String? firstArtistId(List<YtmArtistRef> artists)`;
  - `class ArtistLookup`, constructor `ArtistLookup(YtmService ytm)`, with
    `Future<String?> forTrack(Track t)`:
    - `source != 'yt'` or no `ytVideoId` → null;
    - otherwise `radio(ytVideoId)`, then `firstArtistId(current.artists)`;
    - the answer (including null) is cached per videoId, but an `Err` is
      not cached;
  - `final artistLookupProvider = Provider<ArtistLookup>`;
  - `Future<void> openArtist(BuildContext context, WidgetRef ref, {String? browseId, Track? track, required String name})`:
    - a `browseId` wins;
    - otherwise `artistLookup.forTrack(track)`;
    - if it finds an id → `context.goYtmArtist(id)`;
    - if not → Search for `name`, using the stats page's code (set
      `searchQueryProvider`, `goTab` to the Search branch, or
      `router.go('/search')`), moved here.

- [ ] **Step 1: Write the failing tests**
  - `forTrack of a local track is null without calling YouTube`.
  - `forTrack of a yt track returns the first artist with a browseId`:
    artists `[ref(no id), ref('UC2'), ref('UC3')]` → `'UC2'`.
  - `forTrack caches: two calls, one radio request`.
  - `forTrack after an Err tries again next time`.
  - Widget: `openArtist with no id found opens Search with the name`.
  - Stats: `tapping a top artist whose song is a yt track opens the artist page`.
  - Song menu: `a library yt track's menu offers Go to artist`.
- [ ] **Step 2:** Run
  `flutter test test/ui/ytm/artist_lookup_test.dart test/ui/stats_page_test.dart test/ui/song_menu_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement**
  - Build `ArtistLookup` and `openArtist` as specified above.
  - Stats `_ArtistRow._open` becomes
    `openArtist(context, ref, track: <its sample track>, name: artist.name)`.
    Delete `statsArtistPageProvider`.
  - Song menu: show Go to artist when `artistId != null` **or** the track
    is a yt library track. Route it through `openArtist`.
- [ ] **Step 4:** Re-run the tests from Step 2. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(artist): find an artist's page from any song (SON-10)`.

### Task 5: Save button and library section

**Files:**
- Modify: `lib/ui/ytm/artist_page.dart`
- Modify: `lib/ui/library/library_page.dart`
- Test: `test/ui/ytm/artist_page_test.dart`, `test/ui/library_page_test.dart`

**Interfaces:**
- Consumes: Task 2 `savedArtistsRepositoryProvider` and
  `savedArtistsProvider`; `goYtmArtist`.

- [ ] **Step 1: Write the failing tests**
  - `Save on an unsaved artist saves it and shows "Saved to library"`.
    The button changes to `Saved` (key `ytm.save`).
  - `Saved tapped again unsaves and shows "Removed from library"`.
  - `opening a saved artist whose name changed refreshes the row`.
  - Library: `All lists playlists then saved artists`, matched by finding
    both `Artist` subtitles after the playlist rows.
  - Library: `Artists chip shows only saved artists`.
  - Library: `Local chip hides saved artists`.
  - Library: `tapping a saved artist row opens its page`.
  - Library: `no playlists but a saved artist does not show the empty state`.
- [ ] **Step 2:** Run
  `flutter test test/ui/ytm/artist_page_test.dart test/ui/library_page_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement**
  - **Artist page:** add a `YtmHeroAction` with key `ytm.save`.
    - Icon: `Icons.bookmark_add_outlined` when unsaved, `Icons.bookmark`
      when saved.
    - It watches `watchIsSaved` and shows the islands via `Islands.of`.
    - Call `refresh(page.artist)` once when the page loads.
  - **Library:** add `_Filter.artists('Artists', null)`, placed after
    YouTube.
    - Artist rows reuse `_PlaylistTile`'s look, with a round
      `YtmArtwork(thumbnailUrl, seed: browseId, circle: true)` and the
      subtitle `Artist`.
    - Key: `library.artist.<browseId>`.
- [ ] **Step 4:** Re-run the tests from Step 2. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(library): save artists and list them (SON-10)`.

### Task 6: Tappable artist names

**Files:**
- Create: `lib/ui/widgets/artist_link.dart`
- Modify:
  - `lib/ui/now_playing/now_playing_page.dart` (`_TitleAndArtist`, ~843);
  - `lib/ui/shell/mini_player.dart` (`_Titles`, ~296);
  - `lib/ui/shell/player_bar.dart` (~138);
  - `lib/ui/playlist/playlist_page.dart` (~1264);
  - `lib/ui/ytm/ytm_song_row.dart`, and `YtmTile` in
    `lib/ui/ytm/ytm_result_tiles.dart` if it needs to accept a subtitle
    widget.
- Test: `test/ui/widgets/artist_link_test.dart`,
  `test/ui/now_playing_test.dart`, `test/ui/shell/` (mini player),
  `test/ui/player_bar_test.dart`, `test/ui/playlist_page_test.dart`,
  `test/ui/ytm/ytm_song_row_test.dart`

**Interfaces:**
- Consumes: Task 4 `openArtist`.
- Produces:
  `ArtistLink({required String text, String? browseId, Track? track, bool enabled = true, TextStyle? style, int maxLines = 1, Key? key})`.
  - It shows `text` with `style`, ellipsized.
  - When enabled, a tap calls
    `openArtist(context, ref, browseId: browseId, track: track, name: <first artist name>)`.
    The first artist name is `text` split on `', '`, `' & '`, `' feat. '`,
    taking the first part.
  - On desktop it shows `SystemMouseCursors.click` and an underline on
    hover.
  - Its gesture must win over the parent row's tap (wrap it in its own
    `GestureDetector` with `behavior: HitTestBehavior.opaque`).

- [ ] **Step 1: Write the failing tests**
  - `ArtistLink tap with a browseId navigates to the artist`.
  - `ArtistLink disabled does nothing on tap`.
  - `YtmSongRow: tapping the artist opens the artist and does not play`.
  - `YtmSongRow: tapping the title plays`.
  - Playlist page: `tapping a track's artist opens the artist; tapping its title plays`.
  - Now Playing: `tapping the artist opens the artist page`.
  - Player bar: `tapping the artist opens the artist page`.
  - Mini player: `tapping the artist opens the artist page; tapping the rest opens Now Playing`.
  - Mini player: `while controlling another device the strip text is not tappable`.
- [ ] **Step 2:** Run the listed test files. Expected: FAIL.
- [ ] **Step 3: Implement**
  - Swap each artist `Text` for `ArtistLink`, keeping today's style and
    keys.
  - `YtmSongRow` passes `browseId: firstArtistId(song.artists)`. The
    album part stays plain text after the link.
  - Library and now-playing sites pass `track:`.
  - In the mini player, `enabled: link == null`. In the player bar and
    Now Playing, disable it when the same remote-control state is active
    (find how those widgets learn it, as the mini player's `link` does).
- [ ] **Step 4:** Run `flutter test && flutter analyze`. Expected: all
  pass, no issues.
- [ ] **Step 5:** Commit: `feat(artist): tap an artist name to open their page (SON-10)`.

### Task 7: Finish

- [ ] Run `flutter test` and `flutter analyze`. Build the APK with
  `flutter build apk --release` and the Linux desktop app with
  `flutter build linux`. Both must succeed.
- [ ] Add a short manual checklist to the SON-10 Linear issue as a comment:
  - apply the migration;
  - save on phone and see it on desktop;
  - unsave;
  - tap artists in Now Playing, the mini player, the player bar, a
    playlist, and an album;
  - check monthly listeners.
- [ ] Move SON-10 to In Review.
