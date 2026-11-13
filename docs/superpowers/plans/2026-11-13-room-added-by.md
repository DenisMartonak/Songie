# Who Added Each Song (SON-33) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In a Listen together room, every queue row and the Now Playing
title show the profile picture of whoever put that song in the queue.

**Architecture:**
- The player tags each queue entry with the adder's user id and publishes
  the tags beside the queue.
- The room host sends each song's adder (`by`) and a `faces` table
  (name and picture per user id) in full states. Guests load the tags into
  their own player.
- A small widget looks the tag up in the room's faces.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase Realtime (through
`RoomChannel`), flutter_test with fake_async.

**Spec:** `docs/superpowers/specs/2026-11-13-room-added-by-design.md`

## Global Constraints

- Pictures only, with no visible "Added by" text. Tooltip and Semantics
  label carry the name.
- Every song in a room gets a face. An untagged entry on the host counts as
  the host's.
- No faces outside a room. None in the player bar or the mini player.
- The protocol `v` stays 1. New fields are optional, and older builds
  ignore them.
- Tags are user ids, not device ids.
- Picture sizes: 22 px on queue rows, 28 px on Now Playing.
- Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH`. Never
  boot the Android emulator.

## Review Focus

1. **The same song queued twice by two people** keeps both faces through
   move, shuffle on/off and remove. Covered in Task 1.
2. **A guest who left the room** still shows their face on their songs.
   Covered in Task 3.
3. **A person removes their song and another adds the same song** at the
   same spot. The guest must show the new face, because `_sameSongs` must
   compare `by`. Covered in Task 4.
4. **Someone changes their picture mid-room.** A new full state goes out:
   faces count as part of the window revision. Covered in Task 3.
5. **No picture uploaded, or the link fails.** The coloured initial shows.
   An older host that sends no `by` shows no face and does not crash.
   Covered in Task 6.

---

### Task 1: Player tags queue entries

**Files:**
- Modify: `lib/player/player_service.dart` (`PlayerState`, `_Entry`,
  `playQueue`, `addToQueue`, `appendToQueue`, `replaceQueueAroundCurrent`,
  `_emit`)
- Test: `test/player/player_queue_commands_test.dart`

**Interfaces:**
- Produces:
  - `PlayerState.addedBy: List<String?>`. It is in step with `queue`; the
    default is `const []`, meaning untagged. `copyWith` gains
    `List<String?>? addedBy`.
  - `String? get PlayerState.currentAddedBy`: the tag at `index`, or null
    if there is none.
  - `_Entry.addedBy` (`String?`).
  - Each of these gains an optional named `List<String?>? addedBy`
    parameter, in step with `tracks`, with null meaning untagged:
    - `playQueue(tracks, {startIndex, sourcePlaylistId, addedBy})`
    - `addToQueue(tracks, {addedBy})`
    - `appendToQueue(tracks, {addedBy})`
    - `replaceQueueAroundCurrent(tracks, index, {addedBy})`. The kept
      current entry takes `addedBy[index]`.

- [ ] **Step 1: Write the failing tests**
  - `'queue entries carry who added them through moves and shuffle'`:
    - Call `playQueue([a, b], addedBy: ['u1', 'u1'])`, then
      `addToQueue([c], addedBy: ['u2'])`, then
      `appendToQueue([c], addedBy: ['u3'])`.
    - Expect `addedBy == ['u1', 'u2', 'u1', 'u3']` (queue `a c b c`).
    - Then `move(3, 1)`: expect each tag to follow its entry, i.e. the
      second `c` keeps `'u3'`.
    - Then `setShuffle(true)` and `setShuffle(false)`: expect every
      `(queue[i].id, addedBy[i])` pair to be unchanged as a multiset, and
      the original order restored.
    - Then `removeAt` of the `'u2'` entry: expect `'u2'` gone and `'u3'`
      still there.
  - `'untagged commands leave tags null; currentAddedBy follows index'`:
    - Call `playQueue([a, b])`. Expect `addedBy == [null, null]` and
      `currentAddedBy == null`.
    - Then `replaceQueueAroundCurrent([a, b, c], 0, addedBy: ['h', 'g',
      'g'])`. Expect `currentAddedBy == 'h'`.

- [ ] **Step 2: Run them, expect FAIL**

  Run: `flutter test test/player/player_queue_commands_test.dart`
  Expected: compile errors (`addedBy` not defined).

- [ ] **Step 3: Implement**
  - In `_emit`, whenever the emitted `queue` is not identical to the
    previous one, set `addedBy` from `_queue`:
    `[for (final e in _queue) e.addedBy]`, unmodifiable. Every queue emit
    already builds `queue` from `_queue`, so this covers all paths without
    touching each emit site.
  - Commands set `_Entry.addedBy` from the parameter. If the list's length
    differs from `tracks.length`, ignore it.

- [ ] **Step 4: Run, expect PASS.** Also run `flutter test test/player`.

- [ ] **Step 5: Commit**
  `feat(player): tag queue entries with who added them (SON-33)`

### Task 2: Protocol carries adders and faces

**Files:**
- Modify: `lib/room/room_protocol.dart`
- Test: `test/room/room_protocol_test.dart`

**Interfaces:**
- Produces:
  - `class RoomFace { const RoomFace({required String name, String?
    avatarUrl}); }`. It has value `==` and `hashCode`.
    - `toJson()` gives `{'name', 'avatarUrl'}`.
    - `static RoomFace? fromJson(Object?)`.
  - `RoomSong.by` (`String?`, a user id). Wire key `'by'`, written only
    when non-null. A non-string decodes to null and does not invalidate the
    song.
  - `RoomStateMsg.faces`: `Map<String, RoomFace>`, default `const {}`.
    - Wire key `'faces'`, written only when non-empty.
    - On decode, bad entries are skipped and a non-map gives `{}`.
    - `RoomBeatMsg.over` copies `full.faces`.
  - `RoomPresence.avatarUrl` (`String?`). Wire key `'avatarUrl'`; lenient,
    so a non-string decodes to null.

- [ ] **Step 1: Write the failing tests**
  - `'songs carry who added them; faces round-trip'`:
    - A state with `songs: [yt with by 'u1']` and
      `faces: {'u1': RoomFace(name: 'ann', avatarUrl: 'https://x/a.jpg')}`
      round-trips with equal values.
    - With `by` and `faces` removed from the JSON, it still decodes, with
      `by == null` and `faces` empty.
    - `{'faces': {'u1': 3}}` decodes with `faces` empty.
  - Extend `'presence round-trips…'`: `avatarUrl` round-trips, and its
    absence gives null.
  - Extend the beat test: `beat.over(full).faces` is the same map as
    `full.faces`.

- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/room/room_protocol_test.dart`

- [ ] **Step 3: Implement** the fields above.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**
  `feat(room): songs carry who added them, states carry faces (SON-33)`

### Task 3: Host tags requests and sends faces

**Files:**
- Modify: `lib/room/room_host.dart`
- Test: `test/room/room_host_test.dart`

**Interfaces:**
- Consumes: Task 1's `addedBy` parameters and `PlayerState.addedBy`, and
  Task 2's `RoomSong.by`, `RoomFace`, `RoomStateMsg.faces` and
  `RoomPresence.avatarUrl`.
- Produces:
  - `Map<String, RoomFace> get RoomHost.faces`: everyone ever present in
    this room, host included, by user id. Entries are never removed.
  - `Stream<Map<String, RoomFace>> get RoomHost.facesChanges`.

- [ ] **Step 1: Write the failing tests**
  - `'songs carry who added them; untagged ones are the host's'`:
    - The host plays `[a]`, then guest `g` (user `ug`, Queue role) sends
      `addToEnd [b]`.
    - The last full state has `songs[0].by == 'uh'` and
      `songs[1].by == 'ug'`.
    - `faces.keys` is `{'uh', 'ug'}`, and `faces['ug'].name == 'Name g'`.
  - `'a full guest's playSongs are tagged with that guest'`: every
    `by == 'ug'`.
  - `'a guest who left keeps their face on their songs'`:
    - After the add, the guest channel calls `leave()`. A later full state
      (force one with another device's hello) still has
      `faces['ug']`.
  - `'a new picture sends the full state again'`:
    - The guest re-joins with `avatarUrl: 'https://x/new.jpg'`.
    - The next send within 2.3 s is a `RoomStateMsg` with a new `rev`, and
      `faces['ug'].avatarUrl` is the new link.
  - `'faces list only the adders in the window'`: with only host songs,
    `faces.keys == {'uh'}`.

- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/room/room_host_test.dart`

- [ ] **Step 3: Implement**
  - **Faces:** in `_onPresence`, record
    `RoomFace(name: p.name, avatarUrl: p.avatarUrl)` per `p.userId`, and
    emit on change. Seed with `_me` in `start()`.
  - **Tagging requests:** in `_apply`, `playSongs`, `addNext` and
    `addToEnd` pass `addedBy: List.filled(n, who.userId)`.
  - **Building songs:** `_build` sets
    `by: s.addedBy.elementAtOrNull(i) ?? _me.userId`. `faces` holds only
    the `by` ids in the window.
  - **Window change:** the "same" check also compares the window's `by`
    list and its faces map, kept as `_sentBys` and `_sentFaces`. So a tag
    or picture change bumps `_rev` and sends a full state.

- [ ] **Step 4: Run, expect PASS.** Also run `flutter test test/room`.

- [ ] **Step 5: Commit**
  `feat(room): host tags guests' songs and sends their faces (SON-33)`

### Task 4: Guest loads tags and keeps faces

**Files:**
- Modify: `lib/room/room_guest.dart`
- Test: `test/room/room_guest_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `Map<String, RoomFace> get RoomGuest.faces`: from the latest full
    state, default `{}`.
  - `Stream<Map<String, RoomFace>> get RoomGuest.facesChanges`: emits when
    a full state's faces differ from the previous ones.

- [ ] **Step 1: Write the failing tests**
  - `'the guest's queue carries who added each song'`:
    - The host plays `[a]`, and a second Queue-role device asks
      `addToEnd [b]`. Use the rig's hub: send a `RoomRequestMsg` from
      device `'q'` after `hub.channelFor('q').join(who('uq', 'q'))`, with
      the host giving it the queue role.
    - After settling, `guestPlayer.state.addedBy == ['uh', 'uq']`.
    - `guest.faces.keys` contains `'uq'`.
  - `'another person's copy of the same song updates the face'`:
    - The host queue is `[a, b]` with `b` added by `uq`.
    - The host removes `b`, then a full guest `g` adds `b` at the same
      place.
    - The guest's `addedBy[1]` becomes `'ug'` (the song ids are
      unchanged).

- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/room/room_guest_test.dart`

- [ ] **Step 3: Implement**
  - In `_apply`, build the playable tags in step with `playable` from
    `songs[i].by`.
  - Pass them to `playQueue(..., addedBy:)` and
    `replaceQueueAroundCurrent(..., addedBy:)`.
  - `_sameSongs` also compares `by`.
  - Set `faces` from each `RoomStateMsg` in `_onMessage`, not from beats,
    which carry the full state's faces.

- [ ] **Step 4: Run, expect PASS.** Also run `flutter test test/room`.

- [ ] **Step 5: Commit**
  `feat(room): guests follow who added each song (SON-33)`

### Task 5: Service, status and providers

**Files:**
- Modify:
  - `lib/room/room_service.dart`
  - `lib/ui/room/room_button.dart`
  - `lib/ui/room/room_panel.dart:94`
  - `lib/ui/room/join_room_dialog.dart:99`
  - `lib/ui/playlist/playlist_page.dart:554`
  - `test/helpers/room_rig.dart`
- Test: `test/room/room_service_test.dart`

**Interfaces:**
- Consumes: `RoomHost.faces` / `facesChanges` and `RoomGuest.faces` /
  `facesChanges`.
- Produces:
  - `RoomService.open({userId, name, avatarUrl, play})` and
    `join(code, {userId, name, avatarUrl})`. `avatarUrl` is an optional
    `String?` and goes into `_presence`. Callers pass
    `profile.avatarUrl`.
  - `RoomHosting.faces` and `RoomGuesting.faces`:
    `Map<String, RoomFace>`, default `const {}`.
  - `RoomHosting.me` and `RoomGuesting.me`: the user id `String`. On the
    host, an untagged entry maps to `me`.
  - `roomFacesProvider` (`Provider<RoomFaces?>`), null outside a room.
    `class RoomFaces { final Map<String, RoomFace> faces; final String?
    untagged; RoomFace? of(String? addedBy); }`
    - `untagged` is the host's own id while hosting, and null as a guest.
    - `of` resolves `addedBy ?? untagged`.

- [ ] **Step 1: Write the failing tests**
  - `'hosting status carries faces with the host's picture'`:
    - `open(userId: 'u9', name: 'denis', avatarUrl: 'https://x/d.jpg')`.
    - The status `faces['u9'].avatarUrl == 'https://x/d.jpg'`.
  - `'a guest's status carries the host's faces'`:
    - After the join, `(status as RoomGuesting).faces` contains the host's
      id.

- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/room/room_service_test.dart`

- [ ] **Step 3: Implement**
  - Thread `avatarUrl` through `open`, `join` and `_presence`.
  - Republish the status on `facesChanges`, as for roles.
  - Add the provider next to `roomGuestRoleProvider`.
  - Update the three UI callers and the rig.

- [ ] **Step 4: Run, expect PASS.** Also run `flutter analyze`.

- [ ] **Step 5: Commit**
  `feat(room): room status carries faces (SON-33)`

### Task 6: Faces in the queue and on Now Playing

**Files:**
- Modify:
  - `lib/ui/account/avatar.dart`: extract a public
    `PersonAvatar({required String name, String? url, required double
    size})` from `AccountAvatar`'s picture-or-initial body. `AccountAvatar`
    then uses it.
  - `lib/ui/now_playing/now_playing_queue.dart`: `_QueueRow`
  - `lib/ui/now_playing/now_playing_page.dart`: the title `Row` at about
    line 789
- Create: `lib/ui/room/room_face.dart`
- Test: `test/ui/now_playing/now_playing_room_test.dart`

**Interfaces:**
- Consumes: `roomFacesProvider`, `PlayerState.addedBy` and
  `currentAddedBy`.
- Produces: `class RoomFaceDot extends ConsumerWidget { const
  RoomFaceDot({required String? addedBy, required double size}); }`
  - It is `SizedBox.shrink()` when `roomFacesProvider` is null or `of()`
    gives null.
  - Otherwise it shows `Tooltip(message: name)` around
    `Semantics(label: name, child: PersonAvatar(...))`.
  - Key: `Key('room.face.$userId')`.

- [ ] **Step 1: Write the failing tests** (in
  `now_playing_room_test.dart`, using `RoomRig`)
  - `'queue rows and the title show who added each song'`:
    - As host denis (`u9`), play `[a]`; a Queue guest adds `b`.
    - Queue rows show `room.face.u9` on `a` and the guest's face on `b`.
    - The Now Playing title shows `room.face.u9`.
    - No text `'Added by'` is shown.
  - `'no picture shows the initial'`: with no `avatarUrl`, the face shows
    the uppercase first letter of the name.
  - `'outside a room no faces'`: play `[a]` without a room, and find no
    `room.face.*`.
  - `'an older host's songs show no face'`: give `RoomFaces` empty `faces`
    and a null `untagged` through a provider override, and expect no face
    and no exception.

- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/ui/now_playing/now_playing_room_test.dart`

- [ ] **Step 3: Implement**
  - Add `RoomFaceDot(addedBy: …, size: 22)` in `_QueueRow` before
    `FavoriteStar`, with 8 px spacing.
    - The row gets `addedBy` from `queue`'s parallel
      `state.addedBy.elementAtOrNull(q)`.
    - Add `addedBy` to the queue's `select`, so rows rebuild when tags
      change.
  - Add `RoomFaceDot(addedBy: currentAddedBy, size: 28)` before the
    Now Playing `FavoriteStar`, also with 8 px spacing.

- [ ] **Step 4: Run, expect PASS.** Then run `dart format lib test`,
  `flutter analyze` and the full `flutter test`.

- [ ] **Step 5: Commit**
  `feat(room): show who added each song in the queue and Now Playing
  (SON-33)`
