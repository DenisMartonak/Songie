# Remote Control (Supabase Realtime, step 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every signed-in device can see the user's other running devices and control one of them (transport, volume, shuffle/repeat, queue edits, Play on / Add to queue on) from this device's player bar, Now Playing and queue.

**Architecture:** One private Realtime channel per user (`remote:<user id>`) carries Presence (who is online and what they play) and three Broadcast events (`state`, `command`, `hello`); nothing is stored. A `RemoteHost` on every signed-in device publishes its `PlayerService` state and applies commands addressed to it. A `RemoteController` holds the selected device's latest state. The player UI reads a `PlayerView` (local or remote) through `playerViewProvider`, so no screen is duplicated.

**Tech Stack:** Flutter, Riverpod, `supabase_flutter` (realtime_client 2.13.2: `track`, `presenceState`, `onPresenceSync`, `onBroadcast`, `sendBroadcastMessage`), drift, `fake_async` for timer tests, `uuid` for command ids.

**Spec:** `docs/superpowers/specs/2026-11-06-remote-control-design.md`

Flutter is at `~/development/flutter/bin` (not on PATH): run commands with
`export PATH=$HOME/development/flutter/bin:$PATH` first. Memory on this machine is limited: run focused tests while iterating and the full suite once per task; the stats "… under 500 ms" timing tests fail under load (on main too). Work on branch `remote-control` in `.worktrees/remote-control`.

## Global Constraints

- Channel topic exactly `remote:<user id>`, `private: true`. No tables, nothing stored. The `sync:<user id>` topic and its policies are unchanged.
- Every message carries `v`; `kRemoteProtocol = 1`. Decoding never throws: malformed, unknown-op or other-`v` messages decode to `null` and are ignored. Message handling never throws into a channel callback.
- Presence payload: `{v, deviceId, name, platform, appVersion, playing, title}`.
- State: `{v, from, epoch, offset, index, queue, playing, buffering, position_ms, at_ms, duration_ms, volume, shuffle, repeat, notice}`; debounced to at most one per **250 ms**, plus every **5 s** while playing; sent only while at least one other device is present; at most **2,000** queue ids around the current one, with `offset` the absolute index of `queue[0]`.
- Command: `{v, to, id, op, args, epoch?}`; ops `play pause toggle next previous seek volume shuffle repeat playAt remove move playTracks addNext addToEnd`. A host acts only on `to` = its device id. Hello: `{v, to}` → full state at once.
- Timings: hello unanswered **5 s** → "<device> didn't answer" and back to This device; selected device gone from Presence → "Lost connection to <device>", back to This device after **15 s** (local playback stays paused).
- Device id = `syncStampProvider.deviceId`. Name = `kDeviceName` setting if set, else Android model, else `Platform.localHostname`.
- Always on for signed-in devices, no setting. Signed out: no devices button, no channel joined. Sign out / account switch: leave the channel, controller back to This device.
- Picking a remote pauses local playback. The play button in remote view never starts local playback. Media keys, notification and lock screen keep controlling the local player.
- Copy (exact): "This device", "Playing on <device>", "Connecting to <device>…", "Lost connection to <device>", "<device> didn't answer", "No other devices online", "Update Songies to control this device", "Play on <device>", "Add to queue on <device>", "Unknown song".
- Not in this step: move playback here, opt-out setting, controlling a closed app, listen together.

## Rulings made by this plan (each with its cost if wrong)

- **P1 — index guard:** `queueEpoch` only changes on `playQueue`, so two quick removes from one controller would otherwise shift indexes under the second. `playAt`, `remove` and `move` carry both `epoch` and `track` (the id the controller saw at `index`/`from`). The host acts only if both match; otherwise it does nothing and sends fresh state. Cost: one extra field per command.
- **P2 — unknown ids wait briefly:** a song stored on the controller just now (a search result) has not synced to the host yet. The controller calls `cloudSync.syncNow()` before sending `playTracks`/`addNext`/`addToEnd`; the host retries unknown ids every 500 ms for up to **5 s** before dropping them. Cost: up to 5 s before a brand-new song plays remotely.
- **P3 — other local starts end the remote view:** the playlist page (Play all, Shuffle, row tap, Add to queue) goes through `playerViewProvider`, so it plays on the selected device. Anything else that starts local playback (Home, search, radio, media keys) switches the view back to This device. Cost: a search tap while viewing a remote plays here, not there.
- **P4 — one menu entry per device:** song and playlist ⋯ menus get "Play on <device>" / "Add to queue on <device>" for each compatible online device (max 3 shown; most users have 2–3 devices). Cost: a long menu for a user with many devices.
- **P5 — placeholder track:** an id the controller lacks shows as a `Track` with `source: 'remote'` (`kRemoteUnknownSource`), title "Unknown song", empty artist; the lyrics view shows its empty state for it without a lookup, and its song menu is not offered.

## Review Focus

1. **A song chosen on the controller that the host doesn't have yet** (just searched; sync lagging) → it plays on the host within ~5 s, not silently nothing (P2) — test in Task 3 (`unknown ids are retried until they arrive`).
2. **Two quick queue edits from the controller before the host's next state** (remove row 3 then row 5) → both apply to the songs the user tapped, never a neighbour (P1) — test in Task 3 (`rapid removes hit the tapped songs`) and Task 4 (optimistic indexes).
3. **Host's queue replaced while a controller edits it** (the host user starts a new playlist) → the stale `remove` does nothing and fresh state arrives — test in Task 3 (`stale epoch is ignored with fresh state`).
4. **The selected device sleeps (Android background) and comes back within 15 s** → strip says lost, then returns to normal after a new `hello` answer, no jump to This device — test in Task 4 (`presence returns within 15 s`).
5. **A queue longer than 2,000 with the current song near the end** → the window still contains the current song and the controller's indexes stay absolute — test in Task 3 (`queue window`) and Task 4 (`offset keeps indexes absolute`).

---

### Task 1: Protocol messages

**Files:**
- Create: `lib/remote/remote_protocol.dart`
- Test: `test/remote/remote_protocol_test.dart`

**Interfaces (produces):**
- `const int kRemoteProtocol = 1;` `const int kRemoteQueueWindow = 2000;`
- `class RemotePresence { deviceId, name, platform, appVersion: String; playing: bool; title: String?; v: int; bool get compatible => v == kRemoteProtocol; Map<String, Object?> toJson(); static RemotePresence? fromJson(Object? j) }` — decodes any integer `v` (so old/new versions can be listed greyed); null without a non-empty `deviceId` and `name`.
- `sealed class RemoteMessage { String get event; Map<String, Object?> toJson(); static RemoteMessage? decode(String event, Object? payload) }` — null for `v != kRemoteProtocol`, unknown event, or bad fields.
- `class RemoteState extends RemoteMessage` (event `state`): `from: String; epoch, offset, index: int; queue: List<String>; playing, buffering, shuffle: bool; positionMs, atMs: int; durationMs: int?; volume: double; repeat: RepeatMode; notice: ({String title, String reason})?`. JSON keys snake_case as in Global Constraints; `repeat` as `off|all|one`; `notice` as `{title, reason}` or null. `index` is absolute (−1 when empty).
- `enum RemoteOp { play, pause, toggle, next, previous, seek, volume, shuffle, repeat, playAt, remove, move, playTracks, addNext, addToEnd }` (wire name = enum name).
- `class RemoteCommand extends RemoteMessage` (event `command`): `to, id: String; op: RemoteOp; args: Map<String, Object?>; epoch: int?`. Args per op (decode rejects missing/wrong-typed): `seek {ms:int≥0}`, `volume {v:num 0..1}`, `shuffle {on:bool}`, `repeat {mode:off|all|one}`, `playAt {index:int, track:String}` + epoch, `remove {index:int, track:String}` + epoch, `move {from:int, to:int, track:String}` + epoch, `playTracks {ids:List<String> non-empty, start:int, playlist:String?}`, `addNext {ids}`, `addToEnd {ids}`; others `{}`.
- `class RemoteHello extends RemoteMessage` (event `hello`): `to: String`.

- [ ] **Step 1: Write the failing tests**

`round trips` for each class (`decode(m.event, jsonDecode(jsonEncode(m.toJson())))` equals the original field by field, incl. `notice` null and set, `durationMs` null). `rejects` cases, each `isNull`: `v: 2` state; unknown event `'ping'`; `op: 'explode'`; `seek` with `ms: '10'`; `volume` with `v: 1.5`; `playAt` without `epoch`; `playTracks` with `ids: []`; payload `'nope'` and `null`; `queue: [1, 2]`. `presence keeps other versions`: `{v: 2, deviceId: 'd', name: 'Desk', …}` decodes with `compatible == false`; missing `deviceId` → null.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/remote/remote_protocol_test.dart`
Expected: FAIL (file `remote_protocol.dart` not found).

- [ ] **Step 3: Implement `lib/remote/remote_protocol.dart`**

Hand-written `toJson`/`fromJson` (no codegen); every cast guarded (`is int`, `is List` with all elements `String`); wrap the whole decode in `try … on Object { return null; }` as a last guard.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/remote/remote_protocol_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** — `feat(remote): protocol messages`

---

### Task 2: The channel, its fake, and the Realtime policies

**Files:**
- Create: `lib/remote/remote_channel.dart`
- Create: `supabase/migrations/20261107120000_remote_control.sql`
- Create: `test/helpers/fake_remote_hub.dart`
- Modify: `docs/supabase.md` (apply the new migration; what it allows)
- Test: `test/remote/fake_remote_hub_test.dart`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `abstract class RemoteChannel { Future<void> join(RemotePresence me); Future<void> updatePresence(RemotePresence me); Stream<List<RemotePresence>> get presences; List<RemotePresence> get present; Future<void> send(RemoteMessage m); Stream<RemoteMessage> get messages; Future<void> leave(); }` — `presences`/`present` include this device's own entry; `messages` never contains this device's own sends.
  - `class SupabaseRemoteChannel implements RemoteChannel { SupabaseRemoteChannel(SupabaseClient Function() client, String userId); }` — `channel('remote:$userId', opts: RealtimeChannelConfig(private: true, key: me.deviceId))`; `onPresenceSync` → flatten `presenceState()` payloads through `RemotePresence.fromJson` (drop nulls; one entry per deviceId, latest wins); `onBroadcast` for `state`, `command`, `hello` → `RemoteMessage.decode`, nulls dropped, every callback body in `try/catch` logged with `AppLog.w`; `track(me.toJson())` after `subscribed`; `send` = `sendBroadcastMessage(event: m.event, payload: m.toJson())`. Reconnect is the client's own. Not unit-tested (thin, like `SupabaseCloudRemote.changes`).
  - Test helper `class FakeRemoteHub { RemoteChannel channelFor(String deviceId); void drop(String deviceId); void restore(String deviceId); List<RemoteMessage> sent; }` — delivers sends to every other joined channel synchronously-async (`scheduleMicrotask`), sends each message through JSON encode/decode (so tests exercise the protocol), and keeps presence lists in step; `drop` removes a device from presence and stops delivery both ways until `restore`.

- [ ] **Step 1: Write the migration**

Two policies on `realtime.messages`, both `to authenticated`, both with
`realtime.messages.extension in ('broadcast', 'presence') and (select realtime.topic()) = 'remote:' || (select auth.uid())::text and realtime.messages.topic = (select realtime.topic())`:
"remote: users receive on their own remote topic" (`for select using …`) and "remote: users send on their own remote topic" (`for insert with check …`). Header comment: why no table (spec, How it is built).

- [ ] **Step 2: Write the failing hub tests**

`delivers to others, not self`; `presence lists every joined device and updates`; `drop hides a device and stops delivery until restore`; `leave removes presence`; `a payload that fails to decode is not delivered`.

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/remote/fake_remote_hub_test.dart` — Expected: FAIL (missing files).

- [ ] **Step 4: Implement `remote_channel.dart` and `fake_remote_hub.dart`**

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test test/remote/ && flutter analyze lib/remote test/helpers` — Expected: PASS, no issues.

- [ ] **Step 6: Apply the migration to the local Supabase and check RLS**

Run `supabase db reset` (see `docs/supabase.md`). As user A, `insert into realtime.messages(topic, extension, payload, event, private) values ('remote:<B id>', 'broadcast', '{}', 'x', true)` is refused and `'remote:<A id>'` is accepted. Record the result in the commit message. If no local Supabase is running, say so in the task report rather than skipping silently.

- [ ] **Step 7: Commit** — `feat(remote): realtime channel and policies`

---

### Task 3: The host

**Files:**
- Create: `lib/remote/remote_host.dart`
- Modify: `lib/library/library_repository.dart` (add `tracksByIds`)
- Test: `test/remote/remote_host_test.dart`, `test/library/library_repository_test.dart` (one test for `tracksByIds`)

**Interfaces:**
- Consumes: Tasks 1–2; `PlayerService` (`states`, `state`, `queueEpoch`, `play`, `pause`, `togglePlay`, `next`, `previous`, `seek`, `setVolume`, `setShuffle`, `cycleRepeat`, `playAt`, `removeAt`, `move`, `playQueue`, `addToQueue`, `appendToQueue`).
- Produces:
  - `LibraryRepository.tracksByIds(List<String> ids) → Future<Map<String, Track>>` (live rows only).
  - `class RemoteHost { RemoteHost({required RemoteChannel channel, required PlayerService player, required RemotePresence Function(PlayerState s) presence, required Future<Map<String, Track>> Function(List<String> ids) lookup, int Function()? nowMs}); Future<void> start(); Future<void> stop(); }` — `presence(s)` builds this device's presence from the state (Task 5 supplies it). `repeat` command sets the mode by calling `cycleRepeat()` until it matches.

Behaviour (spec, Messages and Behaviour, plus P1, P2):
- On `start`: `join(presence(player.state))`; listen to `player.states` and `channel.messages`.
- Presence: `updatePresence` only when `playing` or the current track id changes.
- State: debounced 250 ms after any player change; 5 s heartbeat timer while playing; nothing sent while `present` holds only this device; `hello` with `to` = me → state at once (no debounce). `at_ms` = `nowMs()` when built. Window: `offset = max(0, min(index - 1000, len - 2000))`, `queue` = ids `[offset, offset + 2000)`.
- Commands with `to` ≠ me ignored. `playAt`/`remove`/`move`: act only if `epoch == player.queueEpoch` and the id at the absolute `index`/`from` equals `track`; else no-op + fresh state. Unknown ids in `playTracks`/`addNext`/`addToEnd`: re-lookup every 500 ms up to 5 s, then drop the rest; `playTracks` start = the first kept id at or after `start` (none kept → do nothing). Any thrown error → `AppLog.w` + fresh state.

- [ ] **Step 1: Write the failing tests**

Use `fake_async`, `FakeRemoteHub` (host `'h'`, controller `'c'`), a real `PlayerService` over `FakeAudioBackend` (copy the `track()`/`_Resolver` helpers from `test/player/player_queue_commands_test.dart`), and a map-backed `lookup`. Tests (each asserting on `hub.sent` and `player.state`):
`each op reaches the player` (one `test` per op: e.g. `seek {ms: 30000}` → position 30 s; `repeat {mode: 'one'}` → `RepeatMode.one`; `move` → order and index follow);
`commands for another device are ignored`;
`hello is answered at once with full state`;
`no state while alone` (only `'h'` joined; player changes; `sent` has no `RemoteState`);
`changes are debounced to one state per 250 ms` (5 changes in 100 ms → 1 state after 250 ms);
`heartbeat every 5 s while playing, none while paused`;
`stale epoch is ignored with fresh state` (controller saw epoch 1; host `playQueue` again; `remove` → queue unchanged, a new state sent);
`rapid removes hit the tapped songs` (queue a,b,c,d,e; `remove {index:2, track:'c'}` then `remove {index:4, track:'e'}` with the same epoch → the first removes c; the second's index 4 no longer holds e → no-op + fresh state; then `remove {index:3, track:'e'}` → e removed; queue a,b,d);
`unknown ids are retried until they arrive` (`addNext {ids:['x']}`, `x` added to lookup at 2 s → queued; another id never arriving is dropped at 5 s);
`queue window` (3,000 tracks, index 2,900 → `offset` 1,000, 2,000 ids, `queue[index - offset]` is the current id);
`a failing command answers with state and doesn't throw` (`seek` on an empty player);
`presence follows play and song changes only` (volume change → no `updatePresence`).
Plus `tracksByIds returns live rows only` in the repository test.

- [ ] **Step 2: Run them to see them fail** — `flutter test test/remote/remote_host_test.dart` → FAIL.
- [ ] **Step 3: Implement `tracksByIds` and `RemoteHost`**
- [ ] **Step 4: Run** `flutter test test/remote/ test/library/library_repository_test.dart` → PASS.
- [ ] **Step 5: Commit** — `feat(remote): host publishes state and applies commands`

---

### Task 4: The controller

**Files:**
- Create: `lib/remote/remote_controller.dart`
- Test: `test/remote/remote_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2; `PlayerState`, `Track`, `RepeatMode`.
- Produces:
  - `const kRemoteUnknownSource = 'remote';`
  - `enum RemoteLinkStatus { connecting, connected, lost }`
  - `class RemoteLink { RemotePresence device; RemoteLinkStatus status; }`
  - `enum RemoteEndReason { deselected, noAnswer, lost, signedOut }`
  - `class RemoteController { RemoteController({required RemoteChannel channel, required String deviceId, required Future<Map<String, Track>> Function(List<String> ids) lookup, int Function()? nowMs, String Function()? newId}); Stream<RemoteLink?> get links; RemoteLink? get link; Stream<PlayerState> get states; PlayerState get state; Stream<RemoteEndReason> get ended; Future<void> select(RemotePresence device); void deselect([RemoteEndReason r = RemoteEndReason.deselected]); }` plus command methods matching `PlayerView` (Task 5): `play, pause, togglePlay, next, previous, seek(Duration), setVolume(double), setShuffle(bool), setRepeat(RepeatMode), playAt(int), removeAt(int), move(int, int), playTracks(List<String> ids, {int startIndex, String? sourcePlaylistId}), addNext(List<String> ids), addToEnd(List<String> ids)`.
  - `PlayerState` built from `RemoteState`: `queue` = looked-up tracks for the window (placeholder per P5 for missing ids), `index = state.index - state.offset`; indexes the UI passes to `playAt/removeAt/move` are window-relative and the controller adds `offset` before sending, and puts the window entry's id in `track`.

Behaviour: `select` sends `hello`, link `connecting`; first `RemoteState` from that device → `connected`; none in 5 s → `ended(noAnswer)` and link null. While `playing`, a 250 ms ticker re-emits state with `position = position_ms + (now − at_ms)` capped at `duration_ms`. Commands update `state` at once (play/pause/toggle, seek, volume, shuffle, repeat, playAt, remove, move, next/previous ±1 within bounds with position 0); `playTracks/addNext/addToEnd` wait for the host. The next `RemoteState` replaces the optimistic one. Device absent from `channel.presences` → `lost`; back within 15 s → `hello` again, then `connected`; not back → `ended(lost)`. States `from` another device are ignored; nothing sent while no link.

- [ ] **Step 1: Write the failing tests** (`fake_async`, `FakeRemoteHub`, a scripted host that answers `hello` with a given `RemoteState`)

`hello on select, connected on first state`; `no answer in 5 s ends with noAnswer`; `position runs on while playing and stops at the duration` (state at 10 s, 3 s later `state.position` = 13 s; duration 12 s → 12 s); `paused position stays`; `optimistic seek then corrected by the next state`; `offset keeps indexes absolute` (offset 1,000: `removeAt(5)` sends `index: 1005` with that entry's id); `unknown ids show as Unknown song`; `presence lost shows lost and ends after 15 s`; `presence returns within 15 s` (drop at 0, restore at 10 s → `hello` re-sent, `connected` after its answer, no `ended`); `states from another device are ignored`; `deselect stops the ticker and sends nothing more`.

- [ ] **Step 2: Run them to see them fail** — `flutter test test/remote/remote_controller_test.dart` → FAIL.
- [ ] **Step 3: Implement `RemoteController`**
- [ ] **Step 4: Run** `flutter test test/remote/` → PASS.
- [ ] **Step 5: Commit** — `feat(remote): controller with live position and optimistic commands`

---

### Task 5: PlayerView, providers and wiring

**Files:**
- Create: `lib/remote/player_view.dart`, `lib/remote/device_name.dart`
- Modify: `lib/providers.dart`, `lib/main.dart`
- Test: `test/remote/player_view_test.dart`, `test/remote/device_name_test.dart`, `test/providers_test.dart`

**Interfaces:**
- Consumes: Tasks 3–4; `accountStateProvider` (`SignedIn`/`SignedOut`), `syncStampProvider`, `settingsRepositoryProvider` + `kDeviceName`, `readDeviceSummary`, `appVersion`, `cloudSyncProvider.syncNow`, `libraryRepositoryProvider`.
- Produces:
  - `abstract class PlayerView { Stream<PlayerState> get states; PlayerState get state; bool get isRemote; Future<void> play(); pause(); togglePlay(); next(); previous(); seek(Duration d); setVolume(double v); setShuffle(bool on); setRepeat(RepeatMode m); playAt(int i); removeAt(int i); Future<void> move(int from, int to); Future<void> playTracks(List<Track> tracks, {int startIndex = 0, String? sourcePlaylistId}); addNext(List<Track> tracks); addToEnd(List<Track> tracks); }` (all `Future<void>`). `LocalPlayerView(PlayerService)` maps `addNext`→`addToQueue`, `addToEnd`→`appendToQueue`, `setRepeat`→`cycleRepeat` until it matches. `RemotePlayerView(RemoteController, Future<void> Function() syncNow)` sends ids, calling `syncNow()` first for `playTracks/addNext/addToEnd` (P2).
  - `Future<String> remoteDeviceName({required Future<String?> Function() storedName, required bool isAndroid, required Future<DeviceSummary> Function() readDevice, required String hostname})`.
  - Providers: `remoteChannelProvider` (overridden in `main()` with a factory `RemoteChannel Function(String userId)`), `remoteHostFollowerProvider` (joins on `SignedIn`, stops on `SignedOut`/account change; also builds the controller), `remoteControllerProvider` (`RemoteController?`, null signed out), `remoteDevicesProvider` (`StreamProvider<List<RemotePresence>>`, others only, empty signed out), `remoteLinkProvider` (`StreamProvider<RemoteLink?>`), `remoteEndedProvider` (stream of `(RemotePresence, RemoteEndReason)` for the island), `playerViewProvider` (`Provider<PlayerView>`: remote while a link exists, else local), `playerViewStateProvider` (`StreamProvider<PlayerState>` seeded like `playerStateProvider`).
  - `Future<void> selectRemote(WidgetRef/Ref ref, RemotePresence d)`: pauses the local player, then `controller.select(d)`.
  - P3: while a link exists, the local player becoming `playing` calls `controller.deselect()`.

- [ ] **Step 1: Write the failing tests**

`device_name_test`: stored name wins; Android uses the model; desktop uses the hostname; a blank stored name is ignored.
`player_view_test`: `LocalPlayerView` passes each call through (`setRepeat(RepeatMode.all)` from off → `all`); `RemotePlayerView.addNext` calls `syncNow` then sends `addNext` with ids.
`providers_test` (with `FakeRemoteHub` and a fake account service): `signed out joins nothing and lists no devices`; `signing in joins with this device's presence`; `playerViewProvider switches to remote on select and back on deselect`; `selecting a remote pauses local playback`; `local playback starting ends the remote view` (P3); `signing out leaves and returns to This device`; `remoteDevicesProvider excludes this device`.

- [ ] **Step 2: Run them to see them fail** — `flutter test test/remote/ test/providers_test.dart` → FAIL.
- [ ] **Step 3: Implement**, wiring `main.dart`: `remoteChannelProvider.overrideWithValue((uid) => SupabaseRemoteChannel(() => Supabase.instance.client, uid))`, and read `remoteHostFollowerProvider` where `cloudSyncFollowerProvider` is read.
- [ ] **Step 4: Run** `flutter test test/remote/ test/providers_test.dart && flutter analyze` → PASS, clean.
- [ ] **Step 5: Commit** — `feat(remote): player view and wiring`

---

### Task 6: Player UI reads the view

**Files:**
- Modify: `lib/ui/shell/player_bar.dart`, `lib/ui/shell/mini_player.dart`, `lib/ui/now_playing/now_playing_page.dart`, `now_playing_header.dart`, `now_playing_controls.dart`, `now_playing_queue.dart`, `lib/ui/lyrics/lyrics_view.dart`, `lib/ui/lyrics/lyrics_strip.dart`, `lib/ui/playlist/playlist_page.dart` (play/shuffle/row tap/Add to queue only, P3)
- Test: `test/ui/remote_view_test.dart`; existing tests in `test/ui/` must still pass

**Interfaces:** Consumes `playerViewProvider`, `playerViewStateProvider`, `kRemoteUnknownSource` (Task 4–5). In the listed files, replace `playerStateProvider` → `playerViewStateProvider` and `playerServiceProvider` → `playerViewProvider` (with the renamed calls: `addToQueue`→`addNext`, `cycleRepeat`→`setRepeat(next)`, `playQueue`→`playTracks`). Every other file keeps the local providers. Lyrics: a current track with `source == kRemoteUnknownSource` shows the lyrics empty state without a lookup (P5); the song menu isn't opened for it.

- [ ] **Step 1: Write the failing widget tests** (override `playerViewProvider` with a fake remote view)

`player bar shows the remote song and its play sends play to the remote, local player untouched`; `queue reorder and remove go to the view`; `Unknown song shows for a missing id and has no song menu`; `lyrics don't look up an unknown song`; `playlist Play all plays on the selected device`.

- [ ] **Step 2: Run them to see them fail** — `flutter test test/ui/remote_view_test.dart` → FAIL.
- [ ] **Step 3: Make the swap**
- [ ] **Step 4: Run** `flutter test test/ui/ && flutter analyze` → PASS, clean.
- [ ] **Step 5: Commit** — `feat(remote): player bar, Now Playing and queue follow the selected device`

---

### Task 7: Devices button, picker and strip

**Files:**
- Create: `lib/ui/remote/devices_button.dart` (button + picker: popup menu on desktop, bottom sheet on phone), `lib/ui/remote/remote_strip.dart`
- Modify: `lib/ui/shell/player_bar.dart` (button beside the lyrics toggle; strip above the bar), `lib/ui/now_playing/now_playing_header.dart` (button; strip under the header), `lib/ui/shell/mini_player.dart` (strip text replaces the artist line while remote)
- Test: `test/ui/devices_picker_test.dart`

**Interfaces:** Consumes `remoteDevicesProvider`, `remoteLinkProvider`, `remoteEndedProvider`, `selectRemote`, `remoteControllerProvider.deselect`, `accountStateProvider`, `Islands.of(context).show`.

Picker rows: "This device" (check mark when no link), then each other device by `name` with its `title` as subtitle when playing; an incompatible one greyed and disabled with subtitle "Update Songies to control this device"; none → "No other devices online". Strip: connecting "Connecting to <device>…", connected "Playing on <device>", lost "Lost connection to <device>"; tapping it opens the picker. `ended` with `noAnswer` → island "<device> didn't answer"; with `lost` → island "Lost connection to <device>" (`IslandKind.failure`).

- [ ] **Step 1: Write the failing widget tests**

`no button when signed out`; `lists online devices and This device`; `none online says No other devices online`; `an old version is greyed with Update Songies to control this device`; `picking a device shows Connecting then Playing on <device>`; `This device returns`; `no answer shows the island`; `lost shows the strip text`.

- [ ] **Step 2: Run them to see them fail** — `flutter test test/ui/devices_picker_test.dart` → FAIL.
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run** `flutter test test/ui/ && flutter analyze` → PASS, clean.
- [ ] **Step 5: Commit** — `feat(remote): devices picker and Playing on strip`

---

### Task 8: Play on… menu entries, docs, release check

**Files:**
- Modify: `lib/ui/widgets/song_menu.dart` (entries "Play on <device>" / "Add to queue on <device>", P4), `lib/ui/playlist/playlist_page.dart` (same two in the playlist ⋯ menu, for the whole playlist)
- Modify: `docs/manual-test-checklist.md` (new "Remote control" section), `docs/ROADMAP.md` (step 3 done), `docs/PROGRESS.md` (a short entry)
- Test: `test/ui/song_menu_test.dart`, `test/ui/playlist_page_test.dart` (or the existing files that test these menus)

**Interfaces:** Consumes `remoteDevicesProvider` (compatible ones only, first 3), `RemoteController` via a `RemotePlayerView`-like send for a device that isn't selected: add `RemoteController.sendTo(RemotePresence d, RemoteOp op, Map<String, Object?> args)` in this task (no link needed; P2 `syncNow` first). YouTube Music songs are stored first with the menu's existing `track()` helper, then sent by id.

- [ ] **Step 1: Write the failing tests**

`no Play on entries when alone`; `Play on Desk sends playTracks with the song's id to Desk`; `Add to queue on Desk sends addNext`; `an incompatible device gets no entry`; `playlist menu Play on Desk sends the playlist's track ids and its id as playlist`; `a YouTube Music result is stored before it is sent`.

- [ ] **Step 2: Run them to see them fail**, then **Step 3: Implement**, then **Step 4: Run** `flutter test && flutter analyze` (full suite once) → PASS apart from the known timing tests; record counts.

- [ ] **Step 5: Checklist section** — two signed-in devices: each direction; play/pause/seek/volume/shuffle/repeat; queue jump, reorder, remove; Play on / Add to queue on from a song, a playlist and a fresh search result (P2); a local file the other device lacks (skipped with its island on the host); Android in the background (lost strip, back on open); sign out on one; an older build greyed.

- [ ] **Step 6: Build check** — `flutter build linux --release` and `flutter build apk --release` succeed; note sizes in PROGRESS.md.

- [ ] **Step 7: Commit** — `feat(remote): Play on and Add to queue on; docs`
