# Listen Together Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A host opens a room, shares a link, and signed-in friends who open it hear what the host plays, in step, with per-person roles (Listener, Queue, Full control).

**Architecture:** A new `lib/room/` module next to `lib/remote/`. Membership lives in Supabase (`rooms`, `room_members`, four RPCs, Realtime policies on `room:<room id>`). The host's `RoomHost` owns the one queue: it broadcasts room state (song details, not track ids) and applies guests' requests after checking their role. A guest's `RoomGuest` makes its own `PlayerService` follow that state; its `RoomGuestView` (a `PlayerView`) turns the guest's player controls into requests. `RoomService` holds the session (idle, hosting, guesting) for the UI and providers. Links arrive through `app_links`.

**Tech Stack:** Flutter 3.47.8, Riverpod 3, supabase_flutter 2.18 (Realtime Broadcast + Presence, RPC), app_links 7.2.2, drift, fake_async for timing tests.

**Spec:** `docs/superpowers/specs/2026-11-08-listen-together-design.md` (read it first; the remote-control spec `docs/superpowers/specs/2026-11-06-remote-control-design.md` describes the pieces reused here).

## Global Constraints

- Roles: `listener` (default for everyone joining), `queue`, `full`. Only the host changes roles; `full` never includes roles.
- `queue` may: `addNext`, `addToEnd`. `full` may: every op (`play`, `pause`, `toggle`, `next`, `previous`, `seek`, `shuffle`, `repeat`, `playAt`, `remove`, `move`, `playSongs`, `addNext`, `addToEnd`). `listener`: none. Volume is never sent: each person's own.
- Up to **10 people** including the host (`kRoomMaxPeople = 10`).
- Room code: 8 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, shown as `XXXX-XXXX`; parsing ignores case, spaces and `-`.
- Link: `roomLink(code)` = `'$kRoomSiteBase/r/$code'` when `kRoomSiteBase` is non-empty, else `'songies://room/$code'`. `kRoomSiteBase = ''` until SON-22 (one constant in `lib/room/room_links.dart`).
- Host gone: no host in Presence for **15 s** ends the room for guests (`kRoomHostGrace`).
- Drift: a guest whose position differs from the host's by more than **1000 ms** seeks (`kRoomDriftLimit`); smaller drift is left alone. Positions are extrapolated from the **guest's own receive time**, never from another device's clock.
- Host state: debounced **250 ms**, heartbeat every **2 s** while playing, at most **500** songs around the current one (`kRoomQueueWindow`).
- Every message carries `v` = `kRoomProtocol = 1`; decoding never throws; other versions decode to null. A guest whose host has another version leaves with "Update Songies to join this room".
- Copy (exact): strip guest `Listening with <host>`, plus ` · can add songs` for `queue` and ` · full control` for `full`; strip host `Your room · <n> listening`; panel title `Listen together`; buttons `Copy`, `Share link`, `End room`, `Leave`, `Manage`, `Join a room`; role labels `Listener`, `Queue`, `Full control`.
- Islands (exact): `You need a Songies account to join a room` (action `Sign in` → `/settings`); `This room has ended`; `This room is full`; `Room not found`; `The room ended`; `You were removed from the room`; `<name> joined`; `<name> left`; `<name> added <title>`; `You can now add songs` / `You now have full control` / `You can listen only`; `Can't play <title> here, joining in at the next song`; `Local files can't be shared in a room`; `Couldn't reach the room`.
- No emoji anywhere in the UI; icons are Material icons (`Icons.headphones_rounded` for the strip, `Icons.group_rounded` for the room button).
- No room open ⇒ no behaviour change; every existing test passes unchanged.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`; the two stats "under 500 ms" tests fail only under full-suite load.
- Known limit (rooms are for friends): the server checks that a sender is a member and that only the host sends `state`/`roles`/`kick`/`end`, but not the `from` device id inside a `request`, so one guest could pose as another. Note it in `docs/supabase.md`; don't build around it.

## Review Focus

- A guest's stream for the current song fails (or is a host's local file): the guest's own player would skip ahead; the guest must instead stay silent until the host reaches a song it can play, with no retry loop on each heartbeat. → Task 4.
- Device clocks differ by minutes: the guest must still land within 1 s of the host (receive-time extrapolation only). → Task 4.
- The host restarts the same queue (`playSongs` of the same playlist): the guest must reload even though the song list looks identical (the host's queue epoch changes). → Task 4.
- The host's app is killed without sending `end`: guests keep playing and get "The room ended" after 15 s; a later join with that code fails as ended or not found. → Tasks 1 and 5.
- Two devices of the same account in one room (host and guest): roles, kicks and requests key on the device, so the host is never removed or demoted. → Tasks 3 and 5.

---

### Task 1: Database, policies and the room backend

**Files:**
- Create: `supabase/migrations/20261109120000_listen_together.sql`
- Create: `lib/room/room_backend.dart`
- Modify: `docs/supabase.md` (a "Listen together" section: apply the migration; what each table, function and policy is for)
- Test: `test/room/room_backend_test.dart`

**Interfaces:**
- Produces (SQL):
  - `public.rooms (id uuid primary key default gen_random_uuid(), code text unique not null, host_id uuid not null references auth.users on delete cascade, created_at timestamptz not null default now(), ended_at timestamptz)`; RLS on, no direct policies (only the functions touch it).
  - `public.room_members (room_id uuid references public.rooms on delete cascade, user_id uuid references auth.users on delete cascade, joined_at timestamptz not null default now(), primary key (room_id, user_id))`; RLS on, no direct policies.
  - `security definer` functions, `set search_path = ''`, granted to `authenticated` only:
    - `open_room() returns table (room_id uuid, code text)`: ends the caller's open rooms, makes a room with a fresh code (retry on clash), adds the caller as member.
    - `join_room(p_code text) returns uuid`: raises `room_not_found`, `room_ended` (ended, or created over 24 h ago) or `room_full` (10 members) as the exception message; else adds the caller (idempotent) and returns the room id.
    - `leave_room(p_room uuid)`; `remove_member(p_room uuid, p_user uuid)` (host only, never the host); `end_room(p_room uuid)` (host only: sets `ended_at`, deletes the members).
  - Realtime policies on `realtime.messages` for topic `room:<room id>`: `select` and `insert` for members of that room (a `room_members` row for `auth.uid()` and an open room); `insert` with `event in ('state','roles','kick','end')` only when `auth.uid()` is the room's host. Presence (`extension = 'presence'`) allowed for members.
- Produces (Dart):
  - `enum RoomJoinError { notFound, ended, full, offline, other }`; `class RoomJoinException implements Exception { final RoomJoinError kind; }`
  - `class OpenedRoom { final String roomId; final String code; }`
  - `abstract class RoomBackend { Future<OpenedRoom> open(); Future<String> join(String code); Future<void> leave(String roomId); Future<void> remove(String roomId, String userId); Future<void> end(String roomId); }`
  - `class SupabaseRoomBackend implements RoomBackend { SupabaseRoomBackend(SupabaseClient Function() client); }` — `join` maps `PostgrestException.message` containing `room_not_found` / `room_ended` / `room_full` to the error kinds, socket/timeout errors to `offline`.

- [ ] **Step 1: Write the migration** (tables, functions, grants, policies as above). Comment the file as `20261107120000_remote_control.sql` is commented.
- [ ] **Step 2: Failing tests** with a fake `rpc` (inject `Future<Object?> Function(String fn, Map<String, Object?> params)` into a `@visibleForTesting` constructor): `open` returns id and code from `[{room_id, code}]`; `join('ABCD2345')` calls `join_room` with `p_code: 'ABCD2345'` and returns the id; the three exception messages map to `notFound`, `ended`, `full`; a `SocketException` maps to `offline`.
- [ ] **Step 3: Run** `flutter test test/room/room_backend_test.dart` → FAIL.
- [ ] **Step 4: Implement `SupabaseRoomBackend`.**
- [ ] **Step 5: Run** → PASS.
- [ ] **Step 6: Apply the migration to the project** (`docs/supabase.md` steps) and check by hand in the SQL editor as two users (Realtime Inspector for the topic rules); record what was checked in the doc.
- [ ] **Step 7: Commit** `feat(room): rooms, members and their Realtime rules`

### Task 2: Protocol, songs and links

**Files:**
- Create: `lib/room/room_protocol.dart`, `lib/room/room_songs.dart`, `lib/room/room_links.dart`
- Test: `test/room/room_protocol_test.dart`, `test/room/room_songs_test.dart`, `test/room/room_links_test.dart`

**Interfaces:**
- Produces (`room_protocol.dart`): the constants in Global Constraints; `enum RoomRole { listener, queue, full }`; `enum RoomOp { play, pause, toggle, next, previous, seek, shuffle, repeat, playAt, remove, move, playSongs, addNext, addToEnd }`; `bool roleAllows(RoomRole role, RoomOp op)`.
  - `class RoomSong { final String? videoId; final String title; final String artist; final String? album; final int? durationMs; final String? artUrl; bool get local => videoId == null; }` with `toJson`/`fromJson`.
  - `class RoomPresence { final String userId; final String deviceId; final String name; final String platform; final bool host; final int v; }`
  - `sealed class RoomMessage { String get event; Map<String, Object?> toJson(); static RoomMessage? decode(String event, Object? payload); }` with:
    - `RoomStateMsg(event 'state') { int epoch; List<RoomSong> songs; int offset; int index; bool playing; int positionMs; int? durationMs; bool shuffle; RepeatMode repeat; }` (`index` is into the full queue; `songs` is the window starting at `offset`).
    - `RoomRolesMsg('roles') { Map<String, RoomRole> roles; }` keyed by device id.
    - `RoomRequestMsg('request') { String from; String id; RoomOp op; Map<String, Object?> args; int? epoch; }` (`from` = device id).
    - `RoomHelloMsg('hello') { String from; }`, `RoomKickMsg('kick') { String deviceId; }`, `RoomEndMsg('end')`.
- Produces (`room_songs.dart`): `RoomSong roomSongOf(Track t)` (YouTube track → its video id; `source == 'local'` → `videoId: null`); `Future<List<Track?>> tracksForSongs(List<RoomSong> songs, YtTrackStore store)` (a `YtmSong` per YouTube song through `upsertAll`; local songs → null, positions kept).
- Produces (`room_links.dart`): `const String kRoomSiteBase = '';`, `String formatRoomCode(String code)` (`ABCD2345` → `ABCD-2345`), `String roomLink(String code)`, `String? parseRoomCode(String input)` (accepts `https://<any host>/r/<code>`, `songies://room/<code>`, `ABCD-2345`, `abcd 2345`; null otherwise).

- [ ] **Step 1: Failing tests:** every message and `RoomSong` round-trips through JSON; a wrong `v`, an unknown event, an unknown op or role, and garbage payloads decode to null; `roleAllows` table: listener none, queue exactly `{addNext, addToEnd}`, full all 14 ops; `roomSongOf` of a local track has `local == true`; `tracksForSongs` with [yt, local, yt] returns [Track, null, Track] and calls the store once per YouTube song; `parseRoomCode` accepts the four forms above and rejects `https://x/y`, `ABC` and `songies://other/ABCD2345`; `roomLink('ABCD2345')` is `songies://room/ABCD2345` with the empty base.
- [ ] **Step 2: Run** the three test files → FAIL.
- [ ] **Step 3: Implement** (decoding follows `remote_protocol.dart`'s style: type-check every field, `on Object { return null; }`).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(room): room messages, songs and links`

### Task 3: The room channel and the host

**Files:**
- Create: `lib/room/room_channel.dart`, `lib/room/room_host.dart`
- Create: `test/helpers/fake_room_hub.dart` (as `fake_remote_hub.dart`: per-device channels, JSON round trip, `drop`/`restore`, `sent`)
- Test: `test/room/room_host_test.dart`

**Interfaces:**
- Consumes: Task 2's messages and `roomSongOf`/`tracksForSongs`.
- Produces:
  - `abstract class RoomChannel { Future<void> join(RoomPresence me); Stream<List<RoomPresence>> get presences; List<RoomPresence> get present; Future<void> send(RoomMessage m); Stream<RoomMessage> get messages; Future<void> leave(); }` and `SupabaseRoomChannel(SupabaseClient Function() client, String roomId)` on topic `room:<roomId>`, private, presence key = device id (copy `SupabaseRemoteChannel`'s structure).
  - `sealed class RoomHostEvent` with `GuestJoined(String name)`, `GuestLeft(String name)`, `GuestAdded(String name, String title)`.
  - `class RoomHost { RoomHost({required RoomChannel channel, required PlayerService player, required RoomPresence me, required Future<List<Track?>> Function(List<RoomSong>) tracksFor, Future<void> Function(String userId)? removeMember}); Future<void> start(); Future<void> stop({bool end = true}); Map<String, RoomRole> get roles; Future<void> setRole(String deviceId, RoomRole role); Future<void> removeGuest(RoomPresence guest); Stream<RoomHostEvent> get events; Stream<List<RoomPresence>> get people; }`
  - Behaviour: sends `state` (debounce 250 ms, heartbeat 2 s while playing, window of 500) only while a guest is present; answers `hello` with `roles` then `state`; applies a `request` only when `roleAllows(roles[from] ?? listener, op)` and `from` is present; `playAt`/`remove`/`move` use `PlayerService.playAtIf`/`removeAtIf`/`moveIf` with the request's epoch (a stale one sends fresh state); `playSongs`/`addNext`/`addToEnd` turn songs into tracks with `tracksFor` and drop nulls; `removeGuest` sends `kick` for that device, then `removeMember(userId)` unless another present device has the same user id; `stop(end: true)` sends `end`. Presence changes emit `GuestJoined`/`GuestLeft`; an allowed add emits `GuestAdded` with the first song's title.

- [ ] **Step 1: Failing tests** (fake hub, real `PlayerService` over `FakeAudioBackend`, `fakeAsync`): no `state` while alone; a guest joining gets `roles` then `state` after `hello`; a listener's `next` changes nothing; after `setRole(guest, queue)` its `addToEnd` adds and emits `GuestAdded`, its `next` doesn't; `full` may `seek` and `playSongs`; a request from a device not present is ignored; a stale-epoch `remove` touches nothing and sends state; heartbeat every 2 s while playing, none while paused; a 1,200-song queue sends 500 songs with the right `offset`; `removeGuest` on a guest sharing the host's user id sends `kick` and does not call `removeMember`; `stop()` sends `end`.
- [ ] **Step 2: Run** `flutter test test/room/room_host_test.dart` → FAIL.
- [ ] **Step 3: Implement** `RoomChannel`, `SupabaseRoomChannel`, `FakeRoomHub`, `RoomHost`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(room): the host runs the room`

### Task 4: The guest follows

**Files:**
- Create: `lib/room/room_guest.dart`
- Test: `test/room/room_guest_test.dart`

**Interfaces:**
- Consumes: Task 3's channel and hub; Task 2's messages.
- Produces:
  - `enum RoomLeaveReason { left, ended, removed, hostGone, unreachable, outdated }`
  - `class RoomGuest { RoomGuest({required RoomChannel channel, required PlayerService player, required RoomPresence me, required Future<List<Track?>> Function(List<RoomSong>) tracksFor, DateTime Function()? now}); Future<void> start(); Future<void> leave(); RoomRole get role; Stream<RoomRole> get roles; RoomPresence? get host; Stream<List<RoomPresence>> get people; Stream<RoomLeaveReason> get ended; Stream<String> get cantPlay; Future<void> request(RoomOp op, [Map<String, Object?> args, int? epoch]); }`
  - `class RoomGuestView implements PlayerView` (in the same file): `states`/`state` from the guest's own `PlayerService`; `isRemote` false; every command that `roleAllows` becomes a `request` (songs as `roomSongOf`, local ones dropped with a `Local files can't be shared in a room` notice on a `Stream<String> notices`); disallowed commands do nothing; `setVolume` is local.
- Behaviour:
  - `start`: pauses the guest's player, joins, sends `hello` every 2 s until the first `state`; none within 15 s → `ended` emits `unreachable`.
  - Applying `state` (serialised; a newer one replaces a pending one): if the epoch or the window's songs differ from the last applied → `tracksFor`, then `playQueue` of the playable tracks at the mapped index and `seek`; same queue, other index → `playAt(mapped)`; `|local position − expected| > 1000 ms` → `seek(expected)`, where `expected = positionMs + (now − receivedAt)` while playing; `playing` → `play`/`pause`.
  - A host index whose song is local, or whose track this guest failed to play (the player's `notice` names it), is not started: the guest pauses, `cantPlay` emits its title once, and the guest waits for a later index.
  - `kick` for this device → `removed`; `end` → `ended`; host missing from Presence 15 s → `hostGone`; host presence with another `v` → `outdated`. On every end the guest leaves the channel and **does nothing to its player** (it keeps the queue and keeps playing).
  - The guest never edits its own queue except by applying state.

- [ ] **Step 1: Failing tests** (fake hub, a real host from Task 3 and a real guest player, `fakeAsync`, the guest's clock 5 minutes off the host's): joining while the guest plays something else switches to the host's song and position; the host's `next` moves the guest; a host seek by 30 s moves the guest; the guest drifting 600 ms is left alone, 1,500 ms is corrected by one seek; the host replaying the same playlist (new epoch) reloads the guest; a host local file in the queue makes the guest pause with one `cantPlay`, then follow at the next YouTube song; a stream failing on the guest pauses it until the next song, with no repeated `playAt` across 10 heartbeats; a listener's `RoomGuestView.next()` sends nothing, a `queue` guest's `addToEnd([yt, local])` sends one song and one local-files notice; `kick` → `removed`, player still playing; host dropped 15 s → `hostGone`, player still playing; no `state` within 15 s → `unreachable`.
- [ ] **Step 2: Run** `flutter test test/room/room_guest_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/room` → PASS.
- [ ] **Step 5: Commit** `feat(room): guests follow the host`

### Task 5: RoomService, providers and remote control

**Files:**
- Create: `lib/room/room_service.dart`
- Modify: `lib/providers.dart` (room providers; `playerViewProvider` returns the guest view while guesting), `lib/main.dart` (wire `SupabaseRoomBackend` and `SupabaseRoomChannel`), `lib/remote/remote_protocol.dart` (`RemotePresence.inRoom`, optional field, `v` unchanged), `lib/remote/remote_host.dart` (ignores commands while `inRoom`), `lib/ui/remote/devices_button.dart` (a device `inRoom` is greyed with `In a Listen together room`)
- Test: `test/room/room_service_test.dart`, `test/remote/remote_protocol_test.dart` (extend), `test/remote/remote_host_test.dart` (extend)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `sealed class RoomStatus` — `RoomIdle()`, `RoomHosting({required String code, required String link, required List<RoomPresence> people, required Map<String, RoomRole> roles})`, `RoomGuesting({required RoomPresence host, required RoomRole role, required List<RoomPresence> people, required Map<String, RoomRole> roles})`.
  - `sealed class RoomNotice` (for islands) — `RoomNoticeText(String text, {bool signIn = false})`.
  - `class RoomService { RoomService({required RoomBackend backend, required RoomChannel Function(String roomId) channelFor, required PlayerService player, required Future<List<Track?>> Function(List<RoomSong>) tracksFor, required String deviceId, required String platform}); RoomStatus get status; Stream<RoomStatus> get statuses; Stream<RoomNotice> get notices; RoomGuestView? get guestView; Future<void> open({required String userId, required String name, List<Track>? play}); Future<void> join(String code, {required String userId, required String name}); Future<void> leave(); Future<void> end(); Future<void> setRole(String deviceId, RoomRole role); Future<void> remove(RoomPresence guest); Future<void> signedOut(); }`
  - Providers: `roomServiceProvider` (`Provider<RoomService>`, one per app), `roomStatusProvider` (`StreamProvider<RoomStatus>`, current value first), `roomNoticesProvider` (`Provider<Stream<RoomNotice>>`), `roomInviteProvider` (`StateProvider<String?>`: a code waiting for the user, see Task 6).
  - `RemotePresence.inRoom` (bool, default false, decoded leniently).
- Behaviour: `open`/`join` while already in a room throw `StateError` (the UI asks first, Task 7); `join` maps `RoomJoinException` kinds to the island texts; `open` with `play` starts that queue after the room is up; sign-out, account change and `end()` stop the session (host: `end_room`; guest: `leave_room`); a guest's role change emits the matching island text; `GuestJoined`/`GuestLeft`/`GuestAdded` and `cantPlay` become notices; the remote controller is deselected when a room starts; this device's `RemotePresence.inRoom` follows the status.

- [ ] **Step 1: Failing tests** (fake backend, fake hub, real players): `open` → `RoomHosting` with code and `songies://room/<code>` link; a second device `join(code)` → `RoomGuesting` with the host's presence and `listener`; `join` of a full room → `RoomIdle` and notice `This room is full` (same for `notFound` → `Room not found`, `ended` → `This room has ended`); `end()` → both idle, guest notice `The room ended`, guest player still playing; `setRole(guest, full)` → guest notice `You now have full control`; `open` while hosting throws `StateError`; `signedOut()` while guesting calls `leave_room` and goes idle; `RemotePresence(inRoom: true)` round-trips and an old payload without it decodes with `false`; a `RemoteHost` whose device is in a room ignores a `play` command.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `RoomService`, the providers, the remote changes and the `main.dart` wiring (`SupabaseRoomBackend(() => Supabase.instance.client)`, `(id) => SupabaseRoomChannel(() => Supabase.instance.client, id)`, `tracksFor: (s) => tracksForSongs(s, ytTrackStore)`).
- [ ] **Step 4: Run** `flutter test test/room test/remote` → PASS.
- [ ] **Step 5: Commit** `feat(room): the room session, wired into the app`

### Task 6: Links open the app into a room

**Files:**
- Modify: `pubspec.yaml` (`app_links: ^7.2.2`)
- Create: `lib/room/room_link_listener.dart`
- Modify: `lib/main.dart` (listen after the first frame, as the share-intent listener does)
- Modify: `android/app/src/main/AndroidManifest.xml` (a `VIEW` intent filter, `BROWSABLE` + `DEFAULT`, `scheme="songies" host="room"`; `launchMode="singleTask"` if not already)
- Modify: `windows/installer/songies.iss` (`HKCU\Software\Classes\songies`: `URL Protocol`, `shell\open\command` = `"{app}\songies.exe" "%1"`), `windows/runner/main.cpp` (forward the link to the running window per app_links' Windows single-instance guide)
- Modify: `linux/runner/my_application.cc` (`G_APPLICATION_HANDLES_OPEN` and a second launch passing its link to the running instance, per app_links_linux), `linux/packaging/songies.desktop` (`Exec=songies %u`, `MimeType=x-scheme-handler/songies;`)
- Create: `lib/room/linux_link_registration.dart` (AppImage: on start, when `$APPIMAGE` is set, write `~/.local/share/applications/songies-links.desktop` pointing at it and run `xdg-mime default songies-links.desktop x-scheme-handler/songies`; only when the file is missing or points elsewhere)
- Test: `test/room/room_link_listener_test.dart`, `test/room/linux_link_registration_test.dart`, `test/tool/packaging_files_test.dart` (extend)

**Interfaces:**
- Consumes: `parseRoomCode` (Task 2), `roomInviteProvider` (Task 5).
- Produces: `class RoomLinkListener { RoomLinkListener(Stream<Uri> links, void Function(String code) onCode); }` — every link `parseRoomCode` accepts calls `onCode` once (the same link twice within 2 s counts once); others are ignored. `main.dart` sets `roomInviteProvider` to the code; Task 7 handles it.
- `Future<bool> registerLinuxLinks({required String? appImage, required Directory applications, required Future<void> Function(List<String> args) xdgMime})` — returns whether it wrote.

- [ ] **Step 1: Failing tests:** `songies://room/ABCD2345` and `https://x/r/abcd-2345` → `onCode('ABCD2345')`; `songies://other` ignored; a repeat within 2 s counted once, after 2 s twice; Linux registration writes the file with `Exec="<appimage>" %u` and calls `xdg-mime` once, a second run with the same AppImage writes nothing, no `$APPIMAGE` writes nothing; packaging test finds the manifest's `songies` scheme, the `.desktop` `MimeType` and the installer's `URL Protocol`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**, including the platform files.
- [ ] **Step 4: Run** the three test files → PASS; `flutter build linux` and `flutter build apk --debug` succeed.
- [ ] **Step 5: Manual check (Linux, the build from step 4):** `xdg-open songies://room/ABCD2345` with Songies closed opens it; with Songies open, the running window gets it (no second window).
- [ ] **Step 6: Commit** `feat(room): room links open Songies`

### Task 7: Room UI

**Files:**
- Create: `lib/ui/room/room_button.dart` (people-icon button with the count), `lib/ui/room/room_panel.dart` (one `RoomPanel` body used by the desktop popup and the phone sheet; `showRoomPanel(context, ref)`), `lib/ui/room/room_strip.dart` (`RoomStrip` above the player bar and the mini player; `RoomChip` for the full-screen player), `lib/ui/room/room_islands.dart` (notices → islands; handles `roomInviteProvider`), `lib/ui/room/join_room_dialog.dart`
- Modify: `lib/ui/shell/player_bar.dart` (strip above, button next to `DevicesButton`; play/skip/seek/shuffle/repeat dimmed and inert unless `RoomGuesting.role == full`), `lib/ui/shell/mini_player.dart` and `lib/ui/shell/phone_shell.dart` (strip on top of the mini player), `lib/ui/now_playing/now_playing_header.dart` (`RoomChip`, room button), `lib/ui/now_playing/now_playing_queue.dart` (reorder/remove/jump only for `full`; host and idle unchanged), `lib/ui/widgets/song_menu.dart` and `lib/ui/playlist/playlist_page.dart` (as a guest: Play next / Add to queue only for `queue`/`full` and disabled for local tracks; playlist ⋯ gets `Listen together` when idle and signed in, which opens a room playing that playlist), `lib/app.dart` (mount `RoomIslands` next to `RemoteEndedIslands`)
- Modify: `android/app/src/main/kotlin/com/songies/songies/SharePlugin.kt` and `lib/youtube/share_intents.dart` (`shareText`)
- Modify: `docs/manual-test-checklist.md` ("Listen together" section)
- Test: `test/ui/room_panel_test.dart`, `test/ui/room_strip_test.dart`, `test/ui/room_islands_test.dart`, `test/ui/player_bar_test.dart` (extend)

**Interfaces:**
- Consumes: `roomServiceProvider`, `roomStatusProvider`, `roomNoticesProvider`, `roomInviteProvider` (Task 5); `formatRoomCode`, `roomLink` (Task 2); `Islands.of(context).show(...)`.
- Behaviour:
  - Panel, idle: `Listen together` with a button `Start a room` and a `Join a room` field (code or link; `parseRoomCode`); signed out: the panel says `You need a Songies account to join a room` with `Sign in`.
  - Panel, hosting: the link with `Copy` (desktop) or `Share link` + `Copy` (phone). `Share link` calls a new `shareText` method on the existing `songies/share` channel (`android/app/src/main/kotlin/com/songies/songies/SharePlugin.kt`: an `ACTION_SEND` `text/plain` chooser), exposed as `Future<void> shareText(String text)` in `lib/youtube/share_intents.dart`; the people (name, `Desktop`/`Phone` from `platform`, a role menu of the three labels, a remove button with a confirmation), `End room` with a confirmation.
  - Panel, guesting: host and people with their roles (read-only), `Leave`.
  - An invite code arriving: signed out → island `You need a Songies account to join a room` with `Sign in`; in a room or controlling a device → a dialog `Leave the current room?` / `Stop controlling <device>?` first; else `join`.
- [ ] **Step 1: Failing widget tests** (fake `RoomService` over the fake hub, `ui_harness.dart`): idle panel shows `Start a room` and `Join a room`; hosting panel shows `ABCD-2345`'s link, two people, the role menu changes a role through the service; guest strip reads `Listening with denis · can add songs` for `queue`; host strip reads `Your room · 2 listening`; as a `listener` the player bar's next button is disabled and the song menu has no Add to queue; as `queue` Add to queue is enabled and disabled for a local track; an invite code while signed out shows the sign-in island, while hosting shows the leave dialog; every island text listed in Global Constraints appears for its notice.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Full suite** `flutter analyze && flutter test` → clean; all pass except the two known stats timing tests.
- [ ] **Step 5: Manual checklist section:** two accounts on two devices (desktop and phone): open, share, join by link and by code; each role; host local file; guest stream failure; leave keeps playing; host kills the app; room full (needs 10, or test with a temporary lower `kRoomMaxPeople` in a debug build); old link; signed-out invite.
- [ ] **Step 6: Commit** `feat(room): Listen together screens`
