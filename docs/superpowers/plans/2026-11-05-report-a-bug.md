# Report a Bug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Friends can send a bug report (description, optional name, optional screenshot, version, device, scrubbed log) from Songies to the user's Discord channel.

**Architecture:** A pure `lib/bug_report/` unit builds the report (device info, log, size limits) and posts it to a Discord webhook through an injectable `http.Client`; a form (dialog on wide layouts, page on phones) collects the input; entry points in Settings and the desktop sidebar appear only when the webhook define is built in. The release workflow passes the webhook from a GitHub secret.

**Tech Stack:** Flutter, `http` (MultipartRequest; `package:http/testing` MockClient in tests), existing `file_picker`, existing islands, existing `scrubPaths`.

**Spec:** `docs/superpowers/specs/2026-11-05-report-a-bug-design.md`

Flutter is at `~/development/flutter/bin` (not on PATH): run commands with
`export PATH=$HOME/development/flutter/bin:$PATH` first.

## Global Constraints

- Webhook define name `BUG_REPORT_WEBHOOK` (`String.fromEnvironment`); from GitHub secret `SONGIES_BUG_WEBHOOK` (already set). The URL never appears in the repo, in logs, or in error messages.
- Builds without the define hide every Report a bug entry point.
- Description required, at least 10 characters (trimmed). Name optional, remembered device-locally under settings key `bug_report_name`.
- Included: app version and build (`1.1.3+7` style), platform, OS + OS version, device model (Android: manufacturer + model; desktop: no host name, no user name), UTC time, the crash-reporting install id (settings key `crash_install_id`) only if it already exists — never create one.
- Log: rotated + current log (as Export log reads them), `scrubPaths` applied per line, plain text, at most 2 MB (keep the newest part), sent as `songies-log.txt`.
- Screenshot: optional, one image, png/jpg/jpeg/webp via `file_picker`; over 7 MB refused at attach time with "That image is too big". Whole message must fit 10 MB: trim the log first.
- Discord: `multipart/form-data` with `payload_json` + `files[0]`/`files[1]`; `allowed_mentions: {"parse": []}`; content/embed text within Discord's limits (embed description ≤ 4096 chars, field values ≤ 1024; truncate with "…").
- Form copy: title "Report a bug"; fields "What happened?" and "Your name (optional)"; button "Attach screenshot"; notice "Includes the app version, your device and the app's log."; buttons "Cancel" and "Send".
- Success: form closes; island "Bug report sent" (success). Failure: form stays open, inline "Couldn't send. Check your connection and try again."; Send usable again. Rate limit: one successful report per minute per app run; refusal text "You just sent one. Try again in a minute."
- While sending, Send shows progress and is disabled.
- Form is a dialog at width ≥ `phoneBreakpoint` (720), a full-screen page below.

## Review Focus

1. Webhook missing or empty → no entry point anywhere, and `BugReportSender` refuses to send — test in Task 1 and Task 2.
2. A Discord 429/5xx or a socket error → `BugReportSendResult.failed`, nothing thrown, rate limit not consumed — test in Task 1.
3. Log larger than 2 MB, or log + 7 MB image over 10 MB → log trimmed to its newest part, total under 10 MB — test in Task 1.
4. A description of 6,000 characters or a name of 300 → message still accepted by Discord's limits (truncated) — test in Task 1.
5. The webhook URL never appears in an exception message, `AppLog` line or island — test in Task 1.

---

### Task 1: Report building and sending

**Files:**
- Modify: `pubspec.yaml` (add `http` as a direct dependency if not already)
- Modify: `lib/core/app_version.dart` (add `const String appBuild = '7';` kept in sync with pubspec's `+N`; extend the existing sync test)
- Modify: `lib/data/settings_repository.dart` (add `kBugReportName = 'bug_report_name'`, device-local)
- Create: `lib/bug_report/bug_report.dart`
- Create: `lib/bug_report/bug_report_sender.dart`
- Test: `test/bug_report/bug_report_test.dart`, `test/bug_report/bug_report_sender_test.dart`

**Interfaces:**
- Produces:
  - `const String kBugReportWebhook = String.fromEnvironment('BUG_REPORT_WEBHOOK');` and `bool bugReportsBuilt({String webhook = kBugReportWebhook})`.
  - `class DeviceSummary { final String platform, os, model; }` and `Future<DeviceSummary> readDeviceSummary()` (Android model from the existing platform info or a small method channel/`device_info_plus` — builder's choice; desktop: `Platform.operatingSystem` + `Platform.operatingSystemVersion`, model `'desktop'` or the OS edition; never `Platform.localHostname`).
  - `class BugReport { final String description; final String? name; final DeviceSummary device; final String version; final DateTime time; final String? installId; final Uint8List log; final ({String fileName, Uint8List bytes})? screenshot; }`
  - `Uint8List collectLog(Directory logsDir, {int maxBytes = 2 * 1024 * 1024})` — rotated then current, `scrubPaths` per line, newest part kept.
  - `Map<String, Object?> discordPayload(BugReport r)` — `content` null or short, one embed (title "Bug report", description = description truncated to 4096, fields Name/Version/Device/Install id, timestamp ISO-8601), `allowed_mentions: {'parse': []}`, `attachments` metadata for the files.
  - `enum BugReportSendResult { sent, failed, tooSoon, notBuilt }`
  - `class BugReportSender { BugReportSender({required http.Client client, String webhook = kBugReportWebhook, DateTime Function() now = DateTime.now}); Future<BugReportSendResult> send(BugReport r); }` — refuses (`notBuilt`) for an empty webhook; `tooSoon` within 60 s of the last `sent`; trims the log so the multipart body stays under 10 MB; on any HTTP status other than 2xx, or any exception, logs `AppLog.w('Bug report failed: <status or exception type>')` without the URL and returns `failed`.
  - `const int maxScreenshotBytes = 7 * 1024 * 1024;`

- [ ] **Step 1: Write the failing tests** (MockClient captures the request)

```dart
test('bugReportsBuilt is false for an empty webhook', ...);
test('collectLog joins rotated + current, scrubs paths and keeps the newest 2 MB', ...);
test('discordPayload has the description, fields, no mentions, and truncates long text', ...);
  // description 6000 chars -> embed description length <= 4096 ending '…'; name 300 chars -> field <= 1024
test('send posts multipart with payload_json, the log file and the screenshot', ...);
  // request.url == webhook; content-type multipart/form-data; files[0] filename songies-log.txt; files[1] the image name
test('send trims the log so log + 7 MB image stays under 10 MB', ...);
test('send returns failed on 429, 500 and a socket error, without throwing, and does not start the cooldown', ...);
test('a second send within 60 s of a success is tooSoon; after 60 s it sends', ...);
test('the webhook URL appears in no log line or exception text', ...);
  // capture AppLog output during a failing send; expect no 'discord.com/api/webhooks'
test('appVersion and appBuild match pubspec.yaml', ...); // extend the existing test
```

- [ ] **Step 2: Run** `flutter test test/bug_report/` → FAIL (missing files).
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Run** `flutter test test/bug_report/` and the app-version test → PASS; `flutter analyze lib test` clean.
- [ ] **Step 5: Commit** `feat: build and send bug reports to Discord`

### Task 2: The form and where it opens

**Files:**
- Create: `lib/ui/bug_report/bug_report_form.dart` (`showBugReportForm(BuildContext, WidgetRef)`; dialog ≥ 720 px, full-screen page below)
- Modify: `lib/providers.dart` (or wherever app providers live): `bugReportSenderProvider` (real `http.Client`), `screenshotPickerProvider` (wraps `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['png','jpg','jpeg','webp'], withData: true)`; replaceable in tests), `deviceSummaryProvider`.
- Modify: `lib/ui/settings/settings_page.dart` (a "Help" section with a "Report a bug" `ListTile`, key `settings.reportBug`, above Logs; only when `bugReportsBuilt()`)
- Modify: `lib/ui/shell/sidebar.dart` (a "Report a bug" nav item, key `sidebar.reportBug`, icon `Icons.bug_report_outlined`, just above Settings; only when `bugReportsBuilt()`; collapsed shows the icon with a tooltip)
- Test: `test/ui/bug_report/bug_report_form_test.dart`

**Interfaces:**
- Consumes: Task 1 (`bugReportsBuilt`, `BugReport`, `BugReportSender.send`, `BugReportSendResult`, `collectLog`, `readDeviceSummary`, `maxScreenshotBytes`, `kBugReportName`, `appVersion`/`appBuild`).
- For tests, `bugReportsBuilt` must be overridable: expose `bugReportsBuiltProvider = Provider<bool>((_) => bugReportsBuilt())` and read that in the UI.

- [ ] **Step 1: Write the failing tests**

```dart
uiTest('no Report a bug entry when the webhook is not built in', ...);
uiTest('Settings and the desktop sidebar open the form', ...);
uiTest('Send is disabled until the description has 10 characters', ...);
uiTest('the name is prefilled from the last report', ...);
uiTest('attaching a screenshot shows a thumbnail that can be removed; a 8 MB image is refused', ...);
uiTest('a successful send closes the form and shows the Bug report sent island', ...);
uiTest('a failed send keeps the form filled and shows the inline error; Send works again', ...);
uiTest('a second report within a minute shows the too-soon message', ...);
uiTest('phone width opens a full page, desktop width a dialog', ...);
```

- [ ] **Step 2: Run** `flutter test test/ui/bug_report/` → FAIL.
- [ ] **Step 3: Implement** the form and entry points with the exact copy from Global Constraints; save the name on a successful send.
- [ ] **Step 4: Run** `flutter test test/ui/` (form, settings, sidebar, shell tests) and the full `flutter test` (stats "… under 500 ms" timing tests can flake under load) → PASS; analyze clean.
- [ ] **Step 5: Commit** `feat: a Report a bug form in Settings and the sidebar`

### Task 3: Release workflow and docs

**Files:**
- Modify: `.github/workflows/release.yml` — each platform build step reads the secret into a step env var (`SONGIES_BUG_WEBHOOK: ${{ secrets.SONGIES_BUG_WEBHOOK }}`) and adds `--dart-define=BUG_REPORT_WEBHOOK=$SONGIES_BUG_WEBHOOK` when it's non-empty, for tag **and** manual runs (unlike the Sentry DSN). Never echo it.
- Modify: `docs/releasing.md` — a short "Bug reports (once)" section: the webhook lives in Discord (channel → Edit channel → Integrations → Webhooks), is stored as GitHub secret `SONGIES_BUG_WEBHOOK` (already set), and if it leaks or gets spammed: delete it in Discord, make a new one, update the secret, make a new release.
- Modify: `docs/manual-test-checklist.md` — a release build shows Report a bug; a report arrives in Discord with version, device, log and screenshot; no @mentions fire; a local debug build hides it.

- [ ] **Step 1: Edit** the workflow and docs as above.
- [ ] **Step 2: Validate** — `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/release.yml`; read each changed build step; `grep -rn "discord.com/api/webhooks" .` finds nothing in tracked files (`git grep`).
- [ ] **Step 3: Commit** `build: release builds can send bug reports`
