# Right pane: friends, listen together, lyrics and queue (SON-40)

## Why

The desktop player bar has four icons at its right end (Lyrics, Devices,
Listen together, Queue) and it feels overwhelming. Friends and listening
together are a big part of Songies now, but they sit behind a dialog and a
page under Profile. The redesign gives them a pane that is open by default
and trims the bar to three icons.

## Goals

- A pane on the right of the desktop window, 320 px wide (as wide as the
  lyrics pane today), open by default, showing Friends.
- Listen together lives in full at the top of that pane. There is no room
  dialog on the desktop shell.
- Lyrics and Queue open in the same pane, in place of Friends.
- The player bar's right end has Lyrics, Queue and Devices (plus volume).
  The Listen together icon goes.
- An X closes the pane down to a slim strip of faces; the app remembers it.
  Clicking the strip opens the pane again.

## Non-goals

- The phone layout. It keeps its bottom nav, mini player, Home header room
  button and the room bottom sheet.
- Friend requests in the pane. They stay on the Friends page.
- Navigation inside the pane (a friend's profile in the pane, a back
  button). A friend still opens their page in the main area.
- The friend profile redesign (SON-39).

## Anti-goals

- Lyrics or Queue and Friends both showing at once, or fighting over the
  right side.
- A room you're in disappearing from view. Hosting or guesting always
  shows: at the top of the pane when it's open, at the top of the strip
  when it's closed.
- The pane taking the page away in a narrow window. It squeezes and
  overlays exactly as the lyrics pane does today.

## Decided with the user

- The room's full contents in the pane (mockup B), not a small card.
- An X closes the pane, and the choice is remembered.
- Closed, the pane becomes a strip of friends' faces (mockup B of the
  reopen question). A click anywhere on it opens the pane.
- Built as one pane with one remembered state (approach 1, below).

## Approaches

1. **One right pane with a remembered state (chosen).** A single
   `RightPane` replaces `LyricsPanel`. One state says whether it's open and
   what it shows (Friends, Lyrics or Queue). One place decides what's on
   the right, so the anti-goal above can't happen.
2. Separate friends, lyrics and queue panes with rules between them. Less
   change per piece, but every rule ("lyrics hides friends") is a place for
   bugs such as two panes open at once.
3. The pane as its own navigator with pages and a back button. More than
   was asked; approach 1 doesn't rule it out later.

## Design

### State

`rightPaneProvider`: a notifier holding

- `open`: bool, default true;
- `content`: `friends | lyrics | queue`, default `friends`.

`open` is remembered in `SettingsRepository` under a new device-local key
(`right_pane_open`, `'1'`/`'0'`). `content` is not remembered: the app
always starts on Friends. Rules:

- The X: `open = false` (content is kept for the session).
- The strip: `open = true, content = friends`.
- Lyrics in the bar: if the pane shows lyrics and is open, go back to
  `friends`; otherwise `open = true, content = lyrics`. Queue does the
  same with `queue`.
- The Lyrics and Queue icons are lit (accent, selected icon) while the
  open pane shows them.

`lyricsPanelOpenProvider` goes; everything that reads it (the desktop
shell's squeeze and overlay logic, the player bar's lit Lyrics icon) reads
the new provider instead.

### Layout

The desktop shell keeps its current logic, with "the lyrics panel is open"
replaced by "the right pane is open":

- Open: the pane is 320 px plus its 8 px gap. Below `_roomyWidth` it
  holds the sidebar collapsed; when the main pane would get narrower than
  `_minMainWidth` it lies over the right of the page instead.
- Closed: the strip is 40 px plus its 8 px gap, always beside the page
  (never overlaid), and doesn't squeeze the sidebar.
- Open and close animate with `AnimatedSize` as the lyrics pane does
  (instant with reduced motion).

### The open pane

Same surface as the lyrics pane today (rounded, `colors.background`,
`ExcludeFocus` so Space keeps toggling play). A slim header row:

- the title (`Friends`, `Lyrics` or `Queue`);
- the X at its right, which closes the pane whatever it shows.

**Friends**, from the top:

1. **Listen together.** The room panel's body, as it is today:
   - signed out: the sign-in line and button;
   - idle: Start a room, and the code-or-link field with Join;
   - hosting: the link with Copy and Share, the people with role menus and
     Remove, and End room;
   - guesting: everyone's role, and Leave.

   `RoomPanel` becomes a body widget used by the pane, the phone bottom
   sheet and the Now Playing dialog (below). Its sign-in action stops
   popping a navigator when it isn't in a dialog.
2. **Friends.** Accepted friends, sorted as the Friends page sorts them.
   Each row shows the picture, the name, and what they play now (or that
   they aren't listening), with Join while they host a room. Join goes
   through `joinRoomAsking`, as on a friend's page today. A tap opens the
   friend's page in the main area (`/profile/friends/<id>`). The friend row
   is pulled out of `friends_page.dart` so the page and the pane share it.
3. A **"N requests"** link when friend requests wait, opening the Friends
   page. A **"Find friends"** link when there are no friends yet, also
   opening the Friends page.

Signed out, the pane shows only the Listen together section's sign-in line
(friends and rooms both need an account).

**Lyrics:** `LyricsView(density: LyricsDensity.compact)`, as in the lyrics
pane today.

**Queue:** `NowPlayingQueue`, as in Now Playing. Its room-role and drag
behaviour stay as they are.

### The strip (pane closed)

40 px wide, the same rounded surface, scrolling if it overflows. From the
top:

- the people icon, accent with the count while in a room;
- each accepted friend's face (`PersonAvatar`, 24 px), in the pane's order,
  with a green dot while they listen now.

Signed out, only the people icon. The whole strip is one click target
(hand cursor, tooltip "Show friends") that opens the pane on Friends. Each
face also has a tooltip with the friend's name.

### Friend activity

While the pane is open on Friends, the pane holds a `watchClosely()` lease
on `FriendsService` (one refresh a minute, as the Friends page does) and
releases it when it closes or switches to Lyrics or Queue. Otherwise the
normal 5-minute refresh applies. The cost: each desktop app with the pane
open asks the server once a minute.

### The player bar

Right end: Lyrics, Queue, Devices, volume. `RoomButton` leaves the player
bar. The Queue icon no longer opens Now Playing; clicking the cover or
the title still does.

### Elsewhere

- **Now Playing** covers the whole window, pane included. Its header keeps
  its room button, which opens the room dialog as today, so a room can be
  managed from there.
- **Phone:** unchanged (the Home header button and the bottom sheet).

## Left to the builder

- Exact header styling, spacing and section labels, matching the app's
  existing panes.
- How the room body's dialog-only bits (the dialog's own padding and
  title) adapt to the pane.
- Test updates. Known: `lyrics_panel_test`, `player_bar_test` (room
  button, queue button), `shell_test`, `room_panel_test` (the popup
  becomes the pane on desktop), `room_faces_test`,
  `now_playing_faces_test`, `phone_remote_test`.

## Calls made without the user

- `content` is not remembered; the app starts on Friends.
- The strip never overlays the page, and doesn't squeeze the sidebar.
- The X closes the pane even while it shows Lyrics or Queue.
- Now Playing keeps its room button with the dialog.
- Signed out: only the sign-in line in the pane, the people icon in the
  strip.
- "Find friends" and "N requests" links lead to the Friends page.
- Before friends first load, the Friends section shows nothing (no
  spinner); a failed refresh keeps the last list, as the Friends page does.
- While controlling another device, Lyrics and Queue show that device's
  song and queue, as they already do (both read the player view).
