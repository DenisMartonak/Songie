# Friend Activity (SON-35) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Friends see what you're playing now and your top 10.
- You can join a friend who is hosting a room.
- Two sharing switches are stored with the account.

**Architecture:**
- **Server.** One `activity` row per account. It is written only through
  security-definer functions; friends read it through `friend_activity()`,
  which leaves out what isn't shared.
- **App.** An `ActivityPublisher` writes from the player and stats. The
  `FriendsService` fetches friends' activity with each refresh, and every
  minute while a friends page is open.
- **Settings** gets a Privacy section.

**Tech Stack:** Supabase (Postgres, RPC), Flutter, Riverpod, fake_async; a
podman Postgres for the SQL checks.

**Spec:** `docs/superpowers/specs/2026-11-13-friend-activity-design.md`

## Global Constraints

- **Migration** `supabase/migrations/20261115120000_friend_activity.sql`,
  applied after the friends one. Documented in `docs/supabase.md` as
  "Friend activity (`20261115120000_friend_activity.sql`)", with manual
  checks.
- **RPCs:**
  - `set_sharing(p_listening boolean, p_top boolean)`
  - `publish_now_playing(p_now jsonb, p_room_code text)`
  - `publish_top(p_top jsonb)`
  - `friend_activity() returns table (user_id uuid, now_playing jsonb,
    now_updated_at timestamptz, room_code text, top jsonb)`
  - `my_sharing() returns table (share_listening boolean, share_top
    boolean)`, which gives both true when the caller has no row.
- **JSON shapes:**
  - now playing: `{"title", "artist", "videoId"?}`;
  - top: `{"artists": [{"name"}], "songs": [{"title", "artist",
    "videoId"?}]}`, at most 10 of each.
  - Covers come from `videoId` (`https://i.ytimg.com/vi/<id>/hqdefault.jpg`).
    Local songs have none.
- **Timings:**
  - publish debounce 2 s;
  - re-publish every 5 min while playing;
  - top at most once an hour;
  - fast poll every 1 min while a friends page is open;
  - stale after 15 min.
- **Copy:**
  - Settings section "Privacy", with switches "Share what I'm listening to"
    and "Share my top 10 with friends". Signed out: "Log in to share with
    friends".
  - Friend page: "Not listening right now", "Join", "Top artists",
    "Top songs".
  - Friend row line: "♪ <title> · <artist>".
- Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH`. Never
  boot the Android emulator.

## Review Focus

1. **A friend turns sharing off.** Their now playing, room code and top
   vanish from your view at the next fetch. The server must not return them
   even if stale fields linger. Covered by SQL check 3 in Task 1 and a
   service test in Task 4.
2. **The app closes mid-song without clearing.** The status counts as stale
   after 15 minutes and isn't shown. Covered in Task 4.
3. **Hosting starts or ends while a song plays.** The room code is
   published and cleared without waiting for a song change. Covered in
   Task 3.
4. **A non-friend calls `friend_activity()`** or reads the table, and gets
   nothing about strangers. Covered by SQL check 4 in Task 1.
5. **Signing out.** It stops publishing and clears your now playing on the
   server before the session goes, where possible. Covered in Task 3.

---

### Task 1: Migration and docs

**Files:**
- Create: `supabase/migrations/20261115120000_friend_activity.sql`
- Modify: `docs/supabase.md`

**Interfaces:**
- **Table** `public.activity(user_id uuid primary key references
  auth.users on delete cascade, share_listening boolean not null default
  true, share_top boolean not null default true, now_playing jsonb,
  now_updated_at timestamptz, room_code text, top jsonb, top_updated_at
  timestamptz)`.
  - RLS is on, with a select policy for your own row only and
    `grant select`. There is no other grant.
- **`public.are_friends(a uuid, b uuid) returns boolean`.** It is security
  definer, revoked from clients, and checks for an accepted `friendships`
  row.
- **Functions** (security definer, `search_path = ''`, granted to
  `authenticated`), as listed in the Global Constraints:
  - `set_sharing` upserts. Turning off listening nulls `now_playing`,
    `now_updated_at` and `room_code`; turning off top nulls `top` and
    `top_updated_at`.
  - `publish_now_playing` upserts `now_playing`, `room_code` and
    `now_updated_at = now()`. It does nothing while `share_listening` is
    false.
  - `publish_top` upserts. It does nothing while `share_top` is false.
  - `friend_activity()` gives one row per accepted friend that has an
    activity row. Each field is null unless its sharing flag is on.
  - `my_sharing()`.

- [ ] **Step 1: Write the SQL**, in the friends migration's style.
- [ ] **Step 2: Write the docs section** with manual checks for accounts
  A and B (friends) and C (not a friend):
  1. A publishes now playing; B sees it in `friend_activity()`.
  2. A publishes top; B sees it.
  3. A runs `set_sharing(false, true)`. B's row for A has null now
     playing and room code but still has top. A's own row has those fields
     nulled.
  4. C's `friend_activity()` has no row for A. C's `select * from activity`
     shows only C's own row.
  5. Writing to `activity` directly fails.
  6. Deleting A removes A's row.
- [ ] **Step 3: Verify in a throwaway container.**
  - Start `podman run -d --rm --name songies-pg -e POSTGRES_PASSWORD=x
    docker.io/library/postgres:16-alpine`.
  - Apply the auth/profiles stub, then the friends migration, then this
    one.
  - Run checks 1–6 as SQL.
  - Expected: every check as documented. Then stop the container.
- [ ] **Step 4: Commit** `feat(friends): activity table and functions
  (SON-35)`

### Task 2: ActivityBackend

**Files:**
- Create: `lib/friends/activity_backend.dart`
- Create: `test/helpers/fake_activity_backend.dart`
- Modify:
  - `lib/providers.dart`: `activityBackendProvider`, lazy.
  - `test/helpers/ui_harness.dart`: `activityBackend`, with an override.
- Test: `test/friends/activity_backend_test.dart`

**Interfaces:**
- **Models.** Each has value `==`, `toJson` and a lenient `fromJson` that
  returns null on a bad shape.
  - `class NowPlaying { title, artist, String? videoId }`
  - `class TopSummary { List<String> artists; List<NowPlaying> songs }`.
    Songs reuse the shape.
  - `class FriendActivity { NowPlaying? nowPlaying; DateTime?
    nowUpdatedAt; String? roomCode; TopSummary? top; bool
    listeningAt(DateTime now) }`. `listeningAt` is `nowPlaying != null`
    and updated within 15 minutes.
  - `class Sharing { bool listening, top }`.
- **The interface:**

  ```dart
  abstract interface class ActivityBackend {
    Future<Sharing> mySharing();
    Future<void> setSharing(Sharing s);
    Future<void> publishNowPlaying(NowPlaying? now, {String? roomCode});
    Future<void> publishTop(TopSummary top);
    Future<Map<String, FriendActivity>> friendActivity();
  }
  ```

- `SupabaseActivityBackend(client)` and `.withRpc(rpc)`. Errors map
  through the same rules as `SupabaseFriendsBackend._guard`; extract it as
  `Future<T> guardFriendsCall<T>(Future<T> Function())` in
  `friends_backend.dart` and reuse it.
- **`FakeActivityBackend`:**
  - per-user rows, `me`, `friendsOf` (a callback);
  - sharing flags applied as the SQL does;
  - `calls` and `error`.

- [ ] **Step 1: Write the failing tests**
  - `'models round-trip and reject bad shapes'`.
  - `'listeningAt ignores a status older than 15 minutes'`.
  - `'calls map to their functions and parameters'` (withRpc):
    - `publishNowPlaying(null)` sends `{'p_now': null, 'p_room_code':
      null}`.
    - `setSharing` sends both booleans.
    - `friendActivity` parses rows into a map.
  - `'the fake hides what is not shared'`: B turns listening off, and A's
    `friendActivity()['b'].nowPlaying` is null while its top remains.
- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/friends/activity_backend_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.** Also run `flutter test test/friends`.
- [ ] **Step 5: Commit** `feat(friends): activity backend (SON-35)`

### Task 3: ActivityPublisher

**Files:**
- Create: `lib/friends/activity_publisher.dart`
- Modify: `lib/providers.dart`: `activityPublisherProvider`, which follows
  the account like `friendsServiceProvider`. It is started from `main.dart`
  next to the other always-on services.
- Test: `test/friends/activity_publisher_test.dart`

**Interfaces:**
- `ActivityPublisher({required ActivityBackend backend, required
  Stream<PlayerState> states, required PlayerState Function() current,
  required String? Function() roomCode, required Stream<Object?>
  roomChanges, required Future<TopSummary?> Function() top, DateTime
  Function()? now})`.
  - Members: `signedIn()`, `Future<void> signedOut()`, `dispose()`, and
    `Sharing sharing` (loaded on sign-in).
  - It publishes now playing from `current()`:
    - `NowPlaying(title, artist, videoId: track.ytVideoId)` when playing;
    - else null.
  - It reacts to song, playing and room changes, debounced by 2 s, and
    re-publishes every 5 min while playing. It skips when sharing
    listening is off.
  - `top()` builds from `StatsRepository.period(StatsPeriod.month)`: the
    first 10 artists and songs. It publishes at sign-in and then when an
    hour has passed (checked on each publish tick). It skips when sharing
    top is off.
  - `signedOut` sends `publishNowPlaying(null)` (errors ignored), then
    stops.
  - `setSharing(Sharing)` calls the backend and updates `sharing`.
  - `roomCode()` is the hosting status's code while hosting, else null.

- [ ] **Step 1: Write the failing tests** (fake_async, a fake player
  stream)
  - `'a song change publishes after 2 s; pausing clears'`.
  - `'a long song is published again every 5 minutes'`.
  - `'starting to host publishes the room code without a song change'`.
  - `'sharing off: nothing is published'`.
  - `'top is published at sign-in and not again within the hour'`.
  - `'signing out clears now playing and stops'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(friends): publish what you listen to
  (SON-35)`

### Task 4: Friends' activity in FriendsService

**Files:**
- Modify: `lib/friends/friends_service.dart` and `lib/providers.dart`, so
  that `friendsServiceProvider` passes the activity backend.
- Test: `test/friends/friends_service_test.dart`

**Interfaces:**
- `FriendsState` gains `Map<String, FriendActivity> activity`.
- `FriendsService(FriendsBackend, {ActivityBackend? activity, …})`.
  - `refresh()` also fetches `friendActivity()`. If that fetch fails, the
    friends still update and the old activity is kept.
  - `Object watchClosely()` returns a token, and `stopWatching(token)`
    releases it. While any token is held, it refreshes every 1 minute.
- `bool FriendsState.listening(String id, DateTime now)`.

- [ ] **Step 1: Write the failing tests**
  - `'refresh brings friends\' activity'`.
  - `'a friend who stops sharing loses their status at the next refresh'`.
  - `'a status older than 15 minutes is not listening'`.
  - `'watching closely refreshes every minute until released'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(friends): fetch friends' activity (SON-35)`

### Task 5: Settings → Privacy

**Files:**
- Create: `lib/ui/settings/privacy_settings.dart`:
  `PrivacySettingsSection`.
- Modify: `lib/ui/settings/settings_page.dart`, adding it after
  Playback.
- Test: `test/ui/settings/privacy_settings_test.dart`

**Interfaces:**
- Two `SwitchListTile`s, `privacy.listening` and `privacy.top`.
  - They read `activityPublisherProvider`'s `sharing`.
  - A toggle calls `setSharing`. On failure, the switch flips back and an
    island shows "You're offline" or "Couldn't save that".
- Signed out, the section shows only "Log in to share with friends".

- [ ] **Step 1: Write the failing tests**
  - `'both switches start on and save to the server'`.
  - `'a failed save flips the switch back and says so'`.
  - `'signed out it asks to log in'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(friends): privacy switches in Settings
  (SON-35)`

### Task 6: Activity on the friends pages

**Files:**
- Modify: `lib/ui/friends/friends_page.dart` (friend rows) and
  `lib/ui/friends/friend_page.dart`.
- Test: `test/ui/friends/friend_activity_ui_test.dart`

**Interfaces:**
- **Friend rows:** a second line, "♪ <title> · <artist>"
  (`friends.listening.<id>`), while `listening(id, now)`.
- **Friend page:**
  - a now-playing card (`friend.nowPlaying`) with a cover
    (`Artwork`/network image from the `videoId`), the title and the
    artist;
  - "Join" (`friend.join`) when `roomCode != null`. It calls
    `joinRoomAsking(context, container, code)`, as the join dialog does;
  - otherwise "Not listening right now" (`friend.notListening`);
  - "Top artists" and "Top songs", 10 rows each, when the top is shared.
- Both pages call `watchClosely` in `initState` and `stopWatching` in
  `dispose`.

- [ ] **Step 1: Write the failing tests**
  - `'a listening friend shows what they play on their row'`.
  - `'a friend\'s page shows now playing, top artists and top songs'`.
  - `'Join appears when they host and joins their room'`: use `RoomRig`.
    The friend hosts code `ABCD2345`; after Join, the room service is
    guesting.
  - `'a stale or unshared status says Not listening right now'`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.** Then run `dart format lib test`,
  `flutter analyze` and the full `flutter test`.
- [ ] **Step 5: Commit** `feat(friends): show friends' listening and top 10
  (SON-35)`
