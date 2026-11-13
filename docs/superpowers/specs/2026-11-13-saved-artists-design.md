# Saved artists (SON-10) — design

## Intent

Artists you like should be one tap away. Today you can open a YouTube Music
artist page from search, home and the song menu, but you can't keep it, and
the artist name on a playing song or in a playlist isn't tappable. This work
lets you **save** an artist, find them in the **library** next to your
playlists, have them **sync** to your other devices like playlists, and open
an artist page by **tapping the artist's name** wherever a song shows it.

Success: you hear a song, tap the artist name, tap Save, and the artist is
in the library on every device you use.

## Goals

1. **Artist page** (`lib/ui/ytm/artist_page.dart`) keeps what it has:
   - picture and name;
   - Play and Radio;
   - Top songs: 5 shown, with Show all;
   - Albums, Singles, and Fans also like rows.

   Two additions:
   - **Monthly listeners** under the name, e.g. "68M monthly listeners".
     YouTube sends this as `monthlyListenerCount` in the artist header
     (`"68M monthly audience"` in `test/fixtures/innertube/browse_artist.json`).
     When YouTube leaves it out, nothing is shown.
   - **Save button** in the hero actions, next to Play and Radio. It shows
     *Save* when the artist isn't saved and *Saved* (filled icon) when it is.
     Tapping it toggles. An island confirms "Saved to library" or
     "Removed from library".
2. **Library: saved artists, "just like playlists".** Saved artists appear
   as rows in the library list, using the playlist tile's look but with a
   round picture, the name, and "Artist" as the subtitle. Tapping a row
   opens the artist page.
3. **Sync.** Saved artists sync between signed-in devices through the
   existing cloud sync, like playlists.
4. **Tappable artist names** open the artist page from:
   - Now Playing (the artist line under the title);
   - the mini player (phone) and the player bar (desktop);
   - song rows in library playlists and on YouTube Music album and
     playlist pages.

## Non-goals

- No change to the number of top songs, and no separate EPs row. YouTube's
  Singles row already holds EPs.
- No artist pages for local files. They have no YouTube artist.
- No "follow" or subscribe on the user's YouTube account. Saving is
  Songies-only.
- No grid, carousel or other special layout for saved artists. That may
  come later.

## Anti-goals

- Tapping a song row must still play the song. Only the artist name opens
  the artist.
- An older app version on another device must not break or lose data when
  saved-artist rows arrive.

## How it works

### Data: a new synced table `saved_artists`

In `lib/data/tables.dart`, with `SyncColumns`:

| column | type | notes |
|---|---|---|
| `browseId` | text | YouTube Music artist id (`UC…`) |
| `name` | text | as last seen |
| `thumbnailUrl` | text, nullable | as last seen |
| `savedAt` | datetime | for sorting |

- **Row id is deterministic** from the browse id (`artist:<browseId>`). If
  two devices save the same artist, they write the same row, and
  last-write-wins settles it with no duplicates. So `SyncTable.savedArtists`
  does not need the clash rules.
- **Unsave** writes a tombstone (`deleted = true`). Saving again clears it,
  with a new clock.
- **Opening a saved artist's page** refreshes `name` and `thumbnailUrl` when
  they changed (my call), so the library row stays current.
- **Version bumps:**
  - drift `schemaVersion` 10 → 11, with a migration that creates the table
    and its `localSeq` index;
  - `kRowFormat` 10 → 11. Older apps then park the new rows instead of
    failing (`rowFromServer` already returns null for an unknown table or a
    newer format).
- **Sync registration:** add `savedArtists('saved_artists')` to `SyncTable`
  in `lib/sync/sync_row.dart`, plus `info()`, and anything else that
  switches over `SyncTable`.
- **Server:** a new Supabase migration
  (`supabase/migrations/20261113120000_saved_artists.sql`) widens the
  `sync_rows_tbl_rule` check to include `'saved_artists'`. It also updates
  any other place in the SQL that lists the table names (the
  cloud_sync migration lists them twice). The user applies it by hand, as
  with earlier migrations. Note this in `docs/supabase.md`.
- **Repository:** a small `SavedArtistsRepository` (or methods on the
  library repository; the builder decides), with:
  - `watchAll()`, newest saved first;
  - `isSaved(browseId)` as a stream, for the button;
  - `save(YtmArtist)`;
  - `unsave(browseId)`.

### Library list

`lib/ui/library/library_page.dart`:
- Add a filter chip **Artists**.
- **All** shows playlists, then saved artists below them.
- **Artists** shows only saved artists.
- Local, YouTube and Downloaded show playlists only, as today.
- The empty-library state still appears only when there are no playlists and
  no saved artists.

### Monthly listeners

- Parse `monthlyListenerCount` in the artist header parser
  (`lib/innertube/ytm_parse.dart`) into a new nullable field on
  `YtmArtistPage`.
- Keep the number part YouTube sends ("68M") and show it as
  "68M monthly listeners". The user asked for "monthly listeners". YouTube
  now words it "monthly audience", which is the same figure.
- Show it in the hero under the title. `YtmHero` gains an optional subtitle
  line.

### Finding an artist's page from a song

Add one shared lookup: `artistPageFor(song) → browseId?`.

1. If the song already carries artist ids (a `YtmSong`, or a queue item
   built from one), return the first artist that has a browse id.
2. Otherwise, for a library track with `source == 'yt'`, ask YouTube Music
   with the `next` call for its `videoId`, the same call `YtmService.radio`
   makes, and return the playing song's first artist browse id. Cache the
   answer in memory per videoId for the session.
3. Otherwise (a local file, offline, or no answer), return null.

When a name is tapped:
- If the lookup returns a page, open it with `context.goYtmArtist`.
- If it returns null, open Search with the artist name. The stats page
  already does this; reuse its pattern.
- If the lookup takes more than a moment, there is no spinner. The page
  simply opens when the answer arrives.

The same lookup also replaces:
- `statsArtistPageProvider`, which today always ends in Search for library
  tracks because `MenuSong.track(...).artistId` is always null;
- the song menu's **Go to artist** for library YouTube tracks, which today
  isn't offered for them.

For songs with several artists ("A, B & C"), the tap opens the first
artist. This matches Go to artist (my call).

### Tappable artist names in the UI

- **Now Playing, mini player, player bar:**
  - the artist text becomes its own tap target;
  - on desktop it shows the click cursor and an underline on hover;
  - on the mini player the rest of the pill keeps opening Now Playing;
  - when another device is being controlled (remote control), the artist
    text is not tappable (my call: the page would open on this device while
    the music plays elsewhere, which is confusing).
- **Song rows** (`YtmSongsSliver` rows on album/playlist pages, and library
  playlist rows):
  - the artist part of the subtitle is its own tap target;
  - the rest of the row still plays the song;
  - long-press and right-click still open the song menu.

## Testing

- Unit tests:
  - parsing monthly listeners from the fixture;
  - repository save, unsave and re-save, and tombstones;
  - deterministic ids;
  - the sync round trip of a `saved_artists` row;
  - an older format parking a row;
  - the lookup's order of fallbacks, with a fake `next` response.
- Widget tests:
  - the Save button toggling;
  - library filters showing artists;
  - an artist-name tap navigating, and a row tap still playing.
- No emulator. The user tests on their phone and desktop from an APK or
  desktop build.

## Left to the builder

- Exact widget structure, file names, and whether the repository is new or
  part of `LibraryRepository`.
- Icons. Suggested: `Icons.bookmark_add_outlined` and `Icons.bookmark`, or
  `Icons.person_add_alt` and `Icons.how_to_reg`.
- Where the lookup's cache lives.

## Manual steps for the user

- Apply `supabase/migrations/20261113120000_saved_artists.sql` **before
  using any build that has this feature**.
  - Until the migration is applied, `push_rows` refuses `saved_artists` rows
    as `invalidRow`.
  - `CloudSync._pushRows` then halves the page, skips the refused rows (it
    logs "skipped"), and moves the push mark past them.
  - Other tables keep syncing, but the skipped saves never reach the server
    later, unless that artist is saved or unsaved again.
  - Add this as a release-checklist step in `docs/releasing.md`, next to
    step 0.
- Test on phone and desktop:
  - save an artist on one device and see it on the other;
  - unsave it, and see it disappear on the other device.
