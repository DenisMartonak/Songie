# Crash Reporting (Sentry) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tagged release builds of Songies report crashes, Android freezes and unhandled errors to Sentry, anonymously, behind an on-by-default Settings switch.

**Architecture:** A small `lib/core/crash_reporting/` unit holds the build-time config, the scrubbing/filters (pure functions) and a `CrashReporter` that starts and stops Sentry from the device-local setting. `main.dart` reads the setting before starting Sentry; breadcrumbs come from our own router and player listeners (no ids, no titles). The release workflow passes the DSN only for tag pushes, splits debug info and uploads symbols with `sentry_dart_plugin`.

**Tech Stack:** Flutter, `sentry_flutter` (current stable), `sentry_dart_plugin` (dev), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-05-crash-reporting-design.md`

Flutter is at `~/development/flutter/bin` (not on PATH): run commands with
`export PATH=$HOME/development/flutter/bin:$PATH` first.

## Global Constraints

- DSN (public; written in the workflow, passed as `--dart-define=SENTRY_DSN=…`): `https://c4edb51cf9cf17f0bd516e1b2af6168c@o4512375882579968.ingest.de.sentry.io/4512376083841104`
- Org slug `denis-martonak`; project slug from the workflow variable `vars.SENTRY_PROJECT`; auth token from the secret `secrets.SENTRY_AUTH_TOKEN`. Neither slug nor token in Dart code.
- Reporting happens only when `kReleaseMode` **and** the DSN define is non-empty **and** the setting is on. The workflow passes the DSN only when `IS_RELEASE` (tag push) is true.
- Setting key `crash_reports`, device-local (not synced), default **on**. Settings label "Send crash reports", subtitle "Anonymous: no songs, names or files."
- Off: Sentry is not started at launch; switching off while running calls `Sentry.close()`; switching on starts it. Queued reports from an earlier session go out only when on.
- Reported: Dart unhandled errors (`FlutterError.onError`, `PlatformDispatcher.onError`), native crashes (Android NDK, Windows/Linux crashpad, minidumps included), Android ANR (default 5 s). Not reported: `AppLog.w` warnings.
- Per-install id: the SDK's own anonymous installation id only; never `lib/sync/device_identity.dart`'s id.
- `sendDefaultPii = false`; no user, IP, server name/hostname. Breadcrumbs: only categories `navigation` (route templates such as `/playlist/:id`), `player` (play, pause, next, previous, seek, track change — no titles or ids) and app lifecycle. Every other breadcrumb (HTTP, UI, native auto, console/log) is dropped.
- File paths in exception values, messages and breadcrumb text are replaced with `<path>`.
- Release name `songies@<version>` where `<version>` is `pubspec.yaml`'s `X.Y.Z+N`; the same string in the app (`--dart-define=SENTRY_RELEASE=…`) and in the symbol upload. Environment `production`.
- A release still builds and publishes when `SENTRY_AUTH_TOKEN` is missing (upload skipped with a `::warning::`).
- No first-launch notice. No performance tracing, session replay, screenshots or view hierarchy.

## Review Focus

1. No DSN / debug build: the app starts normally and never calls `SentryFlutter.init` — test in Task 2.
2. Setting off at launch → Sentry never started; toggled off → `close` called once; toggled on again → started again; rapid toggling does not start two instances — test in Task 2.
3. An exception whose message holds a home-folder path or a song file path reaches Sentry with `<path>` — test in Task 1.
4. A route with ids (`/playlist/abc123`) produces a breadcrumb with the template (`/playlist/:id`), never the id — test in Task 2.
5. The existing log-file error handlers keep working with Sentry installed (an uncaught error is still written to the log) — test in Task 2.

---

### Task 1: Config and scrubbing

**Files:**
- Modify: `pubspec.yaml` (add `sentry_flutter`)
- Create: `lib/core/crash_reporting/crash_config.dart`
- Create: `lib/core/crash_reporting/scrub.dart`
- Modify: `lib/data/settings_repository.dart` (add `kCrashReports = 'crash_reports'` with the house-style doc comment: device-local, on by default)
- Test: `test/core/crash_reporting/scrub_test.dart`, `test/core/crash_reporting/crash_config_test.dart`

**Interfaces:**
- Produces:
  - `const String kSentryDsn = String.fromEnvironment('SENTRY_DSN');`
  - `const String kSentryRelease = String.fromEnvironment('SENTRY_RELEASE');`
  - `bool crashReportingBuilt({bool releaseMode = kReleaseMode, String dsn = kSentryDsn})` — true only for release mode with a non-empty DSN.
  - `String scrubPaths(String text)` — replaces absolute paths (POSIX `/home/…`, `/storage/…`, `/data/…`, `/tmp/…`, `/media/…`, `/mnt/…`, `/run/media/…`, `file://…`; Windows `C:\…` / `C:/…` / `\\server\…`) up to the next whitespace or quote with `<path>`.
  - `SentryEvent? scrubEvent(SentryEvent event, Hint hint)` — `scrubPaths` over exception values, message, and every breadcrumb message/data string; removes `user`, `serverName`, and request data.
  - `Breadcrumb? filterBreadcrumb(Breadcrumb? crumb, Hint hint)` — keeps only categories `navigation`, `player`, `app.lifecycle` (and the SDK's lifecycle category name if different — check the package), returns others as null; scrubs kept ones.

- [ ] **Step 1: Write the failing tests**

```dart
test('scrubPaths hides POSIX, Android, Windows and file:// paths', ...);
  // '/home/denis/Music/Jazz/a.flac failed' -> '<path> failed'
  // "C:\\Users\\Denis\\Music\\a.mp3" -> '<path>'; 'file:///storage/emulated/0/x.m4a' -> '<path>'
  // 'no path here' unchanged
test('scrubEvent scrubs exception values and drops user and server name', ...);
test('filterBreadcrumb keeps navigation and player, drops http and ui.click', ...);
test('crashReportingBuilt needs release mode and a DSN', ...);
  // (false,'x') false; (true,'') false; (true,'x') true
```

- [ ] **Step 2: Run them to see them fail** — `flutter test test/core/crash_reporting/` → FAIL (missing files).
- [ ] **Step 3: Add the dependency (`flutter pub add sentry_flutter`) and implement the files above.**
- [ ] **Step 4: Run** `flutter test test/core/crash_reporting/` → PASS; `flutter analyze lib test` → no issues.
- [ ] **Step 5: Commit** `feat: crash report config and scrubbing`

### Task 2: Start, stop and breadcrumbs

**Files:**
- Create: `lib/core/crash_reporting/crash_reporter.dart`
- Create: `lib/core/crash_reporting/crash_breadcrumbs.dart`
- Modify: `lib/main.dart` (after `_installErrorLogging()` and the database/settings exist: create `CrashReporter`, `await reporter.applySetting(...)` with the stored value, then follow `settings.watchBool(kCrashReports, fallback: true)`; wire breadcrumbs to the router and `player.states`)
- Test: `test/core/crash_reporting/crash_reporter_test.dart`, `test/core/crash_reporting/crash_breadcrumbs_test.dart`

**Interfaces:**
- Consumes: Task 1 (`crashReportingBuilt`, `kSentryDsn`, `kSentryRelease`, `scrubEvent`, `filterBreadcrumb`, `kCrashReports`).
- Produces:
  - `class CrashReporter { CrashReporter({required bool built, required Future<void> Function() start, required Future<void> Function() close}); Future<void> applySetting(bool on); bool get running; void follow(Stream<bool> setting); Future<void> dispose(); }` — serialises start/close (never two starts in flight; a toggle during a pending start is applied after it). `start` in production is `SentryFlutter.init` with: dsn, release `kSentryRelease`, environment `production`, `sendDefaultPii: false`, `beforeSend: scrubEvent`, `beforeBreadcrumb: filterBreadcrumb`, `anrEnabled: true`, `enableNativeCrashHandling: true`, `attachScreenshot: false`, `attachViewHierarchy: false`, `tracesSampleRate: null`, `enableAutoNativeBreadcrumbs: false`, `enableUserInteractionBreadcrumbs: false`, app-lifecycle breadcrumbs on. `close` is `Sentry.close`. When `built` is false, nothing is ever started.
  - `String routeTemplate(String matchedFullPath)` — returns go_router's path template (`GoRouterState.fullPath`, e.g. `/playlist/:id`); never the concrete location.
  - `void recordRoute(String template)` and `void recordPlayer(PlayerState previous, PlayerState next)` adding `Breadcrumb(category: 'navigation' | 'player', message: …)`; player messages from a fixed set: `play`, `pause`, `next`, `previous`, `seek`, `track change`. Only when `Sentry.isEnabled`.

- [ ] **Step 1: Write the failing tests** (inject fake `start`/`close` that count calls)

```dart
test('not built: applySetting(true) never starts', ...);
test('setting on starts once; off closes; on again starts again', ...);
test('rapid on/off/on while a start is pending ends running with one start in flight at a time', ...);
test('off at launch never starts', ...);
test('routeTemplate gives /playlist/:id for /playlist/abc123', ...);
  // via a GoRouter in a widget test: navigate to /playlist/abc123, read the template the listener saw
test('recordPlayer emits play, pause and track change without titles', ...);
  // breadcrumb messages exactly in the fixed set; no Track.title in any crumb
test('an uncaught error is still written to the log with Sentry installed', ...);
  // install _installErrorLogging-equivalent + a fake Sentry-style wrapper on FlutterError.onError; report an error; AppLog file contains it
```

- [ ] **Step 2: Run** `flutter test test/core/crash_reporting/` → new tests FAIL.
- [ ] **Step 3: Implement** the two files and the `main.dart` wiring. `SentryFlutter.init` installs its own `FlutterError.onError`; it must chain to the log handler (install logging first, as now, and confirm the SDK calls the previous handler; if it doesn't, wrap explicitly). Do not wrap `runApp` in `SentryFlutter.init`'s `appRunner`: start Sentry before `runApp` and let `CrashReporter` restart it on toggles.
- [ ] **Step 4: Run** `flutter test test/core/crash_reporting/` and the full `flutter test` → PASS (the stats "… listens answer in under 500 ms" timing tests can flake under full-suite load; re-run alone if they're the only failures); `flutter analyze lib test` clean. Also run the app once in debug (`flutter run -d linux` for a few seconds, or `flutter build linux --debug`) to confirm it starts with no DSN.
- [ ] **Step 5: Commit** `feat: Sentry starts and stops with the crash report setting`

### Task 3: The Settings switch

**Files:**
- Create: `lib/ui/settings/crash_reports_settings.dart` (`CrashReportsSettingsSection`, same shape as `lib/ui/settings/discord_settings.dart`)
- Modify: `lib/ui/settings/settings_page.dart:98` (insert the section just before `_LogsSection`)
- Test: `test/ui/settings/crash_reports_settings_test.dart`

**Interfaces:**
- Consumes: `kCrashReports` (Task 1); `SettingsRepository.watchBool/setBool`.

- [ ] **Step 1: Write the failing tests**

```dart
uiTest('the crash report switch is on by default', ...);
  // find.text('Send crash reports'); find.text('Anonymous: no songs, names or files.'); switch value true
uiTest('turning it off stores false and survives a rebuild', ...);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**: a section titled "Crash reports" (`SettingsSectionTitle`), one `SwitchListTile` keyed `settings.crashReports`. Shown on every platform and build (the setting is harmless where reporting isn't built).
- [ ] **Step 4: Run** `flutter test test/ui/settings/ test/ui/settings_test.dart` → PASS; analyze clean.
- [ ] **Step 5: Commit** `feat: a Send crash reports switch in Settings`

### Task 4: Release workflow, symbols and docs

**Files:**
- Modify: `.github/workflows/release.yml` (Android, Linux and Windows build steps; a symbol-upload step per platform job)
- Modify: `pubspec.yaml` (dev dependency `sentry_dart_plugin`; a `sentry:` config block with `org: denis-martonak`, `upload_debug_symbols: true`, `upload_source_maps: false`; project, release and auth token come from env vars `SENTRY_PROJECT`, `SENTRY_RELEASE`, `SENTRY_AUTH_TOKEN`; set the plugin's URL/region if the EU region needs it — check the plugin docs)
- Modify: `docs/releasing.md` (new section "Sentry crash reports (once)")
- Possibly modify: `tool/build_appimage.sh`, `windows/installer/*.iss` (whatever the Windows Inno Setup script is) — only if the native crash handler (`crashpad_handler`) is not already inside the Flutter release bundle they copy.

**Interfaces:**
- Consumes: the define names `SENTRY_DSN`, `SENTRY_RELEASE` (Task 1).

**Workflow behaviour:**
- A step computes `SENTRY_RELEASE=songies@<X.Y.Z+N>` from `pubspec.yaml` once and exposes it to the build jobs.
- Every platform build adds `--split-debug-info=build/symbols/<platform>`; when `env.IS_RELEASE == 'true'` it also adds `--dart-define=SENTRY_DSN=<DSN> --dart-define=SENTRY_RELEASE=$SENTRY_RELEASE`. Manual runs build without the DSN.
- After each build, when `IS_RELEASE` and `secrets.SENTRY_AUTH_TOKEN != ''`: `dart run sentry_dart_plugin` (with the env vars). When the token is empty: `echo "::warning::SENTRY_AUTH_TOKEN not set; symbols not uploaded"`. The step never fails the release.
- Linux job: install whatever the native SDK needs to build on ubuntu-22.04 (e.g. `libcurl4-openssl-dev`) if the build asks for it.

**Docs section must cover, in the file's plain style:** creating an auth token in Sentry (Settings → Auth Tokens / Organization tokens, with the scopes the plugin needs), adding GitHub secret `SENTRY_AUTH_TOKEN` and variable `SENTRY_PROJECT` (the project slug from the Sentry URL), leaving "Store Native Crash Reports" off in the Sentry project, and that tag releases report while manual runs don't.

- [ ] **Step 1: Check the native handler** — `flutter build linux --release --split-debug-info=build/symbols/linux` locally; list `build/linux/x64/release/bundle/` and note whether `crashpad_handler` is there. If not, find where the SDK puts it and change `tool/build_appimage.sh` to include it. Do the same reasoning for Windows from the package docs (can't build Windows here); change the installer script if it copies a file list rather than the whole release folder.
- [ ] **Step 2: Edit the workflow, pubspec config and docs** as above.
- [ ] **Step 3: Validate** — `actionlint .github/workflows/release.yml` if available (else `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/release.yml`); `flutter pub get`; `dart run sentry_dart_plugin --help` (or its dry-run) runs; `flutter analyze lib test`; the Linux release build from Step 1 still produces the bundle, and `tool/build_appimage.sh <X.Y.Z>` still builds if `appimagetool` is available (say so if not).
- [ ] **Step 4: Commit** `build: release builds report crashes to Sentry and upload symbols`
