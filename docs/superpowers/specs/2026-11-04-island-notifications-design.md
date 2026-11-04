# Island notifications — design

Roadmap item 2 (`docs/ROADMAP.md`). Agreed with the user on 2026-11-04.

## Why

The floating Material snack bars Songies shows at the bottom of the page
(errors, "Added to queue", "Removed …", "Theme exported", …) look bad. The
user pictured instead a small "island" that pops up from beneath the
player bar, shows the message briefly, and goes back.

## What it is

Every message the app shows today through `PageSnackBars` /
`showPageSnackBar` (`lib/ui/widgets/page_snack_bar.dart`; 42 call sites in
22 files, plus `PlayerErrorSnacks` in `lib/ui/shell/player_error_snacks.dart`)
is shown as an island instead. Material snack bars disappear from the app.

Confirmation dialogs (`AlertDialog`s, e.g. "will be deleted on all your
devices") are not messages and stay as they are.

## Look (option B of the mockups)

- A **black pill**, horizontally centred, floating just above the player
  bar. Height about 38 px, fully rounded ends, padding about 8 px, white
  text, width fits the content up to a
  max (about 420 px on desktop; screen width minus 32 px on phones).
- **Long messages wrap to at most 2 lines** (then ellipsis); the pill grows
  taller and its ends round to a stadium/rounded-rect shape. Some player
  errors are long and the reason must stay readable; shortening wording is
  out of scope. The morph animates height as well as width. *(Claude's
  call.)*
- Black in **every theme** (it is not themed), with a soft drop shadow and a
  faint light outline (white at roughly 8–12 % opacity) so it stays visible
  on the all-black built-in theme and on user-made light themes.
- **Leading item:**
  - when the message is about one song, that song's small cover
    (about 22 px, rounded 4 px, using the existing `Artwork` widget);
  - otherwise a small icon: a check for success, a warning sign for a
    failure, an info icon for neutral notices.
- **Action** (Undo, Retry, Sign in, Open, Details …), when the message has
  one: on the right, in the theme's accent colour, bold, clickable.

## Motion

- **In:** pops up from behind the bar: starts small (scale ≈ 0.6) and lower
  (tucked behind the bar's top edge), transparent, then grows and rises
  into place. Ease-out, about 250–300 ms. "Behind the bar" means it is
  clipped / drawn under the bar while rising, so it emerges from it.
- **Out:** the reverse: shrinks and sinks back behind the bar.
- **Replace:** only one island at a time. A new message while one is shown
  morphs the existing island into the new one (size and content animate
  across) rather than stacking or queueing.
- Respect the platform's reduce-motion setting (`MediaQuery.disableAnimations`):
  fade only.

## Where it appears

- **Desktop / wide layout:** above the `PlayerBar` (`lib/ui/shell/player_bar.dart`,
  72 px tall, always shown), centred on the window's width, emerging from
  behind the bar.
- **Phone layout:** the same, rising from behind the **top of the whole
  bottom stack** in `lib/ui/shell/phone_shell.dart`, whatever is showing:
  DownloadsBanner, DownloadsIndicator, mini player (`lib/ui/shell/mini_player.dart`),
  bottom nav. So it never covers the banner's buttons. The user said
  "above the mini player"; when the banner/indicator are present the island
  sits above them instead *(Claude's call)*. When nothing is playing and
  nothing else is in the stack, it emerges from behind the bottom nav.
- **Keyboard open** (the phone bars hide): the island sits just above the
  keyboard, rising from its top edge *(Claude's call)*.
- **Full-screen player open** (`lib/ui/now_playing/`): the bar is hidden; the
  island still shows, at the bottom centre of the screen, rising from the
  bottom edge.
- It floats over the page and never pushes content.
- It shows **on top of everything**, including bottom sheets, menus and
  dialogs (so an error raised while e.g. the Add to playlist sheet is open
  is seen).
- **When something covers the bar** (a bottom sheet, menu or dialog is
  open over it): the island can't come from behind a bar that is hidden,
  so it rises from the bottom edge of the screen instead, as with the
  full-screen player, over the sheet *(Claude's call)*. Rule of thumb for
  the builder: emerge from behind the bar/stack when it is the topmost
  thing at the bottom; otherwise from the screen's bottom edge.

## Behaviour

- **Duration:** 4 s by default, as now. Call sites that pass a duration
  today keep it (the playlist page's "Added to queue" uses 2 s).
- **Hover** (desktop): pauses the countdown; leaving restarts it.
- **Click/tap on the island** (not on its action): dismisses it at once.
- **Swipe down** (phones): dismisses it.
- **Action click:** runs the action as today, then the island closes.
- **Accessibility:** the message is announced to screen readers, as
  snack bars are now (e.g. `SemanticsService.announce` or a live region).
- **New message:** "Added to queue" from the song menu
  (`SongMenuAction.addToQueue` in `lib/ui/widgets/song_menu.dart`), which
  shows nothing today, now shows an island with the song's cover. The user
  named adding to queue/playlist as a main use.

## Goals

- All existing messages appear as islands, on every platform, with the same
  text, actions and timing they have today.
- The pop-from-behind-the-bar motion is the feature; it must look smooth.

## Non-goals

- No notification history or stacking/queueing several messages.
- No change to message wording beyond what the new layout needs.
- No system (OS) notifications.

## Anti-goals

- An island that covers the player controls, or that can't be seen on some
  theme.
- Messages that get lost: an island hidden under a sheet or dialog, or
  dropped during a route change.

## Left to the builder

- Implementation shape: a replacement for `PageSnackBars` with the same
  call shape (`show(content:, action:, duration:)` plus optional song /
  kind), a root `Overlay` entry or similar so it renders above sheets, and
  how it measures the bar's position for each layout.
- How call sites say "this is about song X" and "this is a failure", and
  migrating the ~42 call sites and their tests (6 test files mention
  `SnackBar`).
- Exact sizes, curves and shadow values within the ranges above.
