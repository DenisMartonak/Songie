# Age-restricted songs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Signed-in users can play and download age-restricted YouTube songs; everyone else is told why a song can't play, and no age-restricted song is ever flagged unavailable.

**Architecture:** Age errors get their own `YtErrorKind`s instead of folding into `notFound`. A new `AgeRestrictedStreamSource` wraps the existing `FallbackStreamSource`: when the anonymous route ends in `ageRestricted` and the user is signed in, it runs yt-dlp once more with the session's cookies (a short-lived Netscape cookies file) and a JS runtime. Desktop finds a runtime (Songies' Deno, or `deno`/`node` on PATH) and can install Deno after asking; Android relies on youtubedl-android's bundled QuickJS.

**Tech Stack:** Flutter 3.47.8 / Dart, Riverpod, drift, yt-dlp (desktop binary, youtubedl-android 0.18.1), Deno 2 release zips, `package:archive` (new) for unzipping.

**Spec:** `docs/superpowers/specs/2026-11-01-age-restricted-playback-design.md`

## Global Constraints

- Ordinary songs take exactly today's path: Innertube, then anonymous yt-dlp. The login is sent only after an `ageRestricted` answer.
- No cookie value or SAPISIDHASH in any log line, `Failure.message`, or file that outlives the yt-dlp run.
- Cookies file: Netscape format, in Songies' private data folder, mode 0600 (Linux), unique name per run, deleted in a `finally`.
- Cookie lines: domain `.youtube.com`, include-subdomains `TRUE`, path `/`, secure `TRUE`, expiry now + 365 days (unix seconds).
- Desktop prompt copy: "This song is age-restricted. To play it, Songies needs to download a small helper (about 45 MB, once)." Buttons: Download, Not now.
- Signed-out copy: "Age-restricted — sign in to YouTube to play it". Signed-in refusal copy: "This YouTube account isn't valid for age-restricted songs". Both snack bars carry a "Sign in" action opening Settings.
- Missing runtime copy (unprompted paths): "Age-restricted — install the helper in Settings to play it".
- The prompt appears only for a song the user picked (`PlayerService._automatic == false`), never for queue advance, prefetch or downloads.
- Tests use fake runners, fake downloads and fake process runners; no network.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`. The two stats timing tests (`stats_repository_test.dart` "under 500 ms") are known to fail under full-suite load only; they are not regressions.

## Review Focus

- A session cookie that fails `YtSession.validName`/`validValue`: no file is written and the result is `ageRestrictedAccount` (the user signs in again), not a crash. → Task 2.
- A signed-in run that times out, is cancelled, or throws: the cookies file is still deleted. → Task 2.
- Prefetch and the playing song resolving two age-restricted videos at once: two different cookies files, neither deleted under the other. → Task 2.
- The session expires (`YtExpired`) between plays: `ensureSession()` gives null, so the result is the signed-out `ageRestricted`, never `ageRestrictedAccount`. → Task 4.
- Deno download cut off or checksum mismatch: no `deno` binary left in `bin`, the next age-restricted pick prompts again. → Task 5.
- Two picks while the prompt is open: one dialog; the second waits on the same answer. → Task 6.

---

### Task 1: Age errors are their own kinds

**Files:**
- Modify: `lib/youtube/yt_models.dart` (enum `YtErrorKind`, `ytErrorUserMessageFromText`)
- Modify: `lib/youtube/ytdlp_client.dart` (`classifyYtDlpStderr`)
- Modify: `lib/innertube/player_stream_source.dart` (`_isVideoLevel`, `_Outcome`, `_resolve`)
- Modify: `lib/downloads/download_service.dart:595` (`_failure`)
- Test: `test/youtube/ytdlp_client_test.dart`, `test/innertube/player_stream_source_test.dart`, `test/player/player_service_test.dart`, `test/downloads/download_service_test.dart` (extend the existing files; check names with `ls test/*/`)

**Interfaces:**
- Produces: `YtErrorKind.ageRestricted` (anonymous refusal), `YtErrorKind.ageRestrictedAccount` (signed-in refusal), `YtErrorKind.needsRuntime` (signed in, no JS runtime). All three map to `FailureKind.unknown` in `ytFailure` (the `_` arm already does this) and are **not** in `PlayerService._haltsQueue`.

- [ ] **Step 1: Write the failing tests**
  - `classifyYtDlpStderr('ERROR: [youtube] x: Sign in to confirm your age. ...')` → `ageRestricted`; same for `'ERROR: [youtube] x: Sorry, this content is age-restricted. ...'`; `'ERROR: ... Private video'` stays `notFound`; `'... available in your country'` stays `notFound`.
  - Innertube: both fake clients answer `LOGIN_REQUIRED` "Sign in to confirm your age" → `ytErrorKindOf(failure) == YtErrorKind.ageRestricted`. One age + one `UNPLAYABLE` → still `ageRestricted` (any age answer wins over `notFound`).
  - PlayerService: a yt track whose resolver returns `ytFailure(YtErrorKind.ageRestricted, ...)` → `onUnavailable` is never called, the notice reason starts with `ytdlp:ageRestricted:`, and the queue moves on.
  - DownloadService: a job failing with `ageRestricted` → `onUnavailable` not called, files removed as for other permanent failures, job marked failed (not requeued).
  - `ytErrorUserMessageFromText` returns the three Global Constraints strings for `ageRestricted`, `ageRestrictedAccount`, `needsRuntime`.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/youtube test/innertube test/player/player_service_test.dart test/downloads`
Expected: FAIL (`ageRestricted` undefined).

- [ ] **Step 3: Implement**
  - Add the three enum values (doc comment on each).
  - In `classifyYtDlpStderr`, move `'Sign in to confirm your age'` and `'age-restricted'` out of the `notFound` list into a check that runs **before** it and returns `ageRestricted`.
  - In `InnertubeStreamSource`, add `_Outcome.ageRestricted(reason)`; `_isVideoLevel`'s age branch becomes this outcome. `_resolve` returns `ageRestricted` if any client gave it, else the existing logic.
  - `DownloadService._failure`: `ageRestricted`/`ageRestrictedAccount`/`needsRuntime` fail the job with the user message and do **not** call `_onUnavailable`.

- [ ] **Step 4: Run the tests to see them pass**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: age-restricted songs get their own error, never flagged unavailable"
```

### Task 2: yt-dlp runs with a session's cookies

**Files:**
- Create: `lib/youtube/ytdlp_cookies.dart`
- Modify: `lib/youtube/ytdlp_client.dart` (constructor, `resolveStream`, `download`, `_run`)
- Modify: `lib/main.dart:115` (`YtDlpClient(runner, cookiesDir: …)`)
- Test: `test/youtube/ytdlp_cookies_test.dart`, `test/youtube/ytdlp_client_test.dart`

**Interfaces:**
- Produces:
  - `String netscapeCookies(YtSession session, DateTime now)`: header line `# Netscape HTTP Cookie File`, then one tab-separated line per cookie: `.youtube.com\tTRUE\t/\tTRUE\t<now+365d unix s>\t<name>\t<value>`. Throws `FormatException('invalid session cookie')` (no names or values in it) if any cookie fails `YtSession.validName`/`validValue`.
  - `class YtDlpAuth { const YtDlpAuth(this.session, this.runtimeArgs); final YtSession session; final List<String> runtimeArgs; }`
  - `YtDlpClient(YtDlpRunner runner, {Directory? cookiesDir, DateTime Function()? now})`
  - `Future<Result<YtStream>> resolveStream(String videoId, {YtDlpAuth? auth})` and `download(..., {YtDlpAuth? auth})`. With `auth`, args gain `['--cookies', <file>, ...auth.runtimeArgs]` before the URL. An age error from an authed run is reported as `ageRestrictedAccount`; an invalid cookie is `ageRestrictedAccount` with detail `invalid session cookie`.

- [ ] **Step 1: Write the failing tests**
  - `netscapeCookies(YtSession({'SID': 'a', 'SAPISID': 'b'}), DateTime.utc(2026, 11, 1))` equals the header plus two lines with expiry `1825027200`.
  - A value containing `;` → `FormatException`, and `'$e'` contains neither the name nor the value.
  - `resolveStream('v', auth: YtDlpAuth(session, ['--js-runtimes', 'node']))` with a fake runner: the recorded args contain `--cookies <path>` and `--js-runtimes node`; while the fake runs, the file exists with the netscape text (and on Linux `stat -c %a` is `600`); after the call the file is gone.
  - The file is gone when the fake runner throws `TimeoutException`, and when it returns exit 1.
  - Two concurrent authed `resolveStream` calls get different `--cookies` paths.
  - An authed run whose stderr is `ERROR: ... Sign in to confirm your age` → `ageRestrictedAccount`; stderr echoing a cookie value → the failure message contains `<redacted>`, not the value.
  - Without `auth`, args are exactly today's.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/youtube`
Expected: FAIL (`ytdlp_cookies.dart` missing).

- [ ] **Step 3: Implement**
  - File name `cookies-<random hex>.txt` in `cookiesDir` (create the dir if missing). On Linux/macOS create it empty, `chmod 600` via `Process.run`, then write; on Windows/Android just write (per-user/private dirs).
  - Delete in a `finally` around the run (ignore delete errors, log a warning without the path's contents).
  - Scrub cookie values (length ≥ 4) from the failure message as `InnertubeClient.call` does.
  - `main.dart`: `cookiesDir: Directory(p.join(paths.root.path, 'tmp'))`; at startup delete leftover `cookies-*.txt` there (crash leftovers).

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/youtube`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: yt-dlp can run with the YouTube session's cookies"
```

### Task 3: Finding a JS runtime

**Files:**
- Create: `lib/youtube/js_runtime.dart`
- Test: `test/youtube/js_runtime_test.dart`

**Interfaces:**
- Produces:
  - `enum JsRuntimeKind { songiesDeno, systemDeno, systemNode, bundled }`
  - `class JsRuntime { const JsRuntime(this.kind, this.args); final JsRuntimeKind kind; final List<String> args; }`
  - `class JsRuntimeFinder { JsRuntimeFinder({required Directory binDir, required bool isAndroid, required bool isWindows, Map<String, String>? environment, bool Function(String path)? exists}); Future<JsRuntime?> find(); File get songiesDeno; }`
  - Android → `JsRuntime(bundled, [])` (Task 4's gate may add `--remote-components ejs:github`).
  - Desktop order: `songiesDeno` exists → `['--js-runtimes', 'deno:<path>']`; `deno` on PATH → `['--js-runtimes', 'deno']`; `node` on PATH → `['--js-runtimes', 'node']`; else `null`.

- [ ] **Step 1: Write the failing tests**
  One test per row of the order above, using a fake `exists` and `environment: {'PATH': '/a:/b'}` (Windows: `;` separator, `.exe` suffix, `Path` key casing); Android with nothing present → `bundled` with empty args.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/youtube/js_runtime_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** by scanning PATH entries for `deno`/`node` (`deno.exe`/`node.exe` on Windows); no subprocess.

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: find a JavaScript runtime for yt-dlp"
```

### Task 4: The signed-in retry, wired for playback and downloads

**Files:**
- Create: `lib/player/age_restricted_stream_source.dart`
- Modify: `lib/main.dart:124-136` (wrap `FallbackStreamSource`), download wiring in `main.dart`/`providers.dart:724`
- Modify: `lib/downloads/download_service.dart` (retry an age-restricted download with auth)
- Modify: `docs/yt-dlp-notes.md` (add the verified table from the spec and the cookies/runtime flags)
- Test: `test/player/age_restricted_stream_source_test.dart`, `test/downloads/download_service_test.dart`

**Interfaces:**
- Consumes: Task 1 kinds, `YtDlpClient.resolveStream/download({YtDlpAuth? auth})`, `JsRuntimeFinder.find()`.
- Produces:
  - `typedef SessionLoader = Future<YtSession?> Function();` (wired to `YtAuth.ensureSession`)
  - `class AgeRestrictedStreamSource implements StreamSource { AgeRestrictedStreamSource(StreamSource inner, YtDlpClient ytDlp, SessionLoader session, JsRuntimeFinder runtimes); }` with `name` `'<inner>+age'`.
  - Rule: inner `Ok` or non-`ageRestricted` `Err` → returned as is. `ageRestricted`: session null → same `ageRestricted`; runtime null → `needsRuntime`; else `ytDlp.resolveStream(id, auth: YtDlpAuth(session, runtime.args))`.
  - DownloadService takes the same `SessionLoader` and `JsRuntimeFinder`; an `ageRestricted` download retries once with auth under the same rule.

- [ ] **Step 1: Write the failing tests**
  - Inner Ok → no session load, no yt-dlp call.
  - Inner `notFound` / `network` → returned unchanged, no retry.
  - Inner `ageRestricted`, session null → `ageRestricted`.
  - Inner `ageRestricted`, session, runtime null → `needsRuntime`, yt-dlp not called.
  - Inner `ageRestricted`, session, runtime `node` → yt-dlp called once with `auth.runtimeArgs == ['--js-runtimes', 'node']`; its Ok is returned.
  - Download: `ageRestricted` then authed Ok → job completes, `onUnavailable` not called.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/player/age_restricted_stream_source_test.dart test/downloads`. Expected: FAIL.

- [ ] **Step 3: Implement** and wire in `main.dart`: `AgeRestrictedStreamSource(FallbackStreamSource(...), ytClient, () => container.read(ytAuthProvider.notifier).ensureSession(), runtimes)`, using whatever handle `main.dart` already uses to reach `YtAuth` (follow how the Home feed gets its session at `providers.dart:538`).

- [ ] **Step 4: Run the full suite.** Run: `flutter analyze && flutter test`. Expected: no issues; all pass except the two known stats timing tests.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: age-restricted songs play when signed in"
```

- [ ] **Step 6: GATE — check with the user before Task 5**
  Ask the user to run `flutter run -d linux` (they have `node` on PATH), make sure they're signed in to YouTube in Settings, and play `S4-2QqwHf5c` ("HOMOŠLERKY (Full Song)").
  - Plays → continue.
  - Fails with `ageRestrictedAccount` → **stop**. Songies' youtube.com-only session (ruling R8) isn't enough; take this back to the user, do not change sign-in.
  Also ask for an Android check on a device, signed in via the in-app sign-in: play the same song. If it fails, run a debug build with `-v` added to the authed args and look for `[jsc:quickjs]` and the solver script source in the log; if the solver script is missing, make Android's `JsRuntime.args` `['--remote-components', 'ejs:github']`, add a Task 3 test for it, and commit `fix: Android fetches yt-dlp's challenge solver`.

### Task 5: Installing Deno on desktop

**Files:**
- Create: `lib/youtube/deno_installer.dart`
- Modify: `pubspec.yaml` (`flutter pub add archive`)
- Modify: `lib/youtube/ytdlp_installer.dart` (`httpDownload` gains `void Function(int received, int? total)? onProgress`)
- Test: `test/youtube/deno_installer_test.dart`

**Interfaces:**
- Produces: `class DenoInstaller { DenoInstaller(Directory binDir, {required Future<List<int>> Function(Uri, {void Function(int, int?)? onProgress}) download, required bool isWindows, ProcessRunFn? runProcess}); File get binary; Future<Result<String>> install({void Function(int received, int? total)? onProgress}); Future<void> remove(); }`
- Asset: `https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip` (Windows: `deno-x86_64-pc-windows-msvc.zip`), checksum from the same URL + `.sha256sum`.

- [ ] **Step 1: Write the failing tests**
  - Happy path: fake zip (built with `package:archive` in the test) holding `deno`; checksum file in Linux format (`<hex>  deno-…zip`) → `bin/deno` exists, `chmod +x` was run, `deno --version` was run, result is the first line of its stdout.
  - Windows checksum in PowerShell table format (`SHA256   <HEX>   D:\…\deno-…zip`) parses (the parser takes the first 64-hex-digit token, any case).
  - Checksum mismatch → `Err`, no `deno` and no temp files in `bin`.
  - Download throws midway → `Err(FailureKind.network)`, nothing left behind.
  - `--version` exits non-zero → `Err`, binary removed.
  - `remove()` deletes `bin/deno`.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/youtube/deno_installer_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** following `YtDlpInstaller.installOrUpdate` (verify, write `<binary>.download`, chmod, version check, rename).

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: Songies can install Deno for yt-dlp"
```

### Task 6: Asking before the download, then playing

**Files:**
- Create: `lib/ui/shell/runtime_prompt.dart` (dialog + progress)
- Create: `lib/player/runtime_prompter.dart`
- Modify: `lib/player/player_service.dart` (constructor callback; `_tryStart` retry)
- Modify: `lib/main.dart`, `lib/ui/shell/desktop_shell.dart` (register the dialog handler)
- Test: `test/player/runtime_prompter_test.dart`, `test/player/player_service_test.dart`, `test/ui/runtime_prompt_test.dart`

**Interfaces:**
- Produces:
  - `class RuntimePrompter { set handler(Future<bool> Function()? h); Future<bool> ask(); }`: `ask()` returns false with no handler; concurrent calls share one in-flight future.
  - `PlayerService(..., {Future<bool> Function()? onNeedsRuntime})`: when `_tryStart` gets `needsRuntime` and `!_automatic`, it awaits `onNeedsRuntime()`; true → resolve the same track once more; false → skip with the notice.
  - Dialog handler (desktop shell): shows the Global Constraints copy; Download → `DenoInstaller.install` with a progress bar → returns `Ok`; Not now / failure → false (failure shows its message in the dialog with Retry).

- [ ] **Step 1: Write the failing tests**
  - `RuntimePrompter`: no handler → false; two concurrent `ask()` → handler called once, both get its answer.
  - PlayerService: user-picked track gets `needsRuntime`, `onNeedsRuntime` returns true, second resolve Ok → plays; returns false → skipped with reason `ytdlp:needsRuntime:…`.
  - PlayerService: automatic advance onto the same track → `onNeedsRuntime` never called.
  - Widget test: the dialog shows the exact copy; Not now pops false.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/player test/ui/runtime_prompt_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement.** Android never sets a handler (its runtime is bundled, so `needsRuntime` can't occur there).

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: ask before installing Deno for an age-restricted song"
```

### Task 7: Sign-in actions and the Settings helper row

**Files:**
- Modify: `lib/ui/shell/player_error_snacks.dart`
- Modify: `lib/ui/settings/youtube_settings.dart` (after the yt-dlp version row, `:342-360`)
- Test: `test/ui/player_error_snacks_test.dart`, `test/ui/settings/youtube_settings_test.dart` (extend existing)

**Interfaces:**
- Consumes: `JsRuntimeFinder.find()`, `DenoInstaller.remove()`, providers for both (add `jsRuntimeFinderProvider`, `denoInstallerProvider` next to `ytDlpRunnerProvider` at `providers.dart:433`, overridden in `main.dart`).

- [ ] **Step 1: Write the failing tests**
  - A notice or error whose reason is `ytdlp:ageRestricted:…` or `ytdlp:ageRestrictedAccount:…` shows a `SnackBarAction` labelled `Sign in` that navigates to `/settings`; other reasons show no action.
  - Settings (desktop): runtime `songiesDeno` → "Helper for age-restricted songs: installed" with a Remove button that calls `remove()`; `systemNode` → "…: using Node.js" with no Remove; null → "…: not installed" with an Install button. Android: row hidden.

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: sign-in action for age-restricted songs, helper row in Settings"
```

### Task 8: Re-checking songs already flagged unavailable

**Files:**
- Modify: `lib/library/library_repository.dart` (next to `markUnavailable`, `:478`)
- Modify: `lib/main.dart` (run once at startup), settings key in `lib/data/settings_repository.dart`
- Modify: `docs/manual-test-checklist.md` (age-restricted song: signed out, signed in, no runtime, Android)
- Test: `test/library/library_repository_test.dart`

**Interfaces:**
- Produces: `Future<Result<int>> clearUnavailableYtTracks()` in `LibraryRepository`: for every `source == 'yt'` track with `unavailable`, writes `unavailable: false` with a fresh stamp (same fields as `markUnavailable`); returns the count. Settings key `kUnavailableRecheckDone` (bool).

- [ ] **Step 1: Write the failing tests**
  - Two flagged yt tracks + one flagged local track → returns 2; both yt rows unflagged with a new `clock`; the local row untouched.
  - Second call → returns 0, clocks unchanged.

- [ ] **Step 2: Run to see them fail.** Run: `flutter test test/library/library_repository_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement**; in `main.dart`, after the library opens: if `kUnavailableRecheckDone` is false, call it, log the count, then set the key.

- [ ] **Step 4: Run the full suite.** Run: `flutter analyze && flutter test`. Expected: clean; all pass except the two known stats timing tests.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: re-check YouTube songs flagged unavailable once"
```
