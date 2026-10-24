# Songies: YouTube Music browse, search and instant streaming — design

**Status:** draft for review · 2026-10-25
**Becomes:** Plan 5. Synced lyrics become Plan 6, listening statistics Plan 7, device sync Plan 8, packaging Plan 9.
**Builds on:** the main design (`2026-10-21-songies-design.md`), Plans 1–4 (Plan 4 is on branch `plan-4-alive-ui-themes`, not yet merged).

## Why

Playing a YouTube song in Songies takes too long. Every song goes through yt-dlp, which starts a separate program (a bundled Python on Android), loads its YouTube code and usually runs YouTube's player script before it has a link. The user wants songs to start as soon as they're tapped.

They also want Songies to stop being only a player for playlists they've already imported. They want to find music inside the app: search YouTube Music, open an artist or album, and browse a home screen of recommendations, the way [Limusic](https://github.com/SimoHypers/limusic) does.

**Success:** you type a song name, tap a result, and it's playing in well under a second on a good connection. You can spend an evening discovering music from the Home feed and artist pages without ever leaving Songies.

## Goals

1. **Instant streaming** of any YouTube song, through YouTube's own app interface ("Innertube"), with yt-dlp as the automatic fallback.
2. **YouTube Music search** with the tabs Songs, Videos, Albums, Artists and Playlists.
3. **The YouTube Music home feed:** rows of recommendations such as Quick picks, Listen again, mixes and new releases.
4. **Artist pages, album pages and YouTube Music playlist pages**, all playable.
5. **Radio:** tapping a song plays it and fills the queue with YouTube Music's "radio" for it, as YouTube Music does.

## Non-goals

- **Signing in to a Google account.** The home feed is signed out. The user said that's fine for now. Sign-in means storing login cookies, which is a separate decision. The anonymous visitor id below is *not* a sign-in.
- **Music videos as video.** Songies stays audio-only. "Videos" results play their audio.
- **Replacing yt-dlp.** Downloads keep using yt-dlp (Plan 3), and so does playlist import. yt-dlp is also the streaming fallback.
- **A hidden-browser route** (running YouTube's own scripts in a WebView, as Limusic does). It costs memory and battery, and is the most fragile part. It can be a later plan if the light route breaks too often.
- **Lyrics and statistics.** They are Plans 6 and 7. This plan only keeps what they will need, such as recording plays of searched songs the same way as library songs.

## Anti-goals (what would make this a failure even if it works)

- **Streaming gets slower, or less reliable, than today.** A failing Innertube route must fall straight through to yt-dlp, never to an error. The worst case is today's speed.
- **Anything runs in the background while idle.** No feed polling, no pre-fetching search results, no warming caches on a timer. This keeps the main design's "no idle work" rule.
- **Searched songs clutter the library.** A song you only searched for and played does not appear in your playlists or library lists.
- **The app breaks when YouTube changes something.** A parser failure on one shelf or one result shows that piece as missing. It never crashes a page or blocks playback.

## What the user decided

- **Search and play:** a search result starts playing on tap. You can add it to a playlist from its ⋯ menu, and putting it in a downloaded playlist is how it gets downloaded.
- **Source:** search goes through **YouTube Music**, not plain YouTube.
- **Home:** browse means a **home screen of recommendations**, like Limusic.
- **Account:** the **signed-out** home feed is fine.
- **Streaming route:** the **light route** (below) with the yt-dlp fallback, chosen because yt-dlp is too slow to start songs.
- **Order:** this plan comes first, before lyrics and statistics.
- **Two Wi-Fi-only settings:** the single "Wi-Fi only" setting splits into **Wi-Fi only downloads** and **Wi-Fi only streaming**.
- **Let YouTube recognise the app:** Songies keeps YouTube's anonymous visitor id between launches and reports plays back to YouTube, so the signed-out feed becomes personal over time (Listen again, better Quick picks).

## How it works

### Instant streaming (the light route)

- Songies asks Innertube's `player` endpoint for the video, impersonating one of YouTube's own app clients that still receive plain, playable stream URLs without a bot-check token. At the time of writing that is the visionOS client, which is also what yt-dlp 2026.10 used in the Plan 2 probe (`c=VISIONOS` in the stream URL). `android_vr` and `tv` have worked at times this year.
- **The client list is data, not code:** an ordered list of client identities (name, version, user agent and so on) is tried in order. Each failure moves to the next client. When they all fail, Songies falls back to yt-dlp (today's path).
- **Which client wins is remembered** for the session, so later songs go straight to it.
- **Picking the stream:** the same audio choice as today, preferring opus, then m4a, then the best audio. It reuses the existing `StreamResolver` cache: expiry from the URL's `expire` parameter, and the cache is cleared on a network change.
- **Next song ahead:** the next song's stream is found while the current one plays. The player already has a `prefetch` hook. It only runs while something is playing, so there is no idle work.
- **Respecting settings:** streaming obeys **Wi-Fi only streaming** and the offline rule, through the same checks `StreamResolver` makes today.
- **Timing check:** the plan includes a debug log of how long each route took, so the user can compare the light route with yt-dlp on their devices.
- **"Under a second" is a goal, not a pass/fail test.** The timing log checks it. Nothing is warmed up at app start, because that would break the no-idle-work rule. That's my call. Where it's free, the stream request and the radio `next` request go out together.

### YouTube Music browsing (the WEB_REMIX client)

- Search, the home feed, artist pages, album pages, playlist pages and radio all use Innertube's YouTube Music endpoints (`search`, `browse`, `next`) with the YouTube Music web client. These endpoints don't need a bot-check token signed out.
- **Parsing is defensive:** each shelf and each result row is parsed on its own, and anything that doesn't parse is dropped and logged. Tests run against recorded responses (fixtures), never the network.

### Wi-Fi-only settings (the user's decision)

- **Settings:** Settings → Downloads keeps **Wi-Fi only downloads**, which is the existing key, renamed in the UI only. That key's behaviour for the download queue doesn't change: on by default on Android, off on desktop.
- **New setting:** **Wi-Fi only streaming** is a new device-local key, *off* by default on every platform, so search-and-play works on mobile data out of the box. The default is my call. It sits in the same section, or under Playback if one exists.
- **Upgrades:** existing installs get the new streaming key with its default (off). Today the single key also blocked streaming, so a user who had it on starts streaming on mobile data after the update. That's my call, and it's what splitting the setting is for. The release notes and checklist say so.
- **Browsing ignores both settings:** search, Home feed, artist and album pages and cover art all work on mobile data. They use very little data.

### Being recognised by YouTube (the user's decision)

- **Visitor id:** the anonymous visitor id (`visitorData`) that YouTube returns is stored device-local in settings and sent with every Innertube request, so the feed is personal to this device. It is never synced and never tied to a Google account. That's my call: one device's taste isn't forced onto another.
- **Play reports:**
  - When a song played through the light route passes Spotify's 30-second rule (the same rule Plan 7's statistics use), Songies calls the play-tracking URLs from that song's `player` response, the way the YouTube Music web app does.
  - Songs played from a local file, or through the yt-dlp fallback without a `player` response, aren't reported. That's my call, rather than an extra request just to report.
  - Reports go out only while playing, so they add no idle work.
- **Consent:** if YouTube answers with a consent page (common in the EU), Songies shows a one-time "YouTube needs you to accept its terms" screen with Accept and Not now, the way YouTube's own apps do. "Not now" keeps a generic feed, and search and playback keep working either way.
- **Reset:** Settings → YouTube → **Reset YouTube recommendations** clears the visitor id and starts fresh. That's my call; it's cheap and gives the user a way out.

### Screens

- **Home:**
  - Your existing Home (greeting, quick tiles, your playlists, recents) stays at the top, unchanged.
  - Below it come the YouTube Music feed rows (Quick picks, Listen again, mixes, new releases and so on), each a horizontal row of cards.
  - The feed loads when Home is opened, not in the background, and is cached in memory for the session. Pull to refresh reloads it.
  - Placement is my call: the user's library stays first because it's what they open most.
- **Search:**
  - The existing Search tab gets YouTube Music results, with the tabs **Songs · Videos · Albums · Artists · Playlists**.
  - Matches from your own library stay as a short section at the top. That's my call, so that searching for something you already own still finds it first.
  - Results load as you stop typing, with the existing debounce.
- **Artist page:**
  - header with picture and name, then **Top songs**, **Albums**, **Singles**, and **Fans also like** (similar artists);
  - a **Play** button and a **Radio** button.
- **Album page:**
  - cover, title, artist and year, then the tracklist;
  - **Play**, **Shuffle**, and **Import as playlist**, which reuses Plan 2's import and sync.
- **YouTube Music playlist page:** the same layout and actions as the album page.
- **Song rows:**
  - **In search results and feed rows,** tapping plays the song and its radio follows in the queue.
  - **Inside an album, a YouTube Music playlist or one of your own playlists,** tapping plays that list from that song, as playlists do today. Radio is only on the Radio button and in the ⋯ menu. That's my call; it keeps one rule for lists.
  - The ⋯ menu offers: Play next, Add to queue, Add to playlist, Go to artist, Go to album, Start radio.
- **Plan 4's look throughout:** the living pages, motion, cover colours and skeleton loaders apply to all the new pages. They reuse the existing widgets, and nothing new is invented.

### Data

- **Track rows for searched songs:** a searched song that you play becomes a `tracks` row (source `yt`, `ytVideoId`), the same as an imported song, so the player, history, downloads, and later lyrics and statistics all work unchanged.
- **Kept out of the library:** it stays out of library lists unless it's in a playlist. Library views show tracks reachable from playlists. A searched song appears in recents and history, because you did play it.
- **Rich metadata:** results carry artist, album, duration and square cover art from YouTube Music. That metadata is used, and is better than what yt-dlp gives for imported songs.
- **Library lists show only songs in a playlist.** Local search, the library lists and the add-songs picker show only tracks reachable from a playlist. Recents and history show everything you played. That's my call, and it's how "searched songs don't clutter the library" is kept.
- **Searched songs stay forever:** these track rows stay as normal synced rows, and nothing cleans them up. They're small, and history, lyrics and statistics point at them. That's my call.
- **Better details for imported songs:**
  - Today the first yt-dlp stream of an imported song upgrades its artist and album through `onStreamMetadata`.
  - The light route's `player` response doesn't carry album, so the upgrade comes from the YouTube Music `next` response instead. Songies already makes that request to fetch radio, so it costs no extra request.
  - It writes only fields that are empty or came from the YouTube channel name, the same rule as today, as a stamped synced write.
  - That's my call.
- **No new synced tables.** The home feed and search results live in memory only.

### Failure handling

- **Streaming:** Innertube fails → yt-dlp → the existing skip-and-notice behaviour from Plan 3, Task 2.
- **Browse or search fails:**
  - Offline shows an "offline" state.
  - Any other error shows "Couldn't load — Retry".
  - The library part of Home and Search keeps working.
- **One bad shelf or row** is skipped without breaking the rest.
- **YouTube refusing a client identity** (HTTP 400/403) moves on to the next client. If every client fails often, the log says so, so it can be updated.

## Constraints

- Flutter and Dart only. No new native code unless a step proves it's needed. Targets are Android (minSdk 24), Windows and Linux.
- The main design's rules still apply:
  - no idle work;
  - tests never touch the network;
  - every synced write is stamped;
  - Plan 3's Wi-Fi-only behaviour holds.
- Plan 4's motion rules apply: Motion tokens, reduced motion, and no looping animation while paused.
- Requests send a normal client user agent and stay at a human pace: one request per user action, plus at most one prefetch for the next song.

## Left to the builder

- **Hand-written client or a Dart package:** hand-writing the Innertube client is the default, because it keeps the client list and parsers under our control. A Dart package may be used where it clearly saves work and is maintained.
- **Starting client list and versions:** take them from current yt-dlp and verify with a probe on the day.
- **Feed card styles:** the exact card style per shelf type. Reuse Home's existing card and tile widgets.
- **Session cache:** the size and lifetime of the in-memory feed and search cache.
- **Radio length:** how many radio songs to queue, and when to fetch more as the queue runs out.
