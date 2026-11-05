# Report a bug — design

Roadmap item 4 (`docs/ROADMAP.md`). Agreed with the user on 2026-11-05.

## Why

A few friends use Songies. When something goes wrong that isn't a crash
(wrong song plays, a playlist looks odd, something is slow), crash
reporting (item 3) never sees it. The user wants friends to be able to
send a bug report from inside the app, landing in the user's Discord
channel through a webhook, with enough detail to understand and fix it.

## Platforms

Android, Windows and Linux (the platforms `release.yml` builds). The form
is a dialog on wide layouts and a full-screen page on phones (the app's
`phoneBreakpoint`, `lib/ui/shell/adaptive_shell.dart`).

## What a report contains

One Discord message per report:

- **Description** — typed by the reporter. Required (at least a few
  characters; *Claude's call:* 10).
- **Name** — optional "Your name" field. Remembered on this device for the
  next report (device-local setting, not synced). *(Remembering is
  Claude's call.)*
- **Basics** — app version and build (`pubspec.yaml`, e.g. `1.1.4+8`), OS
  and OS version, device model, platform, time (UTC). Device model means:
  manufacturer + model on Android; on desktop, what's cheaply available
  (e.g. the Windows/Linux edition), never the computer's host name or the
  user name. Also the crash-reporting install id
  (`crash_install_id`, from item 3) when one exists, so a bug report can
  be matched to crash reports in Sentry; it is random and anonymous.
  *(Claude's call.)*
- **The app's log** — the same file "Export log" saves today
  (`lib/core/log.dart`, `AppLog`), attached as a text file, capped at
  2 MB (the newest part if longer). File paths in it are hidden with the
  crash-reporting scrubber (`scrubPaths` in
  `lib/core/crash_reporting/scrub.dart`). Song titles may still appear;
  the form says "Includes the app's log." *(Scrubbing is Claude's call.)*
- **Screenshot** — optional. The reporter takes it themselves with the
  device's normal screenshot keys and **attaches** it with an "Attach
  screenshot" button (the existing `file_picker` package: images only —
  png, jpg/jpeg, webp). One image, shown as a thumbnail with a remove
  button. *(Decided by the user: attach, not capture.)*
- **Size:** Discord takes about 10 MB per webhook message in total
  (builder confirms the current limit). The log is plain text, at most
  2 MB, trimmed to its newest part first if the total would not fit; an
  image over 7 MB is refused when attached ("That image is too big") so
  the reporter can pick a smaller one. *(Claude's call.)*

The Discord message itself: the description as the main text (or an
embed), name, version, OS and device as fields, the log and screenshot as
attachments. Mentions are disabled (`allowed_mentions: {parse: []}`) so a
report can't ping anyone. *(Claude's call.)*

## Where it starts

- **Only in Settings**, as a "Report a bug" button directly above "Check
  for updates" (in About). *(Decided by the user.)*
- No shake-to-report.

The one-line notice ("Includes the app version, your device and the app's
log.") is the consent; there's no preview step. *(Claude's call.)*

It opens a form (a dialog on desktop, a full-screen page or sheet on
phones) with: description, your name, attach screenshot, a line saying
what else is included (version, device, the app's log), Cancel and Send.

## Sending

- Send posts to the webhook as `multipart/form-data` (`payload_json` +
  files).
- Success: the form closes and the island says "Bug report sent".
- Failure (no internet, Discord error, Discord rate limit): the form
  stays open with everything filled in and shows "Couldn't send. Check
  your connection and try again."; Send works again right away. Nothing
  typed is lost while the form is open. *(Claude's call: no offline
  queue; closing the form discards it; no Retry on the island, the form's
  Send is the retry.)*
- At most one **successful** report per minute from a device (kept in
  memory; a restart resets it); a second Send within that minute is
  refused with "You just sent one. Try again in a minute." Failed
  attempts don't count. *(Claude's call.)*
- While sending, Send shows progress and can't be pressed twice.

## The webhook

- The webhook URL is a secret: **never in the repo** (the repo is
  public). It reaches the build as a build-time define (e.g.
  `--dart-define=BUG_REPORT_WEBHOOK=…`), from a GitHub Actions secret
  (e.g. `SONGIES_BUG_WEBHOOK`) in `.github/workflows/release.yml`, for
  every workflow build (tag and manual runs — reports are deliberate, so
  no quota concern). *(Claude's call.)*
- The check is compile-time (`String.fromEnvironment`). Builds without the
  define (debug, local, a fork's CI without the secret) hide **Report a
  bug**. *(Claude's call.)* A developer can pass the define locally to
  test. The define goes on the build commands only.
- Known limit, accepted for now: someone who digs into the app file can
  extract the URL and post to the channel. When Supabase arrives
  (roadmap item 5), reports move behind a Supabase Edge Function and the
  webhook leaves the app. If it is ever abused, the user deletes the
  webhook in Discord and makes a new one (docs say how).

## Docs

`docs/releasing.md`: one-time setup — create the webhook in Discord
(channel settings → Integrations → Webhooks), add it as GitHub secret
`SONGIES_BUG_WEBHOOK`, and what to do if it leaks (delete it in Discord,
make a new one, update the secret).

## Goals

- A friend can send a useful report in under a minute, from anywhere in
  the app, and the user sees it in Discord with version, device, log and
  optional screenshot.
- Nothing typed is lost on a failed send.

## Non-goals

- Replies or a conversation thread back to the reporter.
- Automatic screenshots or screen recordings.
- An offline queue.
- Sending through Supabase (item 5).

## Anti-goals

- The webhook URL in the repo.
- A report that pings people or can be used to spam the channel from a
  stuck button.
- Sending anything without the reporter pressing Send.

## Left to the builder

- HTTP client (the app already uses `http`/`dart:io` elsewhere), the exact
  Discord message layout, form layout per platform, the menu placement,
  how device info is read (existing helpers or a package).
