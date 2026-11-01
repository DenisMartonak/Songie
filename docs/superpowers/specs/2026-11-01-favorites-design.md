# Favorites — design

Date: 2026-11-01. Status: draft for approval. Roadmap item 2 of 6 (after the
desktop player-bar right-click menu; before the equalizer, crossfade,
Android Auto and Spotify import).

## Why

The user wants a one-tap way to keep songs they love, like Spotify's old
heart: a star on the song, and every starred song in one place they can play
and download.

## What the user decided

- A built-in playlist called **Favorites**, shown with a **star** icon.
- Starring a song adds it to Favorites; un-starring removes it.
- Favorites can be **downloaded** like any playlist.
- The star appears on the **playing song** and on **every song row**.

## Behaviour

### The Favorites playlist

- Pinned at the top of the library's playlist list, with a star where other
  playlists show their cover (playlist page header too).
- Plays, shuffles and downloads exactly like any playlist (same page, same
  download switch, same menus where they apply).
- *(Builder's call, accepted by the user in chat as a guess:)* it can't be
  renamed or deleted (those menu items are hidden for it), and the newest
  favorite is at the top.
- *(Builder's call:)* "newest at the top" is where a new star lands, not a
  locked sort: the user can still drag songs into their own order, and that
  order syncs like any playlist's. Un-starring and starring again puts the
  song back at the top.
- *(Builder's call:)* a playlist the user already made called "Favorites"
  (or similar) is left alone: Songies never rewrites the user's own
  playlists. The built-in one is told apart by its star. The user can move
  songs across and delete their old one if they like.
- It is never empty-deleted and exists on every install from the start, so
  the star always has somewhere to go.

### The star

- **Where:** next to the playing song's title in the desktop player bar; on
  the phone's Now Playing screen next to the title; and on every song row:
  search results, playlist pages (Favorites itself included), Home shelves,
  album and artist pages, the queue, and the stats page's top songs.
- **Look:** outlined when the song isn't a favorite, filled (accent colour)
  when it is. One tap toggles it. It never opens anything.
- **Songs not yet in the library** (a YouTube Music search result or shelf
  song): starring adds the song to the library first, exactly as Add to
  playlist does today, then to Favorites.
- **The song menu** also gets "Add to Favorites" / "Remove from Favorites"
  *(builder's call, accepted by the user as a guess)*.
- Un-starring from inside the Favorites page removes the row from that page
  at once.

### Sync and account

- Favorites syncs to the user's other devices like any playlist, so a star
  set on the phone shows on the PC after a sync.
- Nothing is sent to the user's YouTube account (no YouTube "like"),
  matching how Songies treats the account today.

## Constraints

- The existing data model: `Playlists` (with `SyncColumns`), playlist
  entries, the `LibraryRepository` methods (`addTracks`, `removeEntry`,
  `createPlaylist`), the sync engine (Plan 10), and playlist downloads
  (`setPlaylistDownload`).
- Two devices that each created their own built-in Favorites before syncing
  must end up with **one** Favorites holding both sets of songs, never two
  built-in Favorites.
- *(Builder's call:)* Favorites never raises the sync conflict dialog. Both
  devices' stars are kept (union); when one device starred and the other
  un-starred the same song, the later change wins. "Keep both" can't apply.
- *(Builder's call:)* the user's devices are expected to run the same
  version. If a device still on 1.1.x deletes or renames Favorites (it sees
  an ordinary playlist), the updated device undoes that when it syncs:
  Favorites comes back with its name and songs. Duplicate entries an old
  device adds are collapsed to one.
- A song is a favorite at most once (starring twice can't add it twice; a
  sync merge must not leave duplicates in Favorites).
- Flutter 3.47.8, Riverpod, drift; tests follow the repo's habits (fake
  backends, in-memory database, widget tests through `UiHarness`).

## Non-goals

- Liking songs on YouTube, or importing YouTube likes.
- More than one favorites list, or ratings.
- A star on the phone's mini player (only Now Playing and rows on phone).

## Left to the builder

- How Favorites is marked in the data (a fixed playlist id, a new column, or
  a kind), as long as the "one Favorites after sync" and "no duplicates"
  constraints hold. Whether that needs a schema migration.
- Exact placement and size of the star in each row, matching each row's
  existing layout and the ⋯ button.
- Whether the "is this a favorite" lookup is one shared provider watched by
  every row (recommended) or per row.
