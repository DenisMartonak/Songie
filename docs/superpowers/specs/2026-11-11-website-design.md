# Songies website (SON-22): design

Date: 2026-11-11. Linear: SON-22 (Urgent, Todo). Related: SON-5 Listen
together (merged), SON-6 Passkeys (later; not part of this).

## Why

Discord only makes `https://` links clickable, so Listen together room links
(today `songies://room/<code>`) can't be clicked there. A room link needs to
point at a web page that opens Songies straight into the room. While we're at
it, Songies gets a proper home page: what it is, a download that fits the
visitor's device, a link to the GitHub repo, and a short showcase of the app.

## Goals

- Room links become `https://denismartonak.github.io/Songie/r/<CODE>` and
  are clickable in Discord. The page opens Songies into the room by itself;
  a button does the same if the browser blocked or the person dismissed it.
- A home page with the animated S from the icon, a device-aware Download,
  a GitHub link, a showcase of the app, and a button to a Features page.
- A Features page built from the README's feature list.
- A script that drives the real Linux app through a few scenes and turns
  them into short web videos (screenshots if a scene won't come out smooth).

## Non-goals

- Passkeys / `.well-known/assetlinks.json` (SON-6). A project page under
  `/Songie/` can't serve the domain root; that is solved when passkeys come
  (custom domain or a `DenisMartonak.github.io` repo).
- A custom domain.
- Android App Links / verified https links that skip the browser. The page
  hands off to the existing `songies://` scheme.
- Showing who sent the invite (the user chose no name: the static page only
  knows what's in the link).
- Any server, database lookup, analytics or cookies on the site.
- An app release (user's decision). This work stops at the app change
  merged on `main`; the user releases (1.4.1 or later) when they choose.
  Until then installed apps keep sharing `songies://` links, and the room
  page simply waits for the first release that shares the new address.

## Anti-goals

- The capture script must never touch the user's real library, accounts or
  cloud data. A demo run that signs in with the user's Songies account and
  syncs demo playlists into their cloud would be a failure even if the
  videos look great.
- The site must not feel like a generic template; it should feel like the
  app (its colours and S), as in the chosen mockup.
- Room links must not break for anyone: the app keeps accepting
  `songies://room/<code>` and the old bare-https shape it already parses.

## Hosting (user's decision)

- Same repo, folder `website/`. `docs/` stays internal notes.
- Published to GitHub Pages by a GitHub Actions workflow
  (`.github/workflows/pages.yml`) on pushes to `main` that touch
  `website/**`, plus manual run. Uses the official
  `actions/configure-pages`, `actions/upload-pages-artifact`,
  `actions/deploy-pages`.
- Address: `https://denismartonak.github.io/Songie/`. All links inside the
  site are relative or account for the `/Songie/` base.
- One manual step for the user: repo Settings → Pages → Source: GitHub
  Actions (or Claude sets it with `gh api` if the user allows).
- Plain static files: HTML, CSS, a little vanilla JS. No build step, no
  framework *(Claude's call: nothing to maintain, fast to load)*. Fonts from
  Google Fonts are fine.

## Look (user's decision: mockup "A · Signal")

Inspired by the Spotify × Bastille page the user linked: a dark full-screen
stage, one animated mark in the middle, small text in the corners.

- Background: near-black with a deep violet glow in the middle
  (`radial-gradient(#2a0f45 → #0b0612)` in the mockup).
- The S: the exact stroke path from `assets/icon/songies_icon.svg`, stroked
  with the icon's gradient `#7C3AED → #EC4899`, with a soft pink glow. On
  load it draws itself (~2 s), then sound rings in the same gradient pulse
  out from the centre, one every ~0.7 s, fading as they grow.
- Corners: top-left **Download** (see below), top-right **GitHub** (links
  to `https://github.com/DenisMartonak/Songie`), bottom-left a one-line
  tagline, bottom-right "Android · Windows · Linux".
- `prefers-reduced-motion`: the S shows fully drawn, no rings
  *(Claude's call)*.
- Works at phone width; no horizontal scroll.
- The mockup (`.superpowers/brainstorm/…/home-direction.html`, option A)
  is the reference for feel, not code to copy. Use the frontend-design
  skill when building.

## Home page

1. **First screen:** the stage above, full viewport.
2. **Showcase** (scroll down): four topics as tabs or a row of cards:
   Themes, Playlists & covers, Downloads, Search. Each shows a short looping
   muted video (autoplay, `playsinline`, with a poster image) made by the
   capture script, or a screenshot if that scene has no video. Until the
   script has run, a still image or a tasteful placeholder per topic.
3. A **Features** button leading to the Features page.
4. A small footer: GitHub link, licence line ("For educational purposes
   only", as in the README).

## Download button

- Detect the visitor's device from the user agent: Android → the `.apk`;
  Windows → `-windows-setup.exe`; Linux (not Android) → `.AppImage`.
  Label says which: "Download for Android" etc.
- Release assets carry the version in their name
  (`songies-X.Y.Z.apk`, `songies-X.Y.Z-windows-setup.exe`,
  `songies-X.Y.Z-x86_64.AppImage`), so the page asks the GitHub API for the
  latest release (`api.github.com/repos/DenisMartonak/Songie/releases/latest`)
  and picks the matching asset's download URL.
- Fallback when the API call fails, is rate-limited, or the device is
  anything else (iPhone, Mac, unknown): the button reads "All downloads"
  and links to `https://github.com/DenisMartonak/Songie/releases/latest`.
  The button must be a working link before any JS runs (start as that
  fallback, then upgrade).
- Note: the latest published release is v1.4.0 (shares `songies://` room
  links). The page doesn't care which release is latest.

## Room page

- Address: `/Songie/r/<CODE>`. GitHub Pages has no server routing, so
  `website/404.html` (served for any unknown path) handles `/r/<CODE>`
  *(Claude's call; a builder may choose another static trick as long as the
  visible address the app shares is exactly `…/Songie/r/<CODE>`)*. Any
  other unknown path shows a normal "Page not found" with a link home.
- The code is validated with the same rules as the app
  (`lib/room/room_links.dart`: 8 chars from
  `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, dashes/spaces ignored, case
  insensitive). An invalid code shows "This link doesn't look right" and a
  link home.
- Same dark look with the S (smaller) and the rings.
- Text: **"You've been invited to listen together"**, plus the room code
  shown as `ABCD-2345` *(Claude's call: lets people type it into the app if
  all else fails; the app already accepts typed codes)*.
- On load it immediately navigates to `songies://room/<CODE>` so the
  browser shows its "Open Songies?" prompt.
- **Open Songies** button: does the same again (fallback if the prompt was
  dismissed or blocked).
- Below: "Don't have Songies yet?" with the same device-aware download, and
  a note that joining needs a Songies account (from the Listen together
  design: guests must be signed in).
- The page never tries to tell whether the app opened; it just stays put.

## Features page

- `website/features/` (or `features.html`): the README's feature groups
  (One library for everything, Listening, Make it yours, Across your
  devices), plus Listen together, written for a visitor, in the same look.
  Can reuse showcase images where they fit. Link back home and the
  Download button.

## App changes

- `kRoomSiteBase` in `lib/room/room_links.dart` becomes
  `https://denismartonak.github.io/Songie`, so `roomLink` gives
  `…/Songie/r/<CODE>`.
- `parseRoomCode` must accept that address: today it requires exactly two
  path segments `r/<code>`; it must also accept `Songie/r/<code>` (i.e.
  the last two segments are `r` and the code). Keep accepting
  `songies://room/<code>`, the old two-segment https shape, and typed codes.
  Unit tests in `test/room/` for each.
- No manifest or installer changes: the page hands off via the existing
  `songies://` scheme (Android intent filter, Windows installer, Linux
  `.desktop`/AppImage registration).

## Showcase capture script

- Lives in the repo (e.g. `integration_test/showcase/` plus
  `tool/showcase.sh`). One command records everything; the user re-runs it
  after redesigns.
- Runs the real Linux app (`flutter test integration_test/... -d linux`,
  Flutter at `~/development/flutter/bin/flutter`) with a scripted
  `WidgetTester` driving taps and typing. It opens a window on the user's
  desktop while it runs; that's fine.
- Frames are captured from inside the app (e.g. a `RepaintBoundary` at the
  app root, `toImage` at a steady rate), not by an outside screen recorder,
  so it works on Wayland with nothing to install. ffmpeg (installed) turns
  frames into `.webm` (VP9) plus `.mp4` (H.264) for Safari, and a poster
  `.jpg` (or `.webp`). Target: each clip 5–15 s, a fixed desktop window
  size (e.g. 1280×800), small files (aim under ~2 MB each).
- Output goes to `website/media/showcase/`, committed.
- **Isolation (hard requirement):** the run uses a throwaway data folder
  (`XDG_DATA_HOME` pointed at a temp dir; `lib/core/paths.dart` honours
  it) and must not read or write the user's keyring session: no Songies
  account sign-in, no cloud sync, no YouTube sign-in. Secure storage
  (`flutter_secure_storage`, Secret Service) is shared with the real app,
  so the builder must make sure the demo run can't pick up the user's
  stored session (e.g. override the relevant providers in the test, or use
  a separate storage key prefix) and must verify it.
- **Demo library** seeded by the script (user's decision): **real, popular
  songs from YouTube Music**, added by their YouTube video IDs with their
  real thumbnails, so the clips look like a real library. The user named
  examples: "Adela", "Nicole Kidman", "Ain't in LA"; the builder looks up
  their IDs (and a dozen or so similar popular tracks) once and pins them
  in the seed, so the run doesn't depend on search results. A handful of
  playlists with custom cover images (images made for this, committed
  under the test folder). The Themes scene plays one of the seeded songs so
  "colours follow the album cover" has a real cover. Search and download
  scenes use real YouTube Music over the network; the download scene
  downloads a seeded song.
- Scenes:
  1. **Themes:** open theme settings and switch through a few themes,
     including colours that follow the album cover.
  2. **Playlists & covers:** create a playlist, add songs, set a custom
     cover.
  3. **Downloads:** download a song or playlist and show progress finishing.
  4. **Search:** type a query and show songs/albums/artists results.
- If a scene can't be made smooth or reliable (e.g. network-dependent
  flakiness), produce 1–3 screenshots for it instead; the site shows those.
- Music playback audio is irrelevant (videos are muted).

## Build order (Claude's call)

1. Website (home, room page, features page, Pages workflow) with still or
   placeholder showcase images, plus the app link change. This unblocks
   clickable room links.
2. Capture script, then swap in the videos.

## Left to the builder

- Exact copy text beyond what's quoted above; tagline wording.
- Typography choice (the mockup used Space Grotesk).
- Showcase layout (tabs vs cards), sizing, how the rings are implemented
  (SVG + Web Animations in the mockup).
- Social preview tags (`og:image` etc.) are welcome since links get shared
  in Discord: a room link preview reading "You've been invited to listen
  together · Songies" would be nice.
