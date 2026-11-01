# Age-restricted songs — design

Date: 2026-11-01. Status: draft for approval.

## Why

A user found a song on YouTube (`S4-2QqwHf5c`) that Songies can't play. The
video is age-restricted. Songies streams anonymously, so YouTube refuses it,
and Songies then marks the song **unavailable for good**, the same way it
marks a deleted video. The user is signed in to YouTube in Songies, but that
session is used only for the Home feed, never for playback.

Verified on 2026-11-01 (desktop, Linux, yt-dlp 2026.10.26):

| Request | Result |
|---|---|
| Innertube `player`, VISIONOS and ANDROID_VR, with visitor id | `LOGIN_REQUIRED` "Sign in to confirm your age" |
| yt-dlp, no cookies | `Sign in to confirm your age` |
| yt-dlp, signed-in cookies, no JS runtime | `Sorry, this content is age-restricted … only available on YouTube` |
| yt-dlp, signed-in cookies, `--js-runtimes node` | OK, format `251` opus |

So playing it needs **both** the user's YouTube login **and** a JavaScript
runtime that yt-dlp uses to solve YouTube's challenge. The desktop yt-dlp
build already bundles the challenge solver (`yt_dlp_ejs-0.8.0` in `-v`
output). youtubedl-android 0.18.1 bundles QuickJS (`libqjs.so`) and adds
`--js-runtimes quickjs:<path>` to every run by itself.

## Goals

- Signed in: age-restricted songs play (stream and download), on desktop and
  on Android.
- Signed out: the user is told the song is age-restricted and that signing in
  to YouTube will let it play.
- Signed in, but YouTube still refuses (the account can't watch age-restricted
  videos, e.g. its age isn't verified): the user is told this account can't
  play age-restricted songs.
- An age-restricted song is never marked unavailable.

## Non-goals

- Getting around the age check without an account.
- Sending the login for ordinary songs. Normal playback stays anonymous and
  takes the same path as today.
- PO tokens (yt-dlp's warning about `web_creator` needing one is harmless: a
  different client returned the audio).

## Anti-goals

- A signed-in user being told to sign in *before* their account was tried.
- Downloading anything large without asking.
- A login cookie ending up in a log, an error message or a file that outlives
  the yt-dlp run.

## Behaviour

### Telling an age-restricted song apart

Today `ytErrorKindOf` (`lib/youtube/ytdlp_client.dart`) folds
"Sign in to confirm your age" and "age-restricted" into `notFound`, and
`InnertubeStreamSource._isVideoLevel` counts an age `LOGIN_REQUIRED` as
video-level. Add a new `YtErrorKind.ageRestricted` for both, and keep it apart
from `notFound` all the way to the player. `PlayerService` must not call
`_reportUnavailable` for it.

### Signed out

The song doesn't play. The user sees a message saying the song is
age-restricted and needs a signed-in YouTube account, with a button that opens
the existing YouTube sign-in (browser sign-in on desktop, the in-app sign-in
on Android). The queue moves on as it does for any other song that can't play.

### Signed in

1. The usual route runs first: Innertube, then anonymous yt-dlp. *(Changed
   after the desktop check, at the user's request:)* when Innertube already
   says `ageRestricted`, the anonymous yt-dlp run is skipped; it only gave
   the same answer about 4 s later.
2. If either says `ageRestricted`, Songies runs yt-dlp **once more** with the
   session's cookies (see Cookies) and a JS runtime (see Runtime).
3. If that run returns a stream, it plays.
4. If it fails with an age error again **and a runtime was in use**, the
   user sees: "This YouTube account isn't valid for age-restricted songs."
   *(Builder's call, from the user's "tell the user that this account is not
   valid":)* the message has a button to sign in again or with another
   account, because an expired session and an account without age
   verification look the same to Songies, and signing in fixes the first.
5. An age error from a run **without** a runtime never shows that message.
   On desktop it means the helper is missing (see Runtime). On Android it
   means the solver script is missing; that is a bug, logged as such.
6. Any other failure (network, extractor) behaves as it does today.

Downloads of an age-restricted song follow the same rule: the download run
gets the cookies and the runtime when signed in.

**When the prompt may appear** *(builder's call)*: only when the user picked
the song themselves (tapped it, or pressed next/previous to it). Then playback
waits for the answer. When the queue reaches the song by itself, when the
next song is prefetched, or when a download runs, Songies never prompts:
- with a runtime, the signed-in retry runs as usual (prefetch included);
- without one, the song is skipped (or the download fails) with the
  age-restricted note, and the note says the helper can be installed from
  Settings.

### Songs already flagged

Songs flagged unavailable before this change may be age-restricted (the
user's song almost certainly is). On upgrade, a one-time migration clears
`unavailable` on every YouTube track so each is checked once more. A truly
dead song is flagged again on its next play, costing about 2 s once (the same
cost noted in ruling R12).

*(Builder's call:)* the clear goes through the repository with a fresh sync
stamp, the same way `markUnavailable` writes, so it reaches the user's other
devices. A device still on an older version may flag an age-restricted song
again and sync that back; once it updates, the flag clears on that song's
next successful play. All devices belong to one user, so this is a
short-lived oddity, not data loss.

## Cookies

- The `YtSession` cookies are written to a Netscape-format cookies file
  (`--cookies <file>`) in Songies' private data folder, created with mode
  0600, and deleted when the run ends, including on failure or cancel.
- Only the cookies the session already holds. By ruling R8 that is
  `youtube.com` cookies only, stored as name→value pairs. *(Builder's call:)*
  each line uses domain `.youtube.com`, path `/`, secure `TRUE`, and an
  expiry one year ahead. Nothing new is read from the browser at play time.
- **Gate:** the verified run used a full Firefox cookie export, not Songies'
  own session. The plan's first task checks that the stored `YtSession`
  cookies, written as above, play `S4-2QqwHf5c` (desktop browser sign-in, and
  the Android in-app sign-in on a device). If they don't, building stops and
  the question goes back to the user, because the fix would mean revisiting
  R8.
- yt-dlp may write updated cookies back to the file. Songies ignores that;
  the stored session is not changed by playback.
- Failure messages from the signed-in run are scrubbed of cookie values, the
  way `InnertubeClient.call` already scrubs them.

## Runtime

### Desktop (Linux, Windows)

In order:
1. Deno already installed by Songies in its `bin` folder: pass
   `--js-runtimes deno:<path>`.
2. `deno` or `node` on `PATH`: pass `--js-runtimes deno` or
   `--js-runtimes node`.
3. Neither: ask the user first (see below).

**The prompt** (desktop only): "This song is age-restricted. To play it,
Songies needs to download a small helper (about 45 MB, once)." Buttons:
Download, Not now.
- **Download:** shows progress, then the song plays. Never asked again.
- **Not now:** the song is skipped with the age-restricted note. Asked again
  next time.

**Installing Deno** works like `YtDlpInstaller`: download the release zip for
the platform from Deno's GitHub releases (`deno-x86_64-unknown-linux-gnu.zip`,
`deno-x86_64-pc-windows-msvc.zip`), check it against the `.sha256sum` file
published next to it, unpack it into the `bin` folder, `chmod +x` on Linux,
and check that `deno --version` runs. If anything fails, nothing is left
behind and the user sees an error they can retry.

**Settings** gets a line in the YouTube section, next to yt-dlp: whether the
helper is installed (and which: Songies' Deno, or Node/Deno found on the
system), with a Remove button for Songies' own Deno.

### Android

No download and no prompt. youtubedl-android already supplies QuickJS. The
signed-in run only adds the cookies file.

**Unverified:** whether Android's yt-dlp includes the challenge-solver script.
The builder checks this on a device (run with `-v` and look for
`[jsc:quickjs]` and the solver script's source). If it's missing, Android's
signed-in run also passes `--remote-components ejs:github`.

## Constraints

- Flutter 3.47.8, the existing `Result`/`Failure` types, Riverpod providers.
- Tests follow the repo's habit: fake runners and fake downloads, no network.
- Nothing here changes how ordinary songs play or how long they take to start.

## Left to the builder

- The wording and look of the messages (snackbar, dialog or sheet), matching
  how the player already reports a song it can't play.
- Where the runtime choice and the Deno installer live in the code.
- How the signed-in retry plugs in: a third stream source after anonymous
  yt-dlp, or a step inside `YtDlpClient`. It must run only after an
  `ageRestricted` answer.
- How the Deno version is chosen and updated (pinned or latest).
