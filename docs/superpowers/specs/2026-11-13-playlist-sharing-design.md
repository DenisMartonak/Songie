# Playlist sharing (SON-32)

## Intent

Share a playlist with anyone through a link. The person who opens it gets
it in their library and keeps getting your updates, but can't edit it. Or
they make their own copy, which they can edit and which no longer follows
yours.

## Decisions (user's)

- **Following.** The receiver's playlist follows yours: your adds,
  removals and reorders reach them. They can't edit it.
- **Make a copy.** At any time they can turn it into their own playlist,
  which is editable and no longer follows yours.
- **How it reaches them (A).** A link, sent through any app. Opening it in
  Songies (signed in) offers "Follow" and "Make a copy". Anyone with the
  link and an account can follow, friends or not.
- **How it stays current (approach 1, picked).** Your device publishes a
  snapshot of the playlist's songs under a share code. Followers' apps
  fetch it and update their copy.

## Approaches considered

- **1. A published snapshot (picked).** It's simple, works like friend
  activity, and only shareable songs are sent. A change reaches followers
  once the device you made it on has been online with Songies open.
- **2. The server reads your synced playlist directly.** It would always be
  current, but the server would have to understand the sync rows' internal
  format, which ties sharing to it.

## My calls (agreed)

- **Local files aren't shared.** Followers get the YouTube songs only. When
  you share, you see how many songs from your files are left out.
- **A followed playlist:**
  - shows "Following · by ‹name›";
  - can't be edited, including name, cover and songs;
  - its songs can be played, downloaded and added to other playlists;
  - "Stop following" removes it;
  - it syncs across the follower's own devices like their other playlists.
- **When you stop sharing or delete it,** followers keep the last version
  as their own regular playlist, with a note "‹name› stopped sharing this".
  Nothing vanishes.
- **Opening a link needs an account.** Signed out, it asks you to log in.
- **"Stop sharing"** is on the playlist. Sharing again makes a new link, so
  the old one stays dead.

## Design

### Links

- `<site>/p/<code>` on the website opens `songies://playlist/<code>` in the
  app, like room links (`website/404.html`, `lib/room/room_links.dart`).
- The code is 12 characters from the room-code alphabet. It's the only
  secret, so it is long enough not to be guessed.
- The website change must be live before an app release hands out these
  links (docs/releasing.md, step 0).

### Server

The migration is `supabase/migrations/20261116120000_playlist_sharing.sql`,
documented in `docs/supabase.md`.

- **Table** `shared_playlists(code text primary key, owner uuid references
  auth.users on delete cascade, name text, songs jsonb, updated_at)`.
  - `songs` is `[{title, artist, videoId, album?, durationMs?}]`.
  - It has size limits, like friend activity.
  - Apps don't read it directly.
- **Functions** (security definer, signed-in only):
  - `share_playlist(p_name, p_songs) returns code`;
  - `update_shared_playlist(p_code, p_name, p_songs)`, owner only;
  - `stop_sharing_playlist(p_code)`, owner only;
  - `get_shared_playlist(p_code) returns (name, owner_name, songs,
    updated_at)`. It's null when the code is unknown or stopped.
- A row goes with the owner's account.

### App

- **The owner's playlist** remembers its share code. Whenever its songs or
  name change, the owner's device republishes the snapshot, debounced.
- **The follower's playlist** remembers the code it follows, the owner's
  name, and the last `updated_at` it applied.
  - **When it fetches:** on app start, every 15 minutes, and when the
    playlist opens.
  - **Applying an update:** it replaces the playlist's songs with the
    snapshot's. The songs come in through the usual YouTube song store, so
    covers and downloads work.
  - **When the code is gone:** the playlist turns into a regular playlist
    of theirs, with the note.
- **"Make a copy"** creates a new regular playlist with the same songs, and
  offers to stop following the original.
- **Sync format constraint.** Share and follow fields on `playlists` change
  the synced row format.
  - The builder must use the existing row-format mechanism (`kRowFormat`),
    so an older app version on another device never overwrites them.
  - Or the fields go in a new synced table. That needs the server to accept
    the table name, like the saved-artists migration.

### Screens

- **On your playlist:** "Share", which shows the link to copy or send. Once
  shared, it gives "Copy link" and "Stop sharing", and notes how many songs
  from your files are left out.
- **Opening a link:** a sheet with the playlist's name, the owner, the song
  count and the first few songs, plus "Follow" and "Make a copy".
- **On a followed playlist:**
  - the "Following · by ‹name›" line;
  - "Make a copy" and "Stop following";
  - every edit control hidden.

## Known limit (accepted)

An older Songies version on the **owner's** other device can clear the
owner's share mark.

1. The older version, before it updates, renames the shared playlist or
   changes its cover.
2. After it updates, sync's whole-row last-write-wins keeps its copy of the
   row, which has no share code.
3. The share stays live but frozen, and the owner's playlist shows as not
   shared. Sharing it again makes a new link.

This is a limit of the existing row-format mechanism, which saved artists
share too. A follower's devices are not affected: followed playlists and
their entries are always new-format rows, which an older version leaves
alone.

## Non-goals

No collaborative editing, no sharing with chosen friends only or in-app
invites (a possible later addition), no follower counts, and no sharing of
local files.

## Left to the builder

- The share sheet's layout.
- How a followed playlist is told apart in the database (a column, or a new
  synced table), within the constraint above.
- The SQL details.
