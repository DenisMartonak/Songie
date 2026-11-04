# Crash reporting (Sentry) — design

Roadmap item 3 (`docs/ROADMAP.md`). Agreed with the user on 2026-11-05.

## Why

Songies now has users besides its author (a few friends), on Android,
Windows and Linux. When the app crashes, freezes or hits an unexpected
error on one of their devices, the author has no way to find out or to
see why. Crash reporting sends those problems to Sentry so they can be
fixed, per device and OS.

## What gets reported

- **Crashes** — the app closing on its own, on Android, Windows and Linux:
  Dart errors and native crashes (including native libraries such as mpv
  on desktop).
- **Freezes** — on Android, "app not responding" (ANR: the UI blocked for
  about 5 s). On desktop a frozen window is not reliably detectable;
  desktop freezes show up only if they end in a crash. *(Claude's call.)*
- **Unhandled errors** — errors that escape the app's code without
  crashing it: everything that today reaches `FlutterError.onError` and
  `PlatformDispatcher.instance.onError` (`_installErrorLogging` in
  `lib/main.dart`).
- **Not** reported: problems the app already handles and logs as warnings
  (`AppLog.w`, "Couldn't add that song" islands …). They are expected and
  would use up the free plan's 5,000 errors/month. *(Claude's call.)*

## What a report carries

- App version and build number (from `pubspec.yaml`, e.g. `1.1.4+8`) as the
  Sentry release, so a crash can be seen to stop after a fix; OS, OS
  version, device model; the stack trace with real function names.
- **Breadcrumbs:** the last steps before the problem — screen changes (route
  names such as `/playlist/:id`, never the ids/values), player actions
  (play, pause, skip, seek) and app lifecycle. *(Claude's call on the exact
  list.)*
- A random per-install ID so Sentry can count how many devices a problem
  hits: Sentry's own installation id, or a new random id kept only in this
  device's settings. Never the sync device identity
  (`lib/sync/device_identity.dart`), which could link devices together.
  *(Claude's call.)*
- **Nothing personal:** no song titles, artist names, playlist names, file
  paths, URLs with ids, YouTube/account data, IP address or user name.
  Error messages that may embed such values (e.g. a path in an exception
  string) are scrubbed before sending, best effort: file paths under the
  user's home/app folders are replaced with a placeholder. *(Claude's call.)*

## The switch

- Settings gets **Send crash reports**, **on by default**, with one line:
  "Anonymous: no songs, names or files." (wording may be tightened).
- Turning it off stops reporting at once (no restart needed) and is
  remembered across restarts (stored like the other settings in
  `lib/data/settings_repository.dart`). Turning it back on resumes.
- "Off" must cover native crashes too, which a Dart-side filter cannot
  stop: the setting is read at startup **before** Sentry starts; when off,
  Sentry is not started at all; when switched off while running, Sentry is
  shut down (`Sentry.close()`), and switching it on starts it again. Crash
  reports queued on disk from an earlier session are sent only if the
  setting is on. *(Claude's call.)*
- **No first-launch notice** (the user decided).
- The setting is device-local; it is not synced between devices.
  *(Claude's call.)*

## Which builds report

- Only release builds made by the GitHub release workflow
  (`.github/workflows/release.yml`) for a **tag push** report. Debug runs,
  local builds and manual (`workflow_dispatch`) runs never send anything:
  the workflow passes the DSN only when `IS_RELEASE` is true, and the app
  also requires `kReleaseMode`. *(Claude's call.)*
- The Sentry DSN reaches the build as a build-time define (like
  `kDiscordClientId` in `lib/discord/discord_presence.dart`). The DSN is
  public by design, so it is written directly in
  `.github/workflows/release.yml` (no secret to set up) *(Claude's call)*:
  `https://c4edb51cf9cf17f0bd516e1b2af6168c@o4512375882579968.ingest.de.sentry.io/4512376083841104`
  (EU region, `de.sentry.io`). With no DSN, Sentry is not started at all.
- Builds are tagged with an environment (`production`).

## Native crash snapshots

**The user decided: send them.** Native crashes on Windows and Linux
(crashpad) and Android (NDK) upload their minidump, which Sentry uses to
work out the stack trace. A minidump holds a snapshot of the app's memory
and may contain e.g. a song title or path; that is accepted. The Sentry
project keeps the default of not storing minidumps after processing
("Store Native Crash Reports" off) — `docs/releasing.md` says to leave it
off.

## Debug symbols

- Release builds upload their debug symbols to Sentry so stack traces are
  readable, for every platform built (Android APK, Linux AppImage, Windows
  installer). The workflow's build commands may change for this (e.g.
  adding `--split-debug-info`; `--obfuscate` is not needed). *(Claude's
  call.)*
- Native crash capture on Windows and Linux needs Sentry's native crash
  handler shipped with the app; the AppImage script (`tool/`) and the
  Windows installer script may change to bundle it. If native capture on
  one desktop platform proves impractical on the CI runners, that platform
  falls back to Dart errors only, and the builder says so in its report;
  it is not silently dropped. *(Claude's call.)* Org slug: **`denis-martonak`**; project
  slug: as created by the user (to confirm; project id 4512376083841104,
  EU region); both are workflow variables,
  not hard-coded in Dart.
- The upload uses a Sentry auth token kept only in a GitHub Actions secret
  (e.g. `SENTRY_AUTH_TOKEN`); it never appears in the repo or in chat.
- If the token is missing, the release still builds (the upload step is
  skipped, with a warning).

## Docs

`docs/releasing.md` gets a short plain-language section for the one-time
setup: where to find the DSN and create the auth token in Sentry, and
which GitHub secrets to add.

## Goals

- Crashes, Android freezes and unhandled errors from friends' devices show
  up in Sentry with readable stack traces, version, OS and device.
- Off means off, immediately.

## Non-goals

- Performance monitoring / tracing, session replay, user feedback forms
  (the "Report a bug" form is roadmap item 4).
- Reporting handled warnings.
- iOS/macOS.

## Anti-goals

- Any personal data in a report.
- Debug/development runs eating the monthly quota.
- A crash reporter that itself slows startup noticeably or breaks the app
  when Sentry is unreachable or no DSN is set.

## Left to the builder

- Package version (`sentry_flutter`, current stable) and its options;
  how the setting gates sending (e.g. `beforeSend` returning null when off).
- The exact breadcrumb sources and the scrubbing rules within the limits
  above.
- How native/desktop crash capture and symbol upload are wired per
  platform in the workflow (e.g. `sentry_dart_plugin`, `--split-debug-info`
  / `--obfuscate` only if needed).

## Needed from the user before release

- A Sentry auth token added as a GitHub secret (instructions in
  `docs/releasing.md`).
- The project slug, if not obvious from Sentry.
