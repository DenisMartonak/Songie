# Songies: YouTube sign-in for a personal feed — design

**Status:** draft for review · 2026-10-27
**Becomes:** Plan 7. Plan 6 is the "one song menu everywhere" change, branch `plan-6-song-menu`. After this plan come synced lyrics (Plan 8) and listening statistics (Plan 9). Device sync and packaging follow; their order is the builder's guess until the user sets it.
**Builds on:** the main design (`2026-10-21-songies-design.md`), the YouTube Music design (`2026-10-25-songies-youtube-music-design.md`) and Plans 1–6. Read `docs/innertube-notes.md` first: it records how Songies talks to YouTube today.

## Why

Plan 5 gave Songies YouTube Music's Home feed, signed out. It's personal only to an anonymous visitor id that Songies has been building up since Plan 5. The user wants Songies' Home to be **their** YouTube Music Home: the Quick picks, Listen again and mixes that years of their own listening built, which they see in the YouTube Music app.

**Success:** after signing in once on a device, Home in Songies shows the same kind of personal rows the YouTube Music app shows that account. Songs played in Songies also count in that account's YouTube history, so the feed keeps improving from both apps.

## What the user decided

- **A personal feed is the point.** The feed is all they want from sign-in for now.
- **Plays count on YouTube.** While signed in, songs played in Songies go into the account's YouTube history, as the YouTube Music app records them.
- **Their main Google account is fine.** They were told that Google doesn't officially allow third-party sign-in, and that accounts used this way can occasionally be flagged or challenged. They said they're comfortable with that.
- **Songies playlists stay in Songies.** Adding songs to playlists is Plan 6, into Songies playlists only. Nothing is written to the YouTube account's playlists or library.

## Goals

0. **All three platforms at once.** The user wants to test sign-in everywhere, so this plan ships Android, Windows and Linux together, not one platform at a time. Each platform's sign-in route is done and testable when the plan finishes. Windows is built on the user's PC, as in earlier plans, so its route is written and covered by tests here, and the manual checklist gets a sign-in check per platform.
1. **Sign in to YouTube** (a Google account) once per device, from Settings → YouTube.
2. **A personal Home feed while signed in:** `FEmusic_home` as that account sees it.
3. **Play reports go to the account:** the existing Plan 5 play reports (`PlayReporter`, the 30-second rule) are attributed to the signed-in account, the way the YouTube Music web app does it.
4. **Sign out** from the same place. It removes everything sign-in stored on that device.

## Non-goals

- **The YouTube Music library in Songies:** liked songs, saved playlists, albums, subscriptions and history pages. The user said the feed alone is enough for now.
- **Writing to the account:** likes, adding to YouTube playlists, subscribing. Plan 6's menu adds to Songies playlists only.
- **Account-specific search results or signed-in streaming.** Search and the `player` stream route stay as they are (see "What stays anonymous").
- **More than one account per device**, and switching between accounts.
- **Moving the sign-in between devices.** Each device signs in by itself.

## Anti-goals (what would make this a failure even if it works)

- **Signing in makes anything worse.** Playback speed, the yt-dlp fallback, search and the library must behave exactly as today whether signed in or not.
- **A broken or expired sign-in shows errors or blocks the app.** If the account's session stops working, Songies quietly drops back to the signed-out feed. It tells the user once, in Settings and as a single quiet notice, that they need to sign in again.
- **The login leaks.** The sign-in secrets (cookies) never appear in logs, notices, crash text, test fixtures, docs, exported files, device sync, or anything committed to the public repo. Songies never sees or stores the Google password. The user types it only into Google's own sign-in page.
- **Idle work.** Signing in adds no background polling, no keep-alive requests and no refresh timers. Requests still come only from user actions and from playback, as in Plan 5.

## How it works

### Signing in

- Settings → YouTube gets a **Sign in to YouTube** row. When signed in, the row shows the account's name and picture where available, plus **Sign out**.
- Signing in opens Google's own sign-in page for YouTube Music inside Songies. The user signs in there as on any website, with their password, two-step verification and any Google prompts. Songies never sees the password.
- When the page reaches music.youtube.com signed in, Songies keeps that browser session's YouTube/Google cookies (the sign-in session) and closes the page.
- **Platforms:** an in-app web page works on Android and Windows.
  - **Linux (the user's main machine, Nobara/Fedora) gets two routes, in this order** (my call; the user can overrule):
    1. Google's page inside Songies, if a maintained WebKitGTK-based package works there.
    2. **"Use the YouTube sign-in from my browser".** Songies reads the YouTube/Google cookies from the user's own browser profile, the same way yt-dlp's `--cookies-from-browser` does, covering Firefox and the Chromium family. It does this only after the user picks the browser and confirms, and it keeps only the YouTube/Google cookies it needs. If the browser's cookie store is locked or encrypted in a way Songies can't open, it says so plainly.
  - If route 1 works reliably, route 2 can stay as a secondary option. The builder decides that after trying route 1.
  - A manual "paste your cookies" field is not offered to users. It may exist as a hidden developer fallback for testing.
  - Whatever route is used, the user experience goal is the same: sign in on Google's page (or reuse the browser's existing sign-in), and come back signed in.
- **Where it's stored:** in the platform's secure storage: Android Keystore-backed storage, Windows Credential Manager, or the Linux Secret Service/libsecret (KWallet or GNOME Keyring). It is never stored in the drift database. Secure storage is required, with no home-made encrypted-file fallback (my call). So it is never synced, never exported, and wiped by Sign out. If secure storage is unavailable on a Linux machine, sign-in is not offered there. A short explanation shows instead.

### Using the sign-in

- **Feed and play reports go out signed in.** While signed in, the YouTube Music `browse` request for Home sends the account's cookies and the authorization header that YouTube's web client derives from them, as ytmusicapi and yt-dlp do. The play-tracking requests from `PlayReporter` do the same.
- **What stays anonymous:**
  - The `player` stream route keeps using the app identities from Plan 5 (visionOS, android_vr) without the account. Mixing a web login into app-identity requests could break streaming, and the user didn't ask for signed-in streaming.
  - Search, artist, album and playlist pages and radio also stay as today: signed out.
  - *The builder may send these signed in* if a probe shows it is harmless and gives the account-aware results the YouTube Music web app shows. The default is signed out, to keep the blast radius small.
- **The anonymous visitor id** (Plan 5) stays as it is and keeps being used when signed out. Whether the signed-in requests also send it is left to the builder, following what the web client does.
- **Consent (EU):** a signed-in session normally carries the account's own consent choice. The Plan 5 consent sheet should not appear for a signed-in user. If YouTube still asks, the existing sheet behaviour applies.

### When the sign-in stops working

- Google sessions end: the user signs out elsewhere, changes their password, or Google asks them to sign in again.
- When a signed-in Home request is refused, or comes back signed out, Songies:
  - drops back to the signed-out feed for that load;
  - marks the sign-in as expired;
  - shows "Sign in again" in Settings → YouTube, plus one quiet notice.
- It does not retry in a loop. It does not delete the stored session until the user signs out or signs in again.
- Play reports that fail while signed in are dropped, exactly like Plan 5's failed reports: logged and not retried.

### Signing out

- **Sign out** deletes the stored session from secure storage, invalidates the Home feed (it reloads signed out the next time Home is opened), and leaves everything else alone: the visitor id, consent and library.
- It doesn't sign the account out on Google's side. Optionally, the builder may also call Google's sign-out endpoint if that's simple.

### Being careful with the account

- **Requests stay at the human pace Plan 5 set:**
  - one Home load per Home open or pull-to-refresh;
  - play reports only after the 30-second rule.
  - Nothing new runs in the background.
- The signed-in requests look like YouTube Music's web client. They use its client name and version, user agent and headers, so the account's traffic looks as close as possible to normal browser use.

## How it gets verified

- **The build starts with a probe on the user's machine** (my call): one live sign-in with the real account, run like Plan 5's Innertube probe. It establishes:
  - which client identity, headers and authorization header give a personal Home;
  - whether Plan 5's anonymous play-tracking URLs count in the account's history. If they don't, the reporter may make one extra signed-in request per qualifying play, made only when a play reaches the 30-second rule, to get account tracking URLs. That is allowed (my call).
  - what a signed-out-on-Google's-side Home response looks like, so expiry detection is based on a real marker, not a guess.
- Everything recorded is scrubbed before it's saved (see Data). Later tasks build on the probe's findings.
- **If the user isn't available to sign in when the probe runs** (my call): it becomes a manual check for the user afterwards. Everything is still built against hand-written fixtures, and the plan's progress notes mark the personal feed, history attribution and expiry detection as unverified until that check passes.

## Data

- **No new synced tables.** The sign-in session lives in secure storage on the device.
- One device-local flag (or the presence of the secure-storage entry) says "signed in". The account's display name and picture URL may be cached device-locally for the Settings row.
- Fixtures for tests are hand-written or recorded and scrubbed, following the Plan 5 rules. **Recording a real signed-in response must scrub every cookie, account id, email address, name and picture URL**, as Plan 5 scrubbed visitor ids. `test/innertube/fixtures_scrubbed_test.dart` grows to check these too.

## Constraints

- Flutter and Dart only, except for the platform packages needed for an in-app web page and secure storage. Targets are Android (minSdk 24), Windows and Linux.
- **Rules from earlier plans still hold:**
  - from the main design and Plan 5: no idle work, tests never touch the network, every synced write is stamped, the visitor id is never synced, and a failing Innertube route never errors;
  - from Plan 4: Motion tokens, reduced motion, no looping animation while paused, AA contrast.
- The repo is public. Nothing identifying the account may be committed.

## Left to the builder

- The in-app web page package for each platform, and whether Linux route 1 is good enough on its own.
- Exactly which cookies to keep, and how the authorization header is built. Follow ytmusicapi and yt-dlp's current behaviour, and record it in `docs/innertube-notes.md` the way Plan 5 recorded its probe.
- Whether search, browse pages and radio also go out signed in (see "What stays anonymous"). The default is no.
- Whether the visitor id is sent alongside the sign-in.
- How the account's name and picture are obtained. If it isn't simple, show "Signed in" without them.
- The exact expiry marker, which comes from the probe (see How it gets verified).
