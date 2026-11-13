# Listen together: who added each song (SON-33)

## Intent

In a room, every song shows the profile picture of the person who put it in
the queue, on upcoming songs and on the one playing, so everyone can see
whose pick is on.

## Rules (user's)

- **All songs get a face.** A guest's added songs (Add next, Add to end, a
  Full-control guest's "play these songs") show that guest. Everything else
  shows the host: the queue the room started with, the host's own adds and
  plays, radio fill-ins.
- **Picture only**, no "Added by" text.
- **Where:** a small round picture at the end of each queue row, including
  the Now playing row. Also one on the Now Playing screen for the current
  song. None in the player bar or mini player.
- **How (approach A, picked):** the player tags each queue entry with who
  added it, and the tag travels with the entry.

## Approaches considered

- **A. Tag queue entries in the player (picked).** The tag survives moves,
  removes, shuffle and radio refills, and keeps two copies of one song
  apart. Cost: a careful change to the core player.
- **B. A shadow list in the room host** that reconciles queue changes.
  It leaves the player alone, but it guesses after every edit and goes wrong
  with duplicates and moves.

## Design

- **Player.** `_Entry` gets `addedBy` (a user id, or null). `PlayerState`
  exposes `addedBy`, a list in step with `queue`.
  - `playQueue`, `addToQueue`, `appendToQueue` and
    `replaceQueueAroundCurrent` take optional tags.
  - Outside a room nothing sets them, so nothing shows.
- **Host.** An untagged entry counts as the host's. A guest request's songs
  are tagged with the asking device's user id (from Presence).
- **Wire (v stays 1; older builds ignore the new fields).**
  - Each `RoomSong` gets `by`, a user id.
  - A full state carries `faces`: `{userId: {name, avatarUrl}}` for the
    ids in its window.
  - Presence gains `avatarUrl`, so the host knows each guest's picture.
  - The host remembers faces of people who left, so their songs keep the
    face.
  - A face changing (a new picture) counts as a window change, so a new
    full state goes out (SON-27 revisions).
- **Guest.** It loads its queue with the tags from the host's songs, and its
  UI reads faces from the latest full state.
- **UI.** A room-faces provider, from the room status, maps a user id to a
  name and picture.
  - The picture is the uploaded one, else the coloured initial (same look
    as `AccountAvatar`).
  - No picture shows outside a room.

## My calls (correct if wrong)

- Tags are keyed by **user id**, so two devices on one account show the
  same face.
- **Hover tooltip and screen-reader label** with the person's name. These
  are not visible text, and they help when two people share an initial.
- **Picture size:** about 22 px on queue rows. On Now Playing, about 28 px
  next to the title line.

## Non-goals

No faces outside rooms, no history of who added what after the room ends,
and no filtering by person.

## Left to the builder

The exact Now Playing placement within the header, and test layout.
