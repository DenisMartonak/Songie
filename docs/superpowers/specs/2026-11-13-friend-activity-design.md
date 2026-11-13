# Friend activity (SON-35)

Part 3 of 3, split from SON-21. It builds on friends (SON-34).

## Intent

See what your friends are listening to right now and their top 10, and
join them when they're listening together. Each person can switch off what
they share.

## Decisions (user's)

- **Listening now.** Friends see what you're playing right now, unless you
  turn it off.
- **Top 10.** Friends see your top 10 artists and songs, with no minutes,
  unless you turn it off.
- **Listen together (A).** When a friend is hosting a room, you can join it
  from their row or their page. There are no invites and no listening along
  without a room.
- **How (approach 1, picked).** One small record per account on the server,
  written by your devices and read by friends' apps by polling.
- **Both sharing switches start on.**

## Approaches considered

- **1. A record per account, polled (picked).** It's simple and reliable
  offline, and works like friends does. Changes take up to a minute to show
  while you watch.
- **2. A live Realtime channel per account.** Changes would show instantly,
  but it needs many more live connections against the Realtime quota, plus
  new Realtime permission rules that check friendships.

## My calls (agreed with the decisions above)

- **Top 10** covers the last 30 days and is published at most once an hour.
- **Privacy.** The switches sit in Settings under a new "Privacy" section,
  and their values are stored on the server with the account, so every
  device agrees. Turning one off clears what was published at once.
- **Stale status.** A "now playing" older than 15 minutes counts as not
  listening, which covers an app that closed without clearing it.
- **Join needs sharing.** The room code travels in the listening part, so
  Join shows only when the friend shares listening and hosts an open room.

## Design

### Server

The migration is `supabase/migrations/20261115120000_friend_activity.sql`,
documented in `docs/supabase.md`.

- **Table** `public.activity(user_id uuid primary key references auth.users
  on delete cascade, share_listening boolean not null default true,
  share_top boolean not null default true, now_playing jsonb,
  now_updated_at timestamptz, room_code text, top jsonb, top_updated_at
  timestamptz)`.
- **Helper** `public.are_friends(a uuid, b uuid) returns boolean`. It is
  security definer and reads `friendships` for an accepted row.
- **Reading.** A select policy lets you read your own row, plus a friend's
  row when `are_friends(auth.uid(), user_id)`.
  - A friend's view must not show what they turned off. The function
    `friend_activity()` returns, for each friend:
    - their `now_playing`, `now_updated_at` and `room_code` only when
      `share_listening`;
    - their `top` only when `share_top`.
  - The app reads friends through this function, and the table's select
    policy covers only your own row.
- **Writing** happens only through functions:
  - `set_sharing(p_listening boolean, p_top boolean)`. Turning a switch off
    clears its fields.
  - `publish_now_playing(p_now jsonb, p_room_code text)`. A null `p_now`
    clears it. It is ignored while sharing listening is off.
  - `publish_top(p_top jsonb)`. It is ignored while sharing top is off.
  - All are security definer, with `search_path` set to empty, callable by
    signed-in users only.
  - There are no table write grants.
- **Data shapes:**
  - `now_playing`: `{title, artist, artUrl?, videoId?}`.
  - `top`: `{artists: [{name}], songs: [{title, artist, artUrl?}]}`, at most
    10 of each.

### App

- **`ActivityBackend`.** It wraps the RPCs and `friend_activity()`, and is
  faked in tests.
- **`ActivityPublisher`.** It runs while you're signed in.
  - It publishes now playing when the current song changes or play/pause
    flips, debounced by 2 s.
    - It sends null when paused or stopped, or when the queue is empty.
    - It includes the room code while you're hosting.
  - About every 5 minutes while playing, it publishes again, so a long song
    doesn't go stale.
  - It publishes the top 10 at sign-in and then at most hourly, from
    `StatsRepository` for the last 30 days.
  - It reads the sharing switches from the server, so it skips work while
    they're off.
- **`FriendsService`** gains `activity`, a map of user id to
  `{nowPlaying?, roomCode?, top?}`. It is fetched with every refresh, and
  every minute while the Friends page or a friend's page is open.
- **Settings → Privacy.**
  - Switches "Share what I'm listening to" and "Share my top 10 with
    friends".
  - Signed out, the section says "Log in to share with friends".
  - The switches show the server's values and change them through
    `set_sharing`.
- **Friends page.** Each friend's row gets a second line,
  "♪ Song · Artist", while they're listening.
- **Friend page:**
  - A now-playing card (cover, song, artist), with "Join" (it joins their
    room by code) when they host one. With no listening shared, it says
    "Not listening right now".
  - Then "Top artists" and "Top songs", 10 each.
  - When top isn't shared, those sections are absent.

## Non-goals

No invites, no listening along without a room, no history of what friends
played, and no minutes listened.

## Left to the builder

- Exact layout of the card and lists.
- The publisher's home in the provider graph.
- The SQL details beyond the rules above.
