# Patched copy of just_audio_media_kit 2.1.0

Copied from pub.dev `just_audio_media_kit` 2.1.0 for Songies' equalizer
(docs/superpowers/specs/2026-11-01-equalizer-design.md). The upstream package
keeps its mpv `Player` private, so the app could not set mpv's audio filter.

The only changes are marked `SONGIES PATCH`:

- `JustAudioMediaKit.onPlayerCreated`: called with each new mpv `Player`.
- `JustAudioMediaKit.livePlayers`: the players not yet disposed.

To update: copy the new upstream version over this folder and re-apply those
lines.
