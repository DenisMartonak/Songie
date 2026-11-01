# Crossfade — design

Date: 2026-11-01. Status: draft for approval. Roadmap item 4 of 6 (after
the equalizer, which it must keep working with).

## Why

The user wants songs to blend into each other like Spotify's Crossfade,
instead of one stopping and the next starting.

## What the user decided

- **Like Spotify's Crossfade.**
- The details below were proposed as guesses and accepted ("looks good").

## Behaviour

- **Settings → Playback** (the section the equalizer adds): a **Crossfade**
  switch, **off by default**, and when on a slider from **1 to 12 s**
  (default **5 s**). Per device, not synced, survives restarts.
- **When it fades:** only when a song plays to its end by itself and another
  song follows (the queue's next, a repeat-all wrap, or the radio's next).
  The ending song's volume falls to 0 while the next song's rises from 0,
  over the chosen time, ending exactly when the old song ends.
- **When it doesn't:** Next, Previous, tapping another song, seeking past the
  fade point, repeat-one, the last song with repeat off, and pause (pausing
  mid-fade pauses both and resumes the fade).
- **During a fade** *(builder's call, as Spotify behaves)*: from the moment
  the fade starts the app treats the incoming song as the current one (now
  playing, seek bar, queue highlight, lock screen, Discord). Any manual
  action (Next, Previous, tapping a song, seeking) cuts the outgoing song
  with a click-free ~100 ms ramp and then acts on the incoming song as
  usual: Next skips it, Previous restarts it (it is near its start), seeking
  moves it. The outgoing song's listen closes at the cut.
- **Short songs:** the fade is at most a third of either song's length
  *(builder's call; the user accepted "shorter than twice the fade gets a
  shorter fade")*.
- **What keeps working:** the equalizer on both songs, the user's volume
  (the fade multiplies it, never overrides it), lock-screen / media
  controls and Discord showing the *new* song from the moment the fade
  starts, lyrics following the new song, play history and stats counting
  each song's own heard time (the overlap is heard time for both, never
  double-counted for one), YouTube play reports, and Android audio focus
  (a call ducks or pauses both).
- **Failures:** if the next song can't be loaded in time (no network, a
  stream that won't resolve, an age-restricted song needing sign-in), the
  current song plays out to its end and the player continues the normal
  way, with today's skip notices. A fade never makes a song fail that
  wouldn't fail without it.

## How (decided)

- The player engine gets a **second player** that takes turns with the
  first: the next song is loaded into the idle player shortly before the
  fade (reusing today's stream prefetch, so YouTube links are fresh), both
  play during the overlap, and the idle one becomes the current one when the
  fade ends.
- Both players are the same kind as today (just_audio; ExoPlayer on
  Android, media_kit/mpv on desktop), so each gets the equalizer the same
  way.

## Order

Built after the equalizer (roadmap item 3), so the second player reuses the
equalizer code as it stands then.

## Non-goals

- Spotify's "Automix" (beat matching, smart transitions), skipping silence.
- Fading on manual skips.
- Different fade curves to choose from (the builder picks one that sounds
  even, e.g. equal-power).

## Constraints

- With Crossfade **off**, playback behaves exactly as today: one player,
  same timings, same tests passing.
- The `AudioBackend` interface (`lib/player/audio_backend.dart`) and
  `PlayerService` keep their current contract for the rest of the app; the
  second player is an internal detail of the playback layer.
- Memory and CPU: at most two players exist; the idle one is released when
  Crossfade is off.
- Tests: the fade timing and "when it fades" rules are tested with fake
  backends and a fake clock.

## Left to the builder

- Whether the two players live inside one `AudioBackend` implementation or
  `PlayerService` drives two backends.
- The fade curve and the volume update rate (smooth to the ear, without a
  busy timer when nothing is fading).
- How long before the fade the next song is loaded.
