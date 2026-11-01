# Spotify playlist import — design

Date: 2026-11-01. Status: draft for approval. Roadmap item 6 of 6.

## Why

The user has playlists on Spotify (their own and Spotify-made ones like
Discover Weekly or genre mixes) and wants them in Songies, by pasting a link
into the same import box YouTube playlists use.

## What the user decided

- **Merged into the existing import menu:** paste a link; Songies tells a
  Spotify link from a YouTube one by its URL.
- **Both** the user's own and Spotify-made playlists.
- **Not via Spotify's API.** Songies reads the public page: the embed page
  first (which lists up to 100 songs), and for longer playlists it loads the
  playlist page in a hidden in-app browser, scrolls through it and copies
  the songs. The user accepts that this can break when Spotify changes its
  site, is slower (a progress bar), and sits in a grey area of Spotify's
  terms.
- **One-time copy:** the result is an ordinary Songies playlist; it never
  re-checks Spotify, and **no YouTube sync button** shows on it.

## Behaviour

- **Link detection:** `open.spotify.com/playlist/<id>` (with or without
  `intl-xx/` and query strings, and `spotify:playlist:<id>`) is Spotify;
  everything the dialog accepts today stays YouTube. Album and track links
  get "Only Spotify playlist links can be imported" *(builder's call)*.
  Shared text (Android share sheet) is detected the same way.
- **Reading the playlist:**
  1. The embed page (`open.spotify.com/embed/playlist/<id>`) gives the name,
     cover and up to 100 songs (title, artists, length). Verified 2026-11-01:
     a 50-song playlist came back whole; a 150-song one returned 100.
  2. If the page reports more songs than it listed, or exactly 100, the
     hidden in-app browser loads `open.spotify.com/playlist/<id>`, scrolls
     to the end collecting each row (the list only renders rows near the
     scroll position), and the songs are merged by position. Progress shows
     "Reading songs… 120 / 150".
  3. If step 2 fails (page changed, timeout), the import continues with the
     first 100 and says so: "Imported the first 100 of 150 songs — Spotify's
     page couldn't be read past that."
- **Private, deleted or invalid links:** "This Spotify playlist isn't
  public, or the link is wrong" *(builder's call, accepted as a guess)*.
- **Matching** each song on YouTube Music (the app's existing Innertube
  search, songs filter): query "title artist"; score results by artist
  match, title match and length within a few seconds; prefer official audio
  ("Song" results) over videos, and penalise live / cover / remix / karaoke
  unless the Spotify title has the same word. A score threshold marks a
  match **sure**, **unsure**, or **missing**.
- **Result:** a new local playlist named as on Spotify, with Spotify's cover
  as its cover, holding the sure and unsure matches in Spotify's order.
- **Review** *(accepted as a guess)*: after import a sheet says "142 of 150
  matched" and lists unsure and missing songs. For each: play a preview of
  the chosen match, pick another from the top search results, or remove it.
  The sheet can be closed and the playlist is usable at once; review is
  optional.
- *(Builder's call:)* **the import dialog stays open** during the import,
  with progress ("Reading songs… 120 / 150", then "Matching… 37 / 150") and
  Cancel, like YouTube imports today; no background job. A few hundred songs
  may take a minute or two.
- *(Builder's call:)* the **review sheet** is shown right after the import
  only; unsure and missing songs are not stored for later (no schema change).
- *(Builder's call:)* **importing the same link twice** makes a second
  playlist, like copying one; Songies doesn't record the Spotify id.
- *(Builder's call:)* **song names** are YouTube Music's (a matched song is
  stored once per video and shared across playlists, so a song already in
  the library keeps its name everywhere).
- **One-time:** the playlist is `source: 'local'`, has no YouTube URL, so
  the playlist page shows no sync button; it syncs to other devices like
  any local playlist.

## The hidden browser per platform (user's decision: a truly hidden one)

- **Android, and Windows with WebView2:** the in-app browser Songies already
  ships (`flutter_inappwebview`), run headless (not shown).
- **Linux:** today's in-app browser there is a visible WebKitGTK window
  (`desktop_webview_window`), with no hidden mode and shared data. The user
  chose a **new component** for a truly hidden browser rather than a
  visible window or stopping at 100. The builder picks it at the start of
  the plan (for example a headless WebKitGTK view through a small native
  plugin, or a package that offers one) and records the choice and its
  size; its data is throwaway and separate from the sign-in window's.
- *(Builder's call:)* **Windows without WebView2** (rare on Windows 10/11):
  the import offers Microsoft's WebView2 installer link; without it, the
  import stops at the first 100 with the usual message.

## Constraints

- The hidden browser is never visible to the user and keeps its own
  throwaway data (no cookies kept); see the section above per platform.
- Matching runs against YouTube Music at a polite pace (a few searches at a
  time) and can be cancelled; cancelling keeps nothing half-made unless the
  user chooses to keep what matched so far *(builder's call)*.
- Nothing is sent to the user's Spotify or YouTube account.
- Parsing (link detection, embed JSON, page rows) and scoring are pure
  functions with fixture-based tests; fixtures hold invented song names, as
  the repo's other fixtures do.

## Non-goals

- Re-syncing from Spotify, Spotify albums, liked songs, or private playlists.
- Signing in to Spotify, or Spotify's API (official or the web player's
  internal one).
- CSV import.

## Left to the builder

- The exact scoring weights and thresholds (tuned on a handful of real
  playlists during the build).
- The scroll-and-collect script for the playlist page and its timeouts.
- Where the Spotify code lives (`lib/spotify/` suggested) and how the import
  dialog hands off to it.
