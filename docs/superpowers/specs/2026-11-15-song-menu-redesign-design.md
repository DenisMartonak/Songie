# Song menu and Add to playlist redesign

## Intent

The song menu (⋯ / long-press / right-click on any song) is a flat list of
up to ten rows, and Add to playlist adds to one playlist at a time. The
user gave two reference images: a menu with a header, three big tiles and
a short list, and an Add to playlist sheet with checkboxes and Save.

## Goals

- **Menu** (`lib/ui/widgets/song_menu.dart`), one widget for both
  platforms: phone = bottom sheet (with drag handle); desktop (⋯ button and
  right-click) = a floating card at the pointer, replacing the popup list.
  - Header: cover (56 px, rounded), title, artist, and a round star button
    on the right that toggles Favorites at once (filled when favorite).
  - Tiles row: **Queue**, **Playlist**, **Radio** (icon above label,
    filled `surface`-tone tiles, theme radius). Radio only for a playable
    YouTube song; otherwise two tiles. Queue respects today's room-guest
    rules (hidden / greyed as now).
  - List rows below: Play on <device> / Add to queue on <device>, Go to
    artist, Go to album, Download / Remove download — each only where it
    applies today.
  - Divider, then **Remove from this playlist** in the error color (only
    inside one of your playlists).
  - Every action does exactly what it does today.
- **Add to playlist** (`lib/ui/library/add_to_playlist_sheet.dart`):
  - Header: "Add to playlist", a search icon (expands to a field that
    filters by name), a round "+" button.
  - Rows: Favorites first (accent tile with a star), then your own
    playlists (followed ones excluded, as now), each with art, name and a
    checkbox.
  - Boxes start ticked where the song already is (Favorites included).
  - "+" asks for a name (existing name dialog), creates the playlist and
    shows it ticked.
  - Footer: "None selected" / "1 selected" / "N selected" (count of ticked
    boxes), and **Save**. Save applies only the difference: adds to newly
    ticked, removes from unticked, toggles Favorites if changed. Closing
    without Save changes nothing (except a playlist made with "+", which
    stays, empty).
  - Island after Save: "Added to <name>" / "Added to N playlists",
    "Removed from <name>" / "Removed from N playlists", both joined when
    both happened, nothing when nothing changed. Failures: "Couldn't save
    to <name>" (failure kind).
- Phone: the sheet is a bottom sheet up to ~85 % height. Desktop: the same
  content as a centered dialog (max width 480).

## Non-goals

- No multi-song add (nothing calls the sheet with more than one song).
- No change to which actions exist or what they do.
- No change to the playlist page's own menu.

## Approaches

1. **Rebuild both in place, keeping the action logic (chosen).** One menu
   widget, two presentations; one new repository read.
2. Separate phone and desktop menus — rejected: two copies of the
   availability logic drift.
3. Checkboxes save instantly, no Save — rejected: the reference has Save,
   and a mis-tap would remove a song.

The user picked: desktop uses the new card; boxes start ticked and
unticking removes.

## Builder notes

- New read: `LibraryRepository.playlistIdsContaining(String trackId) →
  Future<Set<String>>`, and a remove method if none exists for one track
  from one playlist (check `library_repository.dart`; playlists use
  fractional positions and sync rows — remove the way the playlist page's
  Remove from this playlist does).
- A YouTube Music song not yet stored is stored when the sheet opens (as
  the menu's `track()` does today), so membership can be read.
- Colors only from the theme. Reduced motion as today (`Motion`).
- Keep existing keys where tests use them (`songMenu.sheet`, entry keys
  by action name, `addToPlaylist.sheet`, `addToPlaylist.new`,
  `addToPlaylist.<id>`); add `songMenu.star`, `songMenu.tile.<action>`,
  `addToPlaylist.save`, `addToPlaylist.search`, `addToPlaylist.favorites`.
