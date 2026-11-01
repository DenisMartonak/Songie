# Equalizer — design

Date: 2026-11-01. Status: draft for approval. Roadmap item 3 of 6.

## Why

The user wants to shape the sound with a few ready-made presets, without
fiddling with sliders.

## What the user decided

- **Presets only**, no sliders.
- The choice lives in **Settings**.

## Behaviour

- Settings gets a **Playback** section (new; *builder's call on the name,
  accepted by the user as a guess*) with an **Equalizer** row showing the
  current preset. Tapping it opens a list of presets with the current one
  checked.
- Presets *(builder's call, accepted as a guess)*: **Off, Bass boost, Vocal,
  Rock, Pop, Classical, Electronic, Acoustic**.
- Picking a preset changes the sound at once, mid-song, with no restart or
  gap, and stays in effect across songs, the queue, YouTube streams,
  downloads and local files alike.
- **Off** sounds exactly like today (on Android the effect is disabled; on
  desktop all gains are 0 dB, see below).
- The choice is per device and not synced (a phone speaker and PC
  headphones need different shaping). It survives restarts.

## How (decided)

- **Android:** just_audio's `AndroidEqualizer` (an `AudioPipeline` effect on
  the `AudioPlayer`). Each preset is a gain per frequency; the builder maps it
  onto whatever bands the device reports, by nearest centre frequency, and
  clamps to the device's min/max.
- **Windows and Linux:** mpv's audio filter (`af`) with an equalizer
  (`lavfi=[...]` built from the same per-frequency gains), set on the
  media_kit player. `just_audio_media_kit` keeps its mpv player private, so
  Songies carries a small patched copy of that package (a path dependency
  under `packages/`) that exposes a way to set the filter.
- *(Builder's call:)* on desktop the equalizer filter is put in mpv's chain
  once, labelled, and presets change its gains in place (`af-command`), so
  switching is seamless. **Off** is then every band at 0 dB: the same sound,
  though the filter stays in the chain. (Setting and clearing `af` on each
  change would make Off literally filter-free but risks a click on every
  switch.) just_audio rebuilds the desktop player after `stop()`, so the
  filter is applied again whenever a new player is made.

- **Windows (user's decision):** the bundled `media_kit_libs_windows_audio`
  libmpv is a minimal audio build that may lack FFmpeg's `equalizer` filter.
  The first task checks it on Windows. If the filter is there, Windows works
  like Linux. If not, the equalizer ships on Android and Linux only for now,
  and on Windows the Settings row reads "Not available on Windows yet"
  (disabled). No switch to the bigger full build, no custom libmpv.

## Preset gains (dB)

Ten reference bands; Android maps them onto its bands as above.

| Preset | 31 | 62 | 125 | 250 | 500 | 1k | 2k | 4k | 8k | 16k |
|---|---|---|---|---|---|---|---|---|---|---|
| Bass boost | 6 | 5 | 4 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| Vocal | -2 | -2 | -1 | 1 | 3 | 3 | 2 | 1 | 0 | -1 |
| Rock | 4 | 3 | 2 | 0 | -1 | 0 | 2 | 3 | 4 | 4 |
| Pop | -1 | 0 | 2 | 3 | 3 | 2 | 0 | -1 | -1 | -1 |
| Classical | 0 | 0 | 0 | 0 | 0 | 0 | -2 | -2 | -2 | -3 |
| Electronic | 5 | 4 | 1 | 0 | -2 | 1 | 0 | 2 | 4 | 5 |
| Acoustic | 3 | 3 | 2 | 1 | 1 | 1 | 2 | 2 | 2 | 1 |

*(Builder's call: these values; they may be tuned by ear later.)*

## Non-goals

- Custom sliders, user-made presets, per-song or per-playlist presets.
- A quick switcher near the player.
- Syncing the choice between devices.

## Constraints

- No audible gap or restart when switching presets, and no clipping beyond
  what the presets imply (the builder may lower overall gain slightly for
  presets with large boosts).
- The patched `just_audio_media_kit` copy changes nothing else; its version
  and the reason for the patch are noted next to it.
- Tests: the preset → gains mapping and the band mapping are pure functions
  with unit tests; the backend effect is behind an interface with a fake.

## Left to the builder

- The settings key name, the provider shape, and where the equalizer
  interface lives in `lib/player/`.
- How the desktop patch exposes the filter (a method on the player, or a
  property hook).
