# Profile redesign (SON-39)

## Intent

The friend page is "bland and without soul": artists and songs have no
pictures, there are no numbers, and the scrollbar sits at the edge of a
720 px column instead of the window. The user drew two mockups (phone and
PC) and wants **one profile layout** for both their own profile and a
friend's, with the friend seeing the same stats they see themselves.

Success: opening a friend feels like opening your own profile, with
pictures, minutes, a chart and the period picker, in the theme's colors.

## Goals

- One profile view, used by `/profile` (signed in) and the friend page.
- Phone layout (narrow): centered avatar on a soft theme-colored glow, big
  name, "N friends", the button row, then "Listening to …" (when they are),
  period picker as a segmented control, a card with minutes listened and
  the chart, "Top 10 artists" (round photos, minutes) and "Top 10 songs"
  (square covers, plays). Each list shows 5, then a full-width "Show more".
- PC layout (wide): avatar left, name and "N friends" beside it, buttons
  far right; "Listening to …" under the avatar. Period chips and a huge
  minutes number ("minutes listened in the last 30 days") on the left, the
  chart filling the right. Artists and songs side by side, each with
  "Show more" in its header and the rank as a large muted number on the
  right of each row.
- Own profile: **Edit profile** (filled, accent) and **⋯** (Log out,
  Delete account). The Account section and the sync status line go: sync
  runs often enough on its own.
- Friend's profile: no Edit profile; **⋯** holds Remove friend. Join stays
  on "Listening to …" while they host a room.
- Friends see everything: all four periods, total minutes, chart, top 10
  artists and songs with minutes and plays, with pictures.
- Real pictures on both profiles: artists show their YouTube Music photo,
  songs their cover.
- The scrollbar sits at the window edge; content stays width-limited.

## Non-goals

- No display name separate from the username; the big name is the
  username and there is no "@handle" line.
- No live push of a friend's stats; they are as fresh as their last
  publish (at most an hour old, and only while their app runs).
- No change to the friends list page, the right pane or the phone shell.
- No "Sync now" anywhere on the profile.

## Anti-goals

- A friend must never see stats while that friend has sharing off.
- The profile must not look different for self vs friend beyond the
  buttons and the menu.
- Hard-coded colors: everything comes from the theme (`SongiesColors`,
  color scheme). The orange in the mockups is just the mockup theme.

## Approaches

1. **The friend's app publishes a full stats summary (chosen).** The
   existing hourly `publish_top` carries the whole summary for all four
   periods with picture links; one view renders a `ProfileStats` that
   comes either from the local `StatsRepository` or from a friend's
   published summary.
2. **The viewer computes stats from a friend's raw listens via cloud
   sync.** Rejected: shares every listen with timestamps, heavy download,
   and needs new read access to synced data.

The user picked 1 ("A": friends see everything).

## Design

### Shared data: `ProfileStats`

A plain model per period: total, previous total (for the "+12 %" line),
buckets, top artists (name, minutes, plays, photo URL, YTM browse id),
top songs (title, artist, plays, minutes, cover URL, video id). Local
stats map into it (local cover files stay as `artworkRef` for own songs;
remote ones carry URLs). The view takes a source: "mine" (reads
`periodStatsProvider`) or "friend id" (reads their summary from
`friendsStateProvider`).

### What is published

`TopSummary` becomes a stats summary in the same `activity.top` jsonb,
with a version field: for each of `week`, `month`, `halfYear`, `year`:
total ms, previous total ms, bucket ms list (bucket boundaries are derived
by the viewer from the period and the summary's `at` date), top 10 artists
(`name`, `ms`, `plays`, `photo?`, `browseId?`) and top 10 songs (`title`,
`artist`, `ms`, `plays`, `videoId?`). Readers stay lenient: an old
publisher's payload (only `artists`/`songs` names) shows as a 30-day top
10 without numbers or chart; a new reader ignores unknown fields. The new
payload also keeps the old top-level `artists`/`songs` keys (30-day names)
so friends on older app versions still see a top 10. `at` is the
publisher's local date. Keep the payload under 64 kB (trim URLs or the
year's list if needed).

Freshness (Claude's call): a friend's stats are shown as published, with
a muted "Updated 3 weeks ago" line under the period picker when the
summary is more than a day old, and the chart's dates come from `at`.

Published as today: on sign-in and at most once an hour, only while
"share top" is on. The Privacy switch is relabelled "Share my stats with
friends".

### Pictures

- Songs: `videoId` from the track (`ytVideoId` for YouTube tracks) gives
  `i.ytimg.com/vi/<id>/hqdefault.jpg`. Local-file songs have no public
  cover: a themed placeholder (seeded `Artwork` look) on a friend's view;
  on your own profile they keep the local cover.
- Artists: at publish time, for each top artist with a YouTube sample
  track, find the browse id with `ArtistLookup.forTrack`, then the photo
  from `ytm.artist(browseId)`. Saved artists (`saved_artists` table)
  already have `thumbnailUrl`; use them first. Answers are kept in a small
  persisted cache keyed by artist name so an hourly publish costs nothing
  after the first. Failures leave the field empty and retry next publish.
- Your own profile's artist rows use the same cached photo when known,
  else today's cover-of-top-song look.
- Tapping an artist with a browse id opens their YTM page (friend's too);
  otherwise Search, as today. Tapping a friend's YouTube song plays it
  through the existing YouTube play path; local-only songs aren't tappable.

### Server (one migration)

- `publish_top`: size limit 16 kB → 64 kB.
- `friend_count(p_user uuid) returns int`: accepted friendships of
  `p_user`, callable only for yourself or an accepted friend (else null).
- `friend_activity()` also returns `share_top` (boolean), so the app can
  tell "sharing off" from "nothing published yet" (today both are a null
  `top`). The return type changes, so the function is dropped and
  recreated.
- Apply and test with the podman postgres recipe before release.

### Layout

- Breakpoint: the wide (PC) layout when the content area is at least
  ~840 px wide, else the phone layout. The page scrolls with the
  scrollbar at the window edge; the content inside is centered and
  limited (phone ~720 px, PC ~1200 px).
- Header glow: a radial gradient from the theme accent at low opacity
  behind the avatar, fading into the background.
- Edit profile opens a sheet with the picture (existing `PictureViewer`)
  and the username (existing `InlineUsername`). Email shows there too.
- ⋯ menu: own → Log out (with the current unsent-changes check), Delete
  account (error color, current confirm). Friend → Remove friend (current
  confirm), then pops back.
- "N friends" is tappable on your own profile (opens `/profile/friends`,
  keeps the request dot); on a friend's it is plain text, hidden until the
  count loads.
- Signed out, `/profile` keeps today's Sign up / Log in.
- Period selection is per page (your choice doesn't change the friend's
  page and vice versa); default 30 days.
- A friend with stats sharing off: header and "Listening to …" only, with
  "<name> doesn't share their stats". Sharing on but nothing published
  yet (or no listens): "No stats from <name> yet". A friend on an old app
  version whose server row lacks the flag is treated as sharing on.

## Left to the builder

Exact spacing, font sizes and breakpoint; how `StatsBody` is split into
the new view (the dead `StatsPage` can go); widget keys for tests; the
cache's storage (settings repository or a small table); test split.
