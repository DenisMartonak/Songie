# Listen together — step 4 — design

Linear SON-5 (accounts and cloud sync, step 4). Agreed with the user on
2026-11-08. Builds on step 1 (accounts), step 2 (cloud sync) and step 3
(remote control, `docs/superpowers/specs/2026-11-06-remote-control-design.md`).
Mockups: `.superpowers/brainstorm/562755-1794178387/content/room-views-v2.html`
(desktop) and `room-phone-v2.html` (phone), local only.

## Why

The user and a friend on Discord want to listen to the same music at the
same time, each on their own device: the user shares a link, the friend
clicks it and hears what the user is playing. Friends can be trusted to
add songs or run the music, if the user allows it.

## Goals

- A **host** opens a room and shares a link (in Discord, for now).
- A **guest** clicks the link, Songies opens on their device and joins the
  room, and they hear what the host plays, at the same point in the song.
- The host gives each guest a **role**: Listener, Queue, or Full control.
- Leaving or the room ending never cuts a guest's music: they keep the
  queue and the song carries on.

## Non-goals

- Sending audio over the network. Every device plays the songs itself.
- Chat, reactions, or voting.
- Rooms that last without the host: the room lives on the host's device.
- The website the links point at (SON-22, built next; see "The link").
- Guests without a Songies account.

## Who can join (the user's choices)

- The guest needs Songies installed **and** an account. A guest who has the
  app but isn't signed in sees an island: they need an account to join
  *(Claude's call: with a "Sign in" action)*.
- The host is whoever opened the room and shared the link.

## Roles (the user's choices)

The host sets each guest's role and can change it at any time:

- **Listener** — hears the room; changes nothing.
- **Queue** — Listener, plus adding songs to the room's queue.
- **Full control** — everything the host can do with the music: play,
  pause, seek, skip, previous, shuffle, repeat, play a whole playlist (it
  replaces the room's queue), and jump to, reorder or remove queue songs.

*(Claude's calls, accepted:)* everyone joins as a Listener; only the host
changes roles, and Full control doesn't include roles; the host can remove
a guest; everyone sees who is in the room and their role. Volume stays
each person's own.

There is **one queue**, the host's. What a guest with a role does changes
that queue, and every device in the room follows it.

## Joining and leaving (the user's choices)

- **Joining:** whatever the guest was playing stops; their player plays
  the room's song from the room's position. If the host plays nothing, the
  guest hears nothing until the host starts something. *(Claude's call:
  the guest's queue is replaced by the room's.)*
- **Leaving:** the guest keeps the room's queue as it was, and the current
  song carries on from where it was, now on its own. From then on it is
  their normal player.
- *(Claude's call, accepted:)* when the room **ends** (the host ends it,
  closes the app, or is gone for more than 15 s), every guest is treated as
  if they left, with the island "The room ended".

## What people see (the user approved the mockups)

Emoji in the mockups are placeholders; the app uses its own icons (the
user asked for no emoji).

- **Guest, desktop:** a strip above the player bar, "Listening with
  <host> · <what the role allows>", with **Leave**. Play, skip and seek
  are dimmed unless the role is Full control; the queue's add/reorder
  controls follow the role the same way. A room button (people icon, with
  the count) opens the room panel.
- **Guest, phone:** the same strip on top of the mini player (tapping it
  opens the room sheet), and a "Listening with <host>" chip at the top of
  the full-screen player, where "Playing on…" goes for remote control.
- **Host, desktop:** a people-icon button in the player bar opens the room
  panel: **Listen together** with the link and **Copy**; the people in the
  room (name, device kind, a role menu, ✕ to remove); **End room**. The
  host's own player bar works as normal, with a "Your room · N listening"
  strip and **Manage**.
- **Host, phone:** the same panel as a sheet that slides up, with **Share
  link** (the phone's share menu, Discord included) and **Copy**.
- **Starting a room:** "Listen together" from the people-icon button, and
  in a playlist's ⋯ menu *(Claude's call: that one opens the room and plays
  the playlist)*.
- **Island notices** *(Claude's calls)*: to the host, "<name> joined",
  "<name> left", "<name> added <song>"; to a guest, their role changing,
  being removed, and the room ending.
- Names are account usernames.

## Edge cases (Claude's calls, accepted)

- **In step:** guests stay within about a second of the host. A guest who
  drifts further is corrected by a seek, not by cutting or restarting the
  song; small drift is left alone.
- **Songs a guest can't play** (a local file of the host's, an
  age-restricted song when the guest isn't signed in to YouTube, a stream
  that fails): skipped on that guest's device with an island note; they
  join in again at the next song. Everyone else carries on.
- **Songs a guest adds** (Queue and Full control): from search, their
  library and playlists, and YouTube Music. Their own local files can't be
  added (the others don't have them); those menu entries are hidden or
  greyed in a room.
- **Host gone:** the host's app closing or losing its connection for more
  than about 15 s ends the room (as remote control's 15 s).
- **One at a time:** joining a room while controlling another device or
  hosting a room first asks to leave that. A host can't join another room
  without ending theirs.
- **The link** works only while the room is open; an old link gives "This
  room has ended" on the island.
- **Size:** up to 10 people including the host; a full room says so on the
  island.
- **Stats, history, Discord status:** what a guest hears counts as their
  own listening, as if they played it.
- **A guest's own settings still apply** on their device: Wi-Fi only
  streaming, the equalizer, their volume. A song their settings keep from
  streaming is skipped there like any song they can't play.
- **Queue role adds** both "Play next" and "Add to queue", as the host's
  own song menu offers.
- **A guest with Full control plays a playlist** from their own library:
  its songs' details go to the host, which turns them into its own tracks
  and plays them; the guest's local files among them are dropped, with an
  island note to that guest.
- **The same account on two devices:** one can join the other's room; it
  is treated as any guest.
- **Covers on guests:** fetched by the guest from the song details sent.
  They may differ from the host's (e.g. the host has a song's album art
  and the guest gets its video thumbnail); that is accepted for now.

## How it is built (Claude's call, accepted)

**Supabase Realtime**, as remote control: a private channel per room. The
**host's app is in charge**: guests send requests; the host checks the
sender's role and applies allowed ones to its own `PlayerService`, then
broadcasts the room state (current song, position, playing, queue) to
everyone. Guests' players follow that state.

What follows from that:

- **Guests don't share the host's library.** Room messages carry each
  song's details (YouTube video id, title, artist, album, duration, and
  what's needed for a cover), not just track ids as remote control does.
  A guest's device turns them into its own tracks the usual way
  (`YtTrackStore`), so they show and play like any YouTube song. A local
  file of the host's is marked as such and skipped on guests.
- **Only joined people hear the room.** The channel is private, and only
  members may read or send on it. Membership is kept in the database
  (rooms and members, with row-level security), so the link's code is
  what lets a signed-in user in, the host can remove someone, and a full
  or ended room refuses new members. A new migration under
  `supabase/migrations/`, documented in `docs/supabase.md`.
- The room code in the link is random and hard to guess.

## The link (Claude's call)

The website that turns a clickable `https://` link into "open Songies" is
SON-22, built right after this. For this step:

- Songies registers a `songies://` link on Android, Windows and Linux
  (Linux through the `.desktop` file), and a room link opens the app into
  the join flow, also when the app wasn't running.
- The room panel shares `https://<site>/r/<code>`, with the site's address
  as one constant set when SON-22 exists. Until then, the app also accepts
  that link, a `songies://` link or the bare code pasted into a **Join a
  room** entry, so the feature can be tested before the site exists.

## Constraints

- No change to playback when no room is open.
- Remote control keeps working as it does; a device in a room isn't
  offered as a remote-control target to other devices *(Claude's call)*.
- Free Supabase tier: no audio, nothing large; room messages are small and
  rate-limited (debounced state, as remote control).
- Message decoding never throws; unknown or newer-version messages are
  ignored, and a guest on an older version is told to update.
- Tests with fake channels and fake time for the host, guest, roles, drift
  correction, ending and leaving; widget tests for the strip, panel and
  sheet; a manual checklist section for two real devices and two accounts.

## Left to the builder

- Message shapes, the debounce and heartbeat timings, and the drift
  threshold.
- How the guest's player follows the host's (reusing remote control's
  pieces where they fit, e.g. the player view and the protocol style).
- The database tables, the join call and the channel policies.
- How the link reaches a running app on each platform.
- How guest covers are fetched (from the song details sent).

## Not in this step

The website (SON-22); rooms that outlive the host; handing the host role
to someone else; chat.
