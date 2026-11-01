# Android Auto — design

Date: 2026-11-01. Status: draft for approval. Roadmap item 5 of 6 (after
Favorites, which it shows).

## Why

The user wants to use Songies in the car through Android Auto: control
playback and choose a playlist from the car's screen.

## What the user decided

- On the car screen: **skipping, pausing, and choosing playlists**.
- **Lists are enough**: no voice commands ("Hey Google, play … on Songies").
- The rest below was proposed as guesses and accepted.

## Behaviour

- **Setup (user's decision):** Songies is installed from GitHub, not the
  Play Store, and Android Auto lists only Play Store media apps by default.
  The user turns on Android Auto's developer mode (tap the version number
  10 times) and "Unknown sources" once; the plan includes a short how-to
  (in the README and the manual checklist). Publishing to the Play Store is
  out of scope.

- Songies appears in Android Auto's app list as a media app (its own icon
  and name).
- **Player screen** (Android Auto's standard media screen): title, artist,
  cover, play/pause, next, previous, and a seek bar where the car shows one.
  A **star** button toggles Favorites for the playing song *(guess
  accepted)*.
- **Browsing**, two tabs:
  - **Playlists:** Favorites first, then the user's playlists in the
    library's order. Tapping a playlist lists its songs; tapping a song plays
    the playlist from that song (the same queue as tapping it in the app).
    Each playlist also offers "Shuffle" as its first item.
  - **Recently played** *(guess accepted)*: the last 50 songs played, newest
    first. Tapping one plays it, with the rest of that list as the queue.
- Covers show in lists and on the player where Android Auto allows.
- **Streaming in the car:** YouTube songs stream as in the app (subject to
  the existing Wi-Fi-only streaming setting); downloaded and local songs
  play offline. A song that can't play is skipped with the app's usual
  notices (shown on the phone; the car shows the next song).
- Whatever is playing on the phone shows in the car when Auto connects, and
  controls in the car and on the phone stay in step.
- *(Builder's call:)* **nothing playing when the car connects:** pressing
  Play in the car (or the car's own "resume" request) resumes the last song
  from play history, with the playlist it was played from as the queue
  (history already records that playlist). Songies never starts playing by
  itself on connect. The car works even when the phone app hasn't been
  opened since the phone restarted.
- *(Builder's call:)* **Wi-Fi only streaming / no signal:** the player keeps
  today's behaviour (the queue stops at the first song that would need to
  stream), and the reason ("Wi-Fi only is on — connect to Wi-Fi to
  stream", "You're offline") is shown on the car screen as the playback
  error, not only on the phone.
- *(Builder's call:)* the **star** is a media control, so it also appears in
  the phone's notification and lock-screen controls (Android takes the
  car's buttons from the same place). Where the car has room for only some
  extra buttons, the order is star, shuffle, repeat.

## How (decided)

- Songies already uses `audio_service` (`lib/player/audio_handler.dart`),
  which is an Android `MediaBrowserService`; Android Auto talks to it. The
  work is answering its browse calls (`getChildren`, `getMediaItem`,
  `playFromMediaId`), a custom action for the star, and the manifest entry
  plus `automotive_app_desc.xml` that tell Android Auto Songies is a media
  app.
- Media ids encode what was tapped (a playlist, a song within a playlist, a
  recently-played song) so `playFromMediaId` can rebuild the queue.

## Non-goals

- Voice commands and search.
- Android Automotive OS (cars with Android built in, no phone).
- Changing playlists from the car (add, remove, reorder).
- Equalizer or crossfade settings in the car.

## Constraints

- Android Auto's own limits: list depth and item counts are capped by the
  car (the builder pages or trims long playlists sensibly; the queue itself
  still holds the whole playlist).
- No behaviour change on desktop. In the phone app the only visible change
  is the star in the notification / lock-screen controls.
- Testable without a car: Google's Desktop Head Unit (DHU) emulator, plus
  unit tests for the browse tree and media-id round trips with fake
  repositories. A manual checklist section covers a real car or DHU run.

## Left to the builder

- Media id format, tab ids, the browse-tree root hints Android Auto asks for.
- Whether "Shuffle" is a list item or a playable flag on the playlist row.
- How covers reach the car (content URIs or file URIs from the art cache).
