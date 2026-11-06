# Remote control (Supabase Realtime) — step 3 — design

Roadmap item 5, step 3 (`docs/ROADMAP.md`). Agreed with the user on
2026-11-06. Builds on step 1 (accounts) and step 2 (cloud sync,
`docs/superpowers/specs/2026-11-05-cloud-sync-design.md`).

## Why

The user wants to see what their other signed-in devices are playing and
control them from this one (Spotify Connect-like): from the phone, run the
computer's playback, including its queue.

## What it is (the user's choices)

- **Remote control and queue editing.** No "move playback here" (transfer
  the song and position to this device) in this step.
- **Both ways of choosing what plays:** the other device's current queue
  (jump to, reorder, remove) **and** this device's own synced library
  (**Play on <device>**, **Add to <device>'s queue**).
- **Spotify-style switch.** A devices button in the desktop player bar and
  in the phone's Now Playing lists the user's other online devices. Picking
  one turns the player bar, Now Playing and queue on this device into a view
  of that device, with a "Playing on <device>" strip. "This device" goes
  back.
- **Always on.** Every device signed in to the account can control and be
  controlled; no setting.
- Signed out: no devices button, nothing joins.

A device is listed only while Songies runs on it. On Android a paused app
in the background may lose its connection and appears again when opened.
This is Android's process model, not a choice.

## How it is built

**Supabase Realtime, Presence + Broadcast on a private per-user channel**
`remote:<user id>`. No tables; nothing stored. *(Claude's call, agreed:
latency ~100 ms, no database writes, nothing counts against storage; a
`device_state` table with Postgres Changes was rejected because offline
state wasn't asked for and it writes constantly.)*

Migration: RLS policies on `realtime.messages` letting an authenticated
user receive (`select`) **and send** (`insert`) broadcast and presence
messages only on `remote:<their id>`. The sync topic's policies are
unchanged.

### Units

- `lib/remote/remote_protocol.dart` — message types (presence info, state,
  command, hello) as plain Dart classes with `toJson`/`fromJson`. Every
  message carries `v` (protocol version, starting at 1). Decoding never
  throws: a malformed or unknown message is `null` and is ignored.
- `lib/remote/remote_channel.dart` — interface `RemoteChannel` (join with
  presence info, update presence, presence list stream, send, incoming
  message stream, leave) and `SupabaseRemoteChannel`. Tests use a fake that
  links several in-memory devices.
- `lib/remote/remote_host.dart` — runs on every signed-in device. Publishes
  this device's player state; applies commands addressed to it to
  `PlayerService`.
- `lib/remote/remote_controller.dart` — while a remote is selected, holds
  its latest state and sends commands.
- `lib/remote/player_view.dart` — a small interface the player UI uses
  (state stream; play, pause, toggle, next, previous, seek, volume,
  shuffle, repeat, playAt, removeAt, move, playTracks, addNext, addToEnd).
  One implementation wraps `PlayerService`, one wraps `RemoteController`.
  The player bar, Now Playing and queue read a `playerViewProvider` that
  returns the selected one, so no screen is duplicated.
- UI: the devices button and picker sheet/menu, the "Playing on <device>"
  strip, and **Play on…** / **Add to queue on…** entries in the song and
  playlist ⋯ menus (shown only when another device is online).

### Device identity

`deviceId` is the existing sync device id (`syncStampProvider`). The name is
the `kDeviceName` setting when one exists (left from the old home-network
sync), else the Android model or the desktop hostname, as the bug report
reads them.

## Messages

- **Presence** (each device tracks its own):
  `{v, deviceId, name, platform, appVersion, playing, title}`; updated when
  play/pause or the song changes. The picker lists these, excluding this
  device.
- **State** (host → channel), event `state`:
  `{v, from, epoch, index, queue: [track ids], playing, buffering,
  position_ms, at_ms, duration_ms, volume, shuffle, repeat, notice}`.
  Sent on every player change (debounced to at most one per 250 ms) and
  every 5 s while playing. Sent only while at least one other device is
  present. `queue` holds track ids only; the controller looks them up in
  its own synced database and shows "Unknown song" for an id it doesn't
  have yet. At most 2,000 entries around the current one are sent (the
  window offset is sent too, so indexes stay true).
- **Command** (controller → channel), event `command`:
  `{v, to, id, op, args, epoch?}`. `op`: `play`, `pause`, `toggle`,
  `next`, `previous`, `seek`, `volume`, `shuffle`, `repeat`, `playAt`,
  `remove`, `move`, `playTracks` (ids, start index, optional source
  playlist id), `addNext`, `addToEnd`. A host acts only on commands with
  `to` = its device id.
- **Hello** (controller → channel), event `hello`: `{v, to}`. The host
  answers with full state right away.

`playAt`, `remove` and `move` carry the `epoch` (the host's `queueEpoch`)
the controller last saw. If it no longer matches, the host does nothing and
sends fresh state: a stale index never touches the wrong song.

Track ids in `playTracks`/`addNext`/`addToEnd` are looked up in the host's
database; ids it doesn't know are dropped. Songs it can't play (a local file
it doesn't have) follow the player's usual skip rules and island notice.

## Behaviour

- **Picking a remote:** this device's player pauses; the controller sends
  `hello` and shows a loading state until the first state arrives (5 s,
  then "Desktop didn't answer" and back to This device).
- **Controller view:** shows the last state; while playing, the position
  runs on from `position_ms` + (now − `at_ms`), capped at the duration.
  Commands update the view at once (optimistic) and the next state message
  corrects it.
- **Play button in remote view** sends `play` to the remote, never starts
  local playback. Media keys, the notification and the lock screen on the
  controlling device keep controlling the local player. *(Claude's call.)*
- **Host used directly** (someone presses pause on it): an ordinary state
  change; controllers follow.
- **Two controllers:** no locking; commands apply in arrival order and
  both see the same state.
- **Remote drops out of Presence:** "Lost connection to <device>" in the
  strip; if it doesn't return within 15 s, back to This device (local
  playback stays paused).
- **Older or newer protocol:** a device whose presence `v` differs is
  listed greyed as "Update Songies to control this device"; its messages are
  ignored.
- **Sign out / account switch:** leave the channel; a controller goes back
  to This device.
- **Offline:** the devices button shows only This device and "No other
  devices online".

## Error handling

- Channel join failures and drops retry with the Supabase client's own
  reconnect; nothing is shown unless a remote is selected (then the
  lost-connection strip).
- A failing command on the host (e.g. seek while nothing loaded) is logged
  and answered with fresh state; no notice on the host.
- Message handling never throws into the channel callback.

## Testing

- Protocol: JSON round trips; malformed, unknown-op and wrong-version
  messages decode to `null`.
- Host (fake channel, real `PlayerService` with a fake backend): every op;
  stale epoch ignored with fresh state; `hello` reply; commands for other
  devices ignored; no state sent while alone; debounce and 5 s heartbeat
  with fake time; queue window at 2,000.
- Controller (fake time): position extrapolation and cap; hello timeout;
  presence-lost 15 s fallback; optimistic update then correction.
- `playerViewProvider` switches implementations; local player paused on
  selection.
- Widgets: devices picker (online, none, old version), remote strip,
  Play on… menu items hidden when alone.
- Manual checklist: two devices, each direction, queue edits, a local file
  the other device lacks, Android in background.

## Not in this step

Move playback here; a setting to opt a device out; controlling a device
whose app is closed; listen together (step 4).
