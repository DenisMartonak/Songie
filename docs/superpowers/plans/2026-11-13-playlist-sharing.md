# Playlist Sharing (SON-32) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Share a playlist by link.
- Receivers follow it (read-only, kept up to date) or make their own
  copy.

**Architecture:**
- **Server.** The owner's device publishes a snapshot of the playlist's
  YouTube songs under a 12-character code (`shared_playlists`, reached
  only through security-definer functions).
- **Follower.** A followed playlist is a normal synced playlist row with
  follow fields. The follower's device fetches the snapshot and replaces
  the playlist's entries with it.
- **Links.** `<site>/p/<code>` opens `songies://playlist/<code>`, as room
  links do.

**Tech Stack:** Supabase (Postgres, RPC), drift (schema 12), Flutter,
Riverpod, fake_async; plain JS for the website, with node tests; podman
Postgres for the SQL.

**Spec:** `docs/superpowers/specs/2026-11-13-playlist-sharing-design.md`

## Global Constraints

- **Migration** `supabase/migrations/20261116120000_playlist_sharing.sql`,
  plus a "Playlist sharing" section in `docs/supabase.md` with manual
  checks. Add it to the pending-migrations note.
- **RPCs:**
  - `share_playlist(p_name text, p_songs jsonb) returns text`, the code;
  - `update_shared_playlist(p_code text, p_name text, p_songs jsonb)`;
  - `stop_sharing_playlist(p_code text)`;
  - `get_shared_playlist(p_code text) returns table (name text,
    owner_name text, songs jsonb, updated_at timestamptz)`, no rows when
    unknown or stopped.
  - Errors: `not_owner`, `too_large` (songs over 512 kB).
- **Code:** 12 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, made on
  the server.
- **Links:**
  - `playlistLink(code) = '$kRoomSiteBase/p/$code'`;
  - `parsePlaylistCode` accepts `songies://playlist/<code>`, any
    `…/p/<code>` address, or a bare code;
  - Android intent filter `songies` / host `playlist`.
- **Snapshot song shape:** `RoomSong.toJson()` (videoId, title, artist,
  album, durationMs, artUrl). Only songs with a `videoId` are shared.
- **Playlist columns** (drift schema 11 → 12, `kRowFormat` 11 → 12, in
  step):
  - `shareCode text?` (owner);
  - `followCode text?`, `followOwner text?`, `followUpdatedAt datetime?`
    (follower);
  - `followEnded bool default false`.
- **Timings:**
  - owner republish debounce 3 s;
  - follower refresh at app start, every 15 min, and when a followed
    playlist opens.
- **Copy:**
  - "Share", "Copy link", "Stop sharing";
  - "Following · by ‹owner›", "Make a copy", "Stop following", "Follow";
  - "‹owner› stopped sharing this";
  - "N songs from your files aren't shared" (singular: "1 song from your
    files isn't shared");
  - "This playlist isn't shared any more" (link to a stopped share);
  - signed out: "Log in to open shared playlists".
- Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH`. Never
  boot the Android emulator.

## Review Focus

1. **Editing a followed playlist** is refused everywhere:
   - repository calls return `Err`;
   - UI edit controls are hidden;
   - the song menu offers no "Remove from playlist" on it.

   Covered in Tasks 4 and 6.
2. **An older app version on the follower's other device** never wipes the
   follow fields. Covered by the `kRowFormat` bump in Task 4 and the
   existing fmt rule.
3. **The owner stops sharing while a follower is offline.** At the next
   fetch the playlist becomes theirs, with the note, and its songs are
   kept. Covered in Task 5.
4. **Opening your own playlist's link** offers no Follow. It says it's
   yours and opens the playlist. Covered in Task 6.
5. **A snapshot with a song the follower already has** reuses their track
   row, with no duplicates (`tracksForSongs` / `YtTrackStore`). Covered in
   Task 5.

---

### Task 1: Migration and docs

**Files:**
- Create: `supabase/migrations/20261116120000_playlist_sharing.sql`
- Modify: `docs/supabase.md`

**Interfaces:**
- **Table** `shared_playlists(code text primary key, owner uuid not null
  references auth.users on delete cascade, name text not null, songs jsonb
  not null, updated_at timestamptz not null default now())`.
  - RLS is on, with no policies and no grants (functions only).
- **Functions** as listed in the Global Constraints:
  - security definer with `search_path = ''`, `revoke` from public and
    anon, `grant` to authenticated;
  - code generation retries on a collision, using
    `extensions.gen_random_bytes` like `open_room`;
  - `get_shared_playlist` joins `profiles` for `owner_name`;
  - stopping deletes the row.

- [ ] **Step 1: Write the SQL.**
- [ ] **Step 2: Write the docs section** with checks, for accounts A
  (owner) and B:
  1. A shares and gets a 12-character code; B's `get_shared_playlist`
     returns the songs and `owner_name`.
  2. A updates, and B sees the change.
  3. B's `update_shared_playlist` or `stop_sharing_playlist` on A's code
     fails with `not_owner`.
  4. A stops sharing; B's get returns no rows.
  5. B's `select * from shared_playlists` fails with permission denied.
  6. More than 512 kB fails with `too_large`.
  7. Deleting A removes A's rows.
- [ ] **Step 3: Verify in podman** with the auth/profiles + extensions +
  realtime stubs, plus all migrations up to this one.
  Expected: checks 1–7 as documented.
- [ ] **Step 4: Commit** `feat(playlists): shared_playlists table and
  functions (SON-32)`

### Task 2: Links (app and website)

**Files:**
- Create: `lib/playlists/playlist_links.dart` and
  `website/assets/js/playlist.js`
- Modify:
  - `website/404.html`: a `playlist` view for `/p/<code>`, a `bad-code`
    view that also covers `p`, plus title and meta;
  - `android/app/src/main/AndroidManifest.xml`: the intent filter;
  - `lib/main.dart`: a listener that sets `playlistInviteProvider`;
  - `lib/providers.dart`: `playlistInviteProvider`, shaped like
    `roomInviteProvider`.
- Test: `test/playlists/playlist_links_test.dart` and
  `test/website/playlist.test.mjs`

**Interfaces:**
- `String playlistLink(String code)` and `String? parsePlaylistCode(String
  input)`. A room code (8 characters) is not a playlist code.
- JS: `playlistCodeFromPath(pathname)` and `playlistAppLink(code)`.
- `PlaylistLinkListener(Stream<Uri>, void Function(String))`, with the
  same 2-second dedupe as `RoomLinkListener`.

- [ ] **Step 1: Write the failing tests**
  - Dart: link round-trip; `songies://playlist/X` and `…/Songie/p/X`
    parse; bad lengths and letters give null; a room link gives null.
  - JS: the same cases. Run with `node --test test/website/`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.** Also run the existing room link tests.
- [ ] **Step 5: Commit** `feat(playlists): playlist links (SON-32)`

### Task 3: SharingBackend

**Files:**
- Create: `lib/playlists/sharing_backend.dart` and
  `test/helpers/fake_sharing_backend.dart`
- Modify:
  - `lib/providers.dart`: `sharingBackendProvider`, lazy;
  - `test/helpers/ui_harness.dart`: an override.
- Test: `test/playlists/sharing_backend_test.dart`

**Interfaces:**
- `class SharedPlaylist { name; ownerName; List<RoomSong> songs;
  DateTime updatedAt; }`
- **The interface:**

  ```dart
  abstract interface class SharingBackend {
    Future<String> share(String name, List<RoomSong> songs);
    Future<void> update(String code, String name, List<RoomSong> songs);
    Future<void> stop(String code);
    Future<SharedPlaylist?> get(String code); // null: gone
  }
  ```

- **Errors** map through `guardFriendsCall`. Add `notOwner` and
  `tooLarge` to `FriendsError`; rename nothing.
- **`FakeSharingBackend`:** in-memory, with `me`, owner names, and the
  `calls` and `error` hooks.

- [ ] **Step 1: Write the failing tests**
  - The RPC names and parameters, via `withRpc`.
  - `get` parses the songs and gives null for an empty result.
  - The fake enforces the owner.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(playlists): sharing backend (SON-32)`

### Task 4: Playlist columns and read-only followed playlists

**Files:**
- Modify:
  - `lib/data/tables.dart`;
  - `lib/data/database.dart`: schema 12, the `from < 12` add-columns step;
  - `lib/sync/cloud/cloud_remote.dart`: `kRowFormat = 12`;
  - `lib/library/library_repository.dart`;
  - the generated `database.g.dart`, via `dart run build_runner build`.
- Test: `test/library/followed_playlist_test.dart` and the existing
  migration test, if there is one (`test/data/`).

**Interfaces:**
- **New methods on `LibraryRepository`:**
  - `Future<Result<String>> createFollowedPlaylist({required String
    code, required String name, required String owner})`;
  - `Future<Result<void>> applySnapshot(String playlistId, {required
    String name, required List<String> trackIds, required DateTime
    updatedAt})`. It replaces the entries in order and sets
    `followUpdatedAt`;
  - `Future<Result<void>> endFollow(String playlistId)`. It sets
    `followEnded` and clears `followCode`. The playlist is then
    editable, and the screen shows the note;
  - `Future<Result<void>> setShareCode(String playlistId, String?
    code)`.
- **`bool Playlist.isFollowed`:** `followCode != null`.
- **`renamePlaylist`, `setPlaylistCover`, `addTracks`, `moveEntry`,
  `removeEntry`, `keepEntry` and `replaceEntryTrack`** return
  `Err(Failure(FailureKind.readOnly, …))` on a followed playlist. Add
  `readOnly` to `FailureKind` if it is missing.

- [ ] **Step 1: Write the failing tests**
  - `'a followed playlist refuses edits'`: every method listed returns
    `Err`, and the entries are unchanged.
  - `'applySnapshot replaces entries in order and keeps the playlist id'`.
  - `'endFollow keeps the songs and makes it editable'`.
  - `'a schema 11 database upgrades with the new columns null'`. Use the
    project's existing migration test pattern, if there is one; otherwise
    open a v11 file made with raw SQL.
  - `'kRowFormat matches the schema version'`: `kRowFormat ==
    AppDatabase.schemaVersion`. This guards bumping both together.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**, then run the build_runner.
- [ ] **Step 4: Run, expect PASS.** Also run `flutter test test/library
  test/sync test/data`.
- [ ] **Step 5: Commit** `feat(playlists): followed playlists in the
  library (SON-32)`

### Task 5: PlaylistSharing service

**Files:**
- Create: `lib/playlists/playlist_sharing.dart`
- Modify: `lib/providers.dart`: `playlistSharingProvider`, which follows
  the account and is listened to from `main.dart`.
- Test: `test/playlists/playlist_sharing_test.dart`

**Interfaces:**
- `PlaylistSharing({required SharingBackend backend, required
  LibraryRepository library, required Future<List<Track?>>
  Function(List<RoomSong>) tracksFor, required Stream<List<Playlist>>
  playlists, Stream<void> Function(String playlistId)? entriesChanged,
  Duration every = const Duration(minutes: 15)})`.
- **Methods:**
  - `Future<String> share(String playlistId)`, which returns the code;
  - `Future<void> stopSharing(String playlistId)`;
  - `Future<SharedPlaylist?> preview(String code)`;
  - `Future<String> follow(String code)`, which returns the playlist id;
  - `Future<String> copy({String? code, String? playlistId})`, which
    returns the new playlist id;
  - `Future<void> stopFollowing(String playlistId)`;
  - `Future<void> refresh([String? playlistId])`;
  - `signedIn()` and `signedOut()`.
- **Songs are converted** with `roomSongOf`, which already leaves local
  files without a `videoId`. Only songs with a `videoId` are sent.
  `localCount(playlistId)` supports the "N songs from your files" line.
- **Owner:** shared playlists whose entries or name change are
  republished after 3 s.
- **Follower:**
  - an unknown code means `endFollow`;
  - a newer `updatedAt` means `tracksFor`, then `applySnapshot`.

- [ ] **Step 1: Write the failing tests** (fakes and fake_async)
  - `'share publishes YouTube songs only and stores the code'`.
  - `'an owner edit republishes after 3 s'`.
  - `'follow creates a followed playlist with the songs'`.
  - `'a refresh applies a newer snapshot and skips an unchanged one'`.
  - `'a stopped share ends the follow and keeps the songs'`.
  - `'copy makes an editable playlist with the same songs'`.
  - `'a song already in the library is reused'`: no second track row.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(playlists): share, follow and copy
  (SON-32)`

### Task 6: Screens

**Files:**
- Create:
  - `lib/ui/playlists/share_playlist_sheet.dart`;
  - `lib/ui/playlists/shared_playlist_sheet.dart`, opened from a link;
  - `lib/ui/playlists/playlist_invite_listener.dart`, like
    `RoomIslands`'s invite handling.
- Modify:
  - `lib/ui/playlist/playlist_page.dart`: the Share action; the
    following line plus actions; edit controls hidden when
    `isFollowed`; the stopped note when `followEnded`;
  - `lib/ui/widgets/song_menu.dart`: no "Remove from playlist" on a
    followed playlist.
- Test: `test/ui/playlists/playlist_sharing_ui_test.dart`

**Interfaces:**
- **Keys:** `playlist.share`, `share.copyLink`, `share.stop`,
  `playlist.following`, `playlist.makeCopy`, `playlist.stopFollowing`,
  `invite.follow`, `invite.copy`.
- **Opening a link while signed out** shows an island with "Log in to open
  shared playlists" and a Sign in action that goes to `/profile`.

- [ ] **Step 1: Write the failing tests**
  - `'Share shows the link and the left-out count; Stop sharing ends it'`.
  - `'a link opens the sheet; Follow adds the playlist and opens it'`.
  - `'a followed playlist shows who it follows and hides editing'`:
    no reorder handles, no delete or rename, and no "Remove from
    playlist" in the song menu.
  - `'opening your own playlist's link opens it, without Follow'`.
  - `'a stopped share's link says so'`.
  - `'a followed playlist whose owner stopped shows the note and is
    editable'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.** Then run `dart format lib test`,
  `flutter analyze` and the full `flutter test`.
- [ ] **Step 5: Commit** `feat(playlists): share and follow screens
  (SON-32)`
