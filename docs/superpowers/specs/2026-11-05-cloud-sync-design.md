# Cloud sync (Supabase) — step 2 — design

Roadmap item 5, step 2 (`docs/ROADMAP.md`). Agreed with the user on
2026-11-05. Builds on step 1 (accounts, `docs/superpowers/specs/2026-11-05-accounts-design.md`).

## Why

Today two Songies devices sync over the home network after pairing with a
code (`lib/sync/`, Settings → Sync devices). The user wants the library to
follow their account instead, through Supabase, everywhere they're signed
in, and the home-network sync removed.

## What syncs (the user's list, plus what it implies)

Synced through the account:
- **Themes** and the **fonts** imported for them (font files too).
- **Playlists** and their entries, including **Favorites** (a playlist).
- The **track details** those playlists point to (`Tracks` rows: title,
  artist, album, length, source, YouTube id, artwork reference).
- **Listening stats** (`Listens`), the **lyrics cache** (`Lyrics`) and
  `YtSeen` — they sync today and the user asked for "everything" except the
  list below. *(Claude's call.)*
- **Artwork files** referenced by synced rows that can't be fetched again
  from YouTube (e.g. art read from a local file's tags, custom covers);
  YouTube thumbnails are fetched again on each device instead of uploaded.
  *(Claude's call.)*

Kept on each device (the user decided): which songs are **downloaded**,
**search history**, **local music files** (MP3s and the music folders),
and everything already device-local (`LocalFiles`, `PlaylistDevicePrefs`,
`LibraryFolders`, `Settings`, `PlayHistory`).

**YouTube sign-in is not synced in this step.** Syncing it would mean
storing Google session cookies in the Supabase database, and YouTube may
end sessions that appear from several devices at once. A possible later
follow-up: upload it encrypted on the device with a passphrase only the
user knows. *(Claude's recommendation; the user didn't object.)*

## Local songs on other devices

A playlist entry whose track is a **local file that this device doesn't
have** is **hidden** on this device (the user decided). "Has" means this
device has a `LocalFiles` row for that track, in any state: a file that
went missing on this same device still shows as missing with Locate, as
today; only tracks that never had a file here are hidden. *(Claude's
call.)* Hidden entries are not listed, not
counted in the song count or length, not played. A device that has the
file shows it normally. YouTube tracks always show. Favorites follows the
same rule.

## How it behaves

- **Signed in:** changes go up within a few seconds when online and come
  down when the app opens, when it comes back online, and live while it
  runs (Supabase Realtime), so a playlist edited on the phone appears on
  the computer without a restart. *(Claude's call: Realtime for
  "down", debounced push for "up".)*
- **Signed out:** nothing syncs; the library stays on the device as it is.
- **Offline:** everything works locally; changes queue (they're already
  marked by `localSeq`) and go up when the connection is back.
- **Merging:** the existing rules — every row carries an HLC `clock`, the
  newer write wins per row, deletions are tombstones (`deleted`), and
  entries added on two devices are both kept. The playlist "clash" question
  the home-network sync asks today (`lib/sync/merger.dart`,
  `clash_dialog.dart`) is **not** asked: the cloud merges automatically,
  newest row wins. *(Claude's call: with live sync, clashes are rare and a
  dialog appearing on its own is confusing.)*
- **Delete vs. edit (the user decided: the newer action wins):** when one
  device deletes a playlist and another adds or changes its songs, the
  later action by clock wins. If the delete is later, the playlist and the
  entries added elsewhere are gone; if the edit is later, the playlist
  comes back with them. No special case; tombstones are ordinary rows.
- **First sign-in on a device that already has a library:** its rows are
  merged into the account and the account's rows into the device, by the
  same newer-wins rule (a newer deletion on one side does apply). Nothing
  else is removed. Signing in on a second device with its own library merges
  that too. *(Claude's call.)*
- **Signing out:** the library stays on the device; sync stops.
- **Logging out:** the app first tries to upload anything not yet sent; if
  it can't (offline), it warns "Some changes on this device haven't been
  uploaded yet. Log out anyway?" *(Claude's call.)*
- **Switching accounts on one device** (log out, log in as someone else):
  on logging in as a **different** account than last time, ask "This
  device has a library from another account. Merge it into this account,
  or start empty?" **Start empty** removes this device's playlists and
  entries (Favorites emptied), themes, fonts, lyrics, listens and YtSeen;
  `Tracks` rows stay (downloads and local files point at them) and are
  simply no longer in any playlist. *(Claude's calls.)*
- **Paired devices from today's home-network sync:** after the update they
  no longer sync with each other until the user signs in on both; then the
  cloud merges both libraries. Nothing is lost; the release notes say to
  sign in on every device. *(Claude's call.)*
- **Deleting the account** deletes the account's cloud data too. The
  deleting device keeps its library locally and is signed out. Other
  devices find their session no longer works, sign out and keep their
  library; signing in again there counts as a different account (the
  merge-or-empty question). *(Claude's calls.)*
- **Status:** Settings → Account shows "Synced" / "Syncing…" / "Waiting
  for internet" and the last sync time. No sync errors pop up on their own;
  a failing sync shows in that line. *(Claude's call.)*

## Removed

Home-network sync, all of it: pairing codes, device discovery (mDNS),
the sync server and client, the SPAKE2 pairing, peers, file transfer
between devices, Settings → Sync devices and its sheets, progress card and
clash dialog. The `Peers` table is dropped in a database migration. What
cloud sync reuses stays: `SyncColumns`, the HLC (`SyncStamp`), `ChangeFeed`
(rows changed since a sequence number), `RowApplier` (applying incoming
rows newest-wins), `SyncRow`. The device identity used as `originDevice`
stays (or moves) as needed. *(Claude's call on what to keep.)*

## Data in Supabase

- One table for synced rows, owned per user: e.g.
  `public.sync_rows(user_id, tbl, id, clock, origin_device, deleted,
  data jsonb, server_seq bigserial, updated_at)` with primary key
  `(user_id, tbl, id)`; row-level security: a user reads and writes only
  their own rows. Upserts only replace a row when the incoming `clock` is
  newer (done in a database function so two devices can't overwrite each
  other out of order). `server_seq` lets a device ask "what changed since
  I last pulled". *(Shape is Claude's call; builder may refine.)*
- Each row carries `fmt`, the app's row format. The server never lets an
  older format overwrite a newer one; a device that pulls a row it can't
  read (newer format, or data it can't decode) skips it, notes the lowest
  such `server_seq` and moves on, shows "Update Songies to keep syncing"
  for a newer format, and after an app update pulls from that seq again
  (and, if a newer format was seen, pushes everything again). NUL, which
  Postgres can't store, goes up escaped.
- Storage bucket for synced files (fonts, non-YouTube artwork), private,
  per-user folders.
- Account deletion (step 1's `delete_my_account`) also deletes the user's
  `sync_rows` (cascade) and their files.
- Free-tier limits: 500 MB database, 1 GB storage. A heavy library
  (tens of thousands of tracks and listens) fits; this is noted in
  `docs/supabase.md`.

## Goals

- Sign in on a new device and the playlists, Favorites, themes, fonts,
  stats and lyrics appear; edit on one device and it shows on the other
  within seconds when both are online.
- Nothing is lost when the same library is edited offline on two devices.
- No account, no change: signed-out use is exactly as today minus the
  removed home-network sync.

## Non-goals

- Syncing downloads, search history, local music files or settings.
- YouTube sign-in sync.
- Remote control and listen together (steps 3 and 4).
- Sharing playlists between different accounts.

## Anti-goals

- Losing a user's playlists or edits during the switch from home-network
  sync to cloud sync, or on first sign-in.
- Another user ever seeing someone's rows or files.
- Sync noise: pop-ups, battery drain from constant polling.

## Left to the builder

- Exact table/functions, pagination, Realtime channel setup, debounce
  timings, how artwork files are chosen for upload, how hidden local
  entries are filtered (query vs view), the drift migration dropping
  `Peers`, and what parts of `lib/sync/` are deleted vs moved.
