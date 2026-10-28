# Songies Plan 7: YouTube sign-in for a personal feed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sign in to YouTube once per device on Android, Windows and Linux. While signed in, Home shows the account's own YouTube Music feed and plays count in the account's history. Signed out, everything works exactly as today.

**Architecture:**
- **Storage:** a `YtSession` (the account's YouTube/Google cookies plus a display name) lives only in platform secure storage, behind a `YtSessionStore`. A Riverpod `ytAuthProvider` exposes signed-out, signed-in, expired or unavailable.
- **Signed-in requests:** `InnertubeClient.call` gains `auth: true`. It adds the session cookies, a `SAPISIDHASH` `Authorization` header and `X-Goog-AuthUser`. Only Home and play reports opt in.
- **Sign-in routes:** an in-app Google page on Android and Windows (`flutter_inappwebview`). On Linux, the in-app page if it works, and otherwise "Use the YouTube sign-in from my browser", which reads Firefox or Chromium-family cookies.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Riverpod 3, drift (no schema change), `flutter_secure_storage`, `flutter_inappwebview`, `sqlite3` (already pulled in by drift, used to read browser cookie stores) and `pointycastle` (Chromium cookie AES). Check each package's current version, and confirm it supports these platforms at plan time.

**Spec:** `docs/superpowers/specs/2026-10-27-songies-youtube-login-design.md`. It builds on the YouTube Music design and Plans 1–6. Read `docs/innertube-notes.md` first.

**Branch:** `plan-7-youtube-login`, made from `plan-6-song-menu` (the one-song-menu change, which is not pushed yet).

## Global Constraints

- **All three platforms ship together:** Android, Windows and Linux. Windows is built on the user's PC, so its route is covered by tests here and by a checklist item.
- **What goes out signed in:** only the Home `browse` request (`FEmusic_home`, including its continuations) and the play reports.
  - `player`, search, artist, album and playlist pages, and radio stay signed out, unless Task 1's probe records that signing them in is harmless. Even then, they are not changed in this plan.
- **No secrets in the open:** session cookies never appear in logs, `Failure` messages, notices, fixtures, docs, exports, device sync or commits. Songies never handles the Google password.
- **Storage:** the session lives only in secure storage, under the key `yt_session`.
  - Android: Keystore-backed storage. Windows: Credential Manager. Linux: Secret Service/libsecret.
  - It is never stored in drift and never synced.
  - With no secure storage, sign-in is not offered, and the Settings row explains why.
- **A broken sign-in never errors:** a refused or signed-out Home response falls back to the signed-out feed for that load. The sign-in is then marked expired, and the user is told once. There is no retry loop, and the stored session is kept until Sign out or a new sign-in.
- **No idle work:** no keep-alive, refresh timer or polling. Requests come only from user actions and playback (Plan 5 rules).
- **Settings:** the device-local key `kYtAccountName = 'yt_account_name'` holds the display name (it's cached, and it's not secret). Sign out removes it.
- **Copy:**
  - Settings → YouTube rows: **"Sign in to YouTube"**; signed in: **"Signed in as <name>"** (or **"Signed in"**) with **"Sign out"**.
  - Expired: **"Sign in again"**. The notice: **"YouTube sign-in expired — showing the regular feed"**.
  - Linux secondary option: **"Use the YouTube sign-in from my browser"**.
  - No secure storage: **"Sign-in needs a keyring (KWallet or GNOME Keyring), which isn't available"**.
- **Fixtures:** recorded signed-in responses are scrubbed of cookies, account and channel ids, emails, names, photo URLs and `datasyncId`s. `test/innertube/fixtures_scrubbed_test.dart` checks for this.
- Plan 4 rules hold: Motion tokens, reduced motion, no looping animation while paused, AA contrast, `Pressable`.
- **Commits end with:**
  - `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01PjntrucDy7bCG4aSheCsV1`

## Review Focus

1. **Cookie leakage through error text.** A signed-in request that fails (a socket error, an HTTP 401 or 403, or bad JSON) yields a `Failure` message and an `AppLog` line that contain no cookie value and no `SAPISIDHASH` value. This is pinned in Task 3.
2. **The session expires mid-session.**
   - The first refused Home load shows the signed-out feed, marks the session expired and emits the notice once.
   - A second Home open sends no signed-in request until the user signs in again: no loop and no repeated notice.
   - This is pinned in Task 3.
3. **No secure storage on Linux** (the keyring is locked or missing). The Sign-in row shows the explanation and the rest of Settings and the app work. A read that throws counts as "unavailable", not as a crash. This is pinned in Task 2.
4. **The browser is running while its cookies are read.** Firefox and Chromium hold their cookie database open. The reader copies the file, together with its `-wal` file, before opening it read-only, so it never locks or corrupts the user's browser profile. This is pinned in Task 6.
5. **Sign out while a signed-in Home load is in flight.**
   - The late response is not shown as the feed.
   - Nothing writes the session back.
   - The next Home open goes out signed out.
   - This is pinned in Task 3.

---

### Task 1: Signed-in probe, findings and scrubbed fixtures

**Files:**
- Create:
  - `tool/innertube_auth_probe.dart` (dev-only, never imported by lib/ or tests)
  - `test/fixtures/innertube/home_signed_in.json`
  - `test/fixtures/innertube/home_signed_out_marker.json`
- Modify:
  - `docs/innertube-notes.md` (new section "Signed in (Plan 7 probe)")
  - `test/innertube/fixtures_scrubbed_test.dart`

**Interfaces:**
- Produces findings, recorded in the notes, that later tasks read:
  - the exact headers a signed-in WEB_REMIX Home needs;
  - the **signed-in marker** (the response field that shows the request was signed in, e.g. `responseContext.serviceTrackingParams[].params` `logged_in` = `1`) and the signed-out marker;
  - whether Plan 5's anonymous `playbackTracking` URLs record into the account's history when sent with the session cookies (**"anonymous tracking attributes: yes/no"**).
- Produces the fixtures for Tasks 3 and 4.

- [ ] **Step 1: Ask the user to sign in.** The probe reads cookies from a Netscape `cookies.txt` path given as `--dart-define=COOKIES=<path>`. The path is outside the repo, the user exports the file from their browser, and the file is deleted after the probe.
  - If the user isn't available, hand-craft the two fixtures from the Plan 5 `browse_home.json`, with the marker fields set as yt-dlp/ytmusicapi document them.
  - Write **"UNVERIFIED — manual check pending"** at the top of the notes section, and continue.
- [ ] **Step 2: Record and check.** Run the probe with `flutter test tool/innertube_auth_probe.dart` (the Plan 5 timing tool's pattern), sending output to the scratchpad. It must:
  - fetch Home signed in and signed out;
  - fetch one `player` signed in;
  - send one play report each way, then check the account's history page (`FEmusic_history`) for the video.
  
  Print only statuses, counts and marker values.
- [ ] **Step 3: Write the fixtures and extend the scrub test.**
  - Save the scrubbed responses as the two fixtures.
  - Extend `fixtures_scrubbed_test.dart` so it fails on:
    - any `SAPISID`, `__Secure-` or `LOGIN_INFO` text;
    - a `UC…` channel id that isn't `UCRr1xG_2WIDs18a6cIiCxeA` (Plan 5's public artist);
    - any `@` email shape;
    - `lh3.googleusercontent.com/a/` account photo URLs;
    - any `datasyncId`.
- [ ] **Step 4: Run** `flutter test test/innertube/fixtures_scrubbed_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `docs: signed-in Innertube probe findings and scrubbed fixtures`.

### Task 2: Session storage and sign-in state

**Files:**
- Create:
  - `lib/innertube/yt_session.dart`
  - `lib/innertube/yt_session_store.dart`
- Modify:
  - `lib/data/settings_repository.dart` (`kYtAccountName`)
  - `lib/providers.dart`
  - `lib/main.dart`
  - `pubspec.yaml` (`flutter_secure_storage`)
  - Linux: check `linux/` CMake needs nothing extra beyond `libsecret-1-dev`, and document it in PROGRESS.
- Test: `test/innertube/yt_session_store_test.dart`, `test/innertube/yt_auth_test.dart`

**Interfaces:**
- Produces:
  - `class YtSession { final Map<String, String> cookies; String? get sapisid; String cookieHeader(); Map<String, Object?> toJson(); factory YtSession.fromJson(Map<String, Object?>); }`
    - `sapisid` reads `SAPISID`, falling back to `__Secure-3PAPISID`.
    - `toString()` returns `'YtSession(<n> cookies)'`, never the values.
  - `abstract class YtSessionStore { Future<bool> available(); Future<YtSession?> read(); Future<void> write(YtSession s); Future<void> clear(); }`
  - `class SecureYtSessionStore implements YtSessionStore`, using key `yt_session`.
    - `available()` does a write, read and delete round trip of a probe key, and returns false on any throw.
    - `read()` returns null on any throw.
  - `sealed class YtAuthState` with `YtSignedOut()`, `YtSignedIn(String? name)`, `YtExpired(String? name)` and `YtAuthUnavailable()`.
  - `class YtAuth extends Notifier<YtAuthState>` with:
    - `Future<void> load()`
    - `Future<void> signIn(YtSession s, {String? name})`
    - `Future<void> signOut()`
    - `void markExpired()`
    - `YtSession? get session` (in memory; null unless signed in)
  - `ytSessionStoreProvider` (`_unwired` plus override in main.dart) and `ytAuthProvider`.

- [ ] **Step 1: Write failing tests**, using an in-memory fake store and one that throws:
  - `signIn` writes the store and `kYtAccountName` and gives `YtSignedIn('Name')`.
  - `load()` after a restart restores `YtSignedIn`.
  - `signOut` clears the store and the name, gives `YtSignedOut`, and `session` is null.
  - `markExpired` gives `YtExpired` and keeps the stored session.
  - A store whose `available()` is false gives `YtAuthUnavailable` (Review Focus 3).
  - A `read()` that throws gives `YtAuthUnavailable`, not a crash.
  - `YtSession.toString()` and `'$state'` contain no cookie value.
  - `sapisid` falls back to `__Secure-3PAPISID`.
- [ ] **Step 2: Run** `flutter test test/innertube/yt_session_store_test.dart test/innertube/yt_auth_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** `main.dart` calls `load()` once at startup. It reads storage only, makes no network request, and keeps to the no-idle rule.
- [ ] **Step 4: Run** the tests. Expected: PASS. Then run `flutter analyze`.
- [ ] **Step 5: Commit** `feat: YouTube session in secure storage and sign-in state`.

### Task 3: Signed-in Home with quiet expiry

**Files:**
- Modify:
  - `lib/innertube/innertube_client.dart`
  - `lib/innertube/ytm_service.dart`
  - `lib/providers.dart` (`ytmHomeProvider`, the consent sheet guard)
  - `lib/ui/ytm/consent_sheet.dart`
- Create: `lib/innertube/sapisid_hash.dart`
- Test: `test/innertube/signed_in_call_test.dart`, `test/innertube/ytm_home_signed_in_test.dart`, `test/ui/home_page_test.dart`

**Interfaces:**
- Consumes: `ytAuthProvider` and `YtSession` (Task 2), and the Task 1 notes (headers and marker).
- Produces:
  - `String sapisidHash(String sapisid, String origin, DateTime now)`. It returns `'SAPISIDHASH <ts>_<sha1hex("<ts> <sapisid> <origin>")>'`, where `ts` is in unix seconds.
  - `InnertubeClient.call(..., {Map<String, String>? query, YtSession? session})`. With a session it:
    - sends `Cookie` (the session's cookie header, plus `SOCS=CAI` when consented);
    - sends `Authorization: sapisidHash(...)` with origin `https://music.youtube.com`;
    - sends `X-Goog-AuthUser: 0` and `X-Origin: https://music.youtube.com`;
    - keeps the visitor id unless Task 1 found it harmful.
  - `bool isSignedInResponse(Map<String, Object?> json)`, which uses Task 1's marker.
  - `YtmService.home({String? continuation, YtSession? session})` returns `Result<YtmHome>`. When signed in, it carries `bool signedIn` on `YtmHome`.

- [ ] **Step 1: Write failing tests:**
  - `sapisidHash('abc', 'https://music.youtube.com', DateTime.utc(2026,1,1))` equals `'SAPISIDHASH 1767225600_' + sha1hex('1767225600 abc https://music.youtube.com')`. Compute the expected hex in the test with `crypto`.
  - **Headers:** a call with a session sends the four headers, and a call without one sends none of them. `player`, `search` and `next` calls from `YtmService`/`InnertubeStreamSource` never carry `Authorization`.
  - **Expiry:**
    - Home with a session whose response is `home_signed_out_marker.json`, or is HTTP 401 or 403, triggers one anonymous retry and returns that feed.
    - `ytAuthProvider` becomes `YtExpired`, and the notice "YouTube sign-in expired — showing the regular feed" shows once.
    - Opening Home again sends no `Authorization` (Review Focus 2).
  - **Leakage:** a signed-in call failing with a `SocketException`, a 403 or bad JSON gives a `Failure.message`, and logs a line, that contain neither the cookie value nor the hash (Review Focus 1).
  - **Sign out mid-load:** sign out while a signed-in Home is gated. When it completes, the provider shows nothing from it, and the next load has no `Authorization` (Review Focus 5).
  - **Consent:** when signed in, `consentRequired` emissions don't open the consent sheet.
  - **Signed-in Home** (`home_signed_in.json`) parses into shelves like Plan 5's.
- [ ] **Step 2: Run** the three test files. Expected: FAIL.
- [ ] **Step 3: Implement.** `ytmHomeProvider` passes `ref.read(ytAuthProvider.notifier).session` only in state `YtSignedIn`, and watches `ytAuthProvider` so that signing in or out reloads Home. The expiry fallback lives in the provider, not in `YtmService`, so it can call `markExpired()`.
- [ ] **Step 4: Run** `flutter test test/innertube test/ui/home_page_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: signed-in YouTube Music Home with quiet expiry`.

### Task 4: Play reports count in the account's history

**Files:**
- Modify: `lib/innertube/play_reporter.dart`, `lib/main.dart`
- Possibly modify: `lib/innertube/ytm_service.dart` (only if Task 1 recorded "anonymous tracking attributes: no")
- Test: `test/innertube/play_reporter_test.dart`

**Interfaces:**
- Consumes:
  - `ytAuthProvider` state and `session` (Task 2), passed into `PlayReporter` as `YtSession? Function() session`;
  - `sapisidHash` (Task 3).
- Produces:
  - `PlayReporter(states, src, transport, {YtSession? Function()? session, Future<PlaybackTracking?> Function(String videoId, YtSession s)? accountTracking, Random? random})`. The unused `now` parameter is dropped.
  - If Task 1 recorded "no": add `YtmService.accountTracking(String videoId, YtSession s)`, which returns `Future<PlaybackTracking?>`. It makes one signed-in WEB_REMIX `player` call **only when a play has qualified**, and reads just `playbackTracking`. This call never feeds streaming.

- [ ] **Step 1: Write failing tests:**
  - Signed in: the two report GETs carry `Cookie` and `Authorization`. Signed out: neither carries them. Both cases keep Plan 5's `ver=2&cpn=` parameters.
  - If attribution is "no": a qualifying play makes exactly one `accountTracking` call, then reports to its URLs. A non-qualifying play (under 30 s) makes none. If `accountTracking` fails, it falls back to the anonymous URLs without the session.
  - A report failing while signed in logs no cookie value (Review Focus 1).
- [ ] **Step 2: Run** `flutter test test/innertube/play_reporter_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, and wire `session` and `accountTracking` in `main.dart`.
- [ ] **Step 4: Run** the test file. Expected: PASS.
- [ ] **Step 5: Commit** `feat: signed-in play reports count in YouTube history`.

### Task 5: Sign in and sign out on Android and Windows, plus the Settings row

**Files:**
- Create:
  - `lib/ui/settings/yt_sign_in_page.dart` (the in-app Google page)
  - `lib/innertube/yt_sign_in.dart` (the route abstraction)
- Modify:
  - `lib/ui/settings/youtube_settings.dart`
  - `pubspec.yaml` (`flutter_inappwebview`)
  - `android/app/src/main/AndroidManifest.xml` (if the package needs it)
  - `windows/` (WebView2 runtime note)
  - `lib/router.dart` (if the page is a route)
- Test: `test/ui/youtube_settings_test.dart`, `test/innertube/yt_sign_in_test.dart`

**Interfaces:**
- Consumes: `YtAuth.signIn/signOut` and `ytAuthProvider` (Task 2).
- Produces:
  - `abstract class YtSignInRoute { String get label; Future<bool> supported(); Future<YtSignInResult?> signIn(BuildContext context); }`, where `YtSignInResult { YtSession session; String? name; }`.
  - `class WebViewSignIn implements YtSignInRoute`, labelled "Sign in to YouTube":
    - It opens `https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/`.
    - When the URL's host is `music.youtube.com` and the `.youtube.com` cookies include `SAPISID` or `__Secure-3PAPISID`, it reads the `.youtube.com` and `.google.com` cookies through the package's cookie manager and closes the page.
    - It then clears the web view's cookies, so the session lives only in secure storage.
  - `List<YtSignInRoute> ytSignInRoutes()`: `[WebViewSignIn]` on Android and Windows. Linux comes in Task 6.
  - `ytSignInRoutesProvider`.
  - **Account name:** if Task 1 found a cheap signed-in source (e.g. `account/account_menu`), Settings fetches it once at sign-in. Otherwise, "Signed in".

- [ ] **Step 1: Write failing widget tests**, using fake routes and a fake store:
  - Signed out, Settings → YouTube shows "Sign in to YouTube". Tapping it runs the route and gives "Signed in as Name" with "Sign out".
  - Sign out asks to confirm, then clears and shows "Sign in to YouTube" again, and Home is invalidated.
  - `YtExpired` shows "Sign in again".
  - `YtAuthUnavailable` shows the keyring explanation and no sign-in row.
  - A route that returns null (the user closed the page) leaves the user signed out with no error.
  - **Session check:** `WebViewSignIn` keeps only `.youtube.com` and `.google.com` cookies, and rejects a cookie set without `SAPISID` or `__Secure-3PAPISID`. Unit-test the cookie filter, `YtSessionFromCookies.build(List<Cookie>)` returning `YtSession?`, separately from the web view.
- [ ] **Step 2: Run** `flutter test test/ui/youtube_settings_test.dart test/innertube/yt_sign_in_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Reuse Plan 4's settings row widgets, `Pressable` and motion tokens.
- [ ] **Step 4: Run** the tests. Expected: PASS. Then run `flutter build apk --release`. Expected: it builds.
- [ ] **Step 5: Commit** `feat: sign in to YouTube on Android and Windows`.

### Task 6: Sign in on Linux

**Files:**
- Create:
  - `lib/innertube/browser_cookies.dart`
  - `lib/innertube/browser_sign_in.dart`
- Modify: `lib/innertube/yt_sign_in.dart` (`ytSignInRoutes` on Linux), `pubspec.yaml` (`pointycastle`)
- Test: `test/innertube/browser_cookies_test.dart`, with hand-built fixture databases created in the test's temp dir, never committed with real data.

**Interfaces:**
- Consumes: `YtSignInRoute`, `YtSessionFromCookies.build` (Task 5).
- Produces:
  - `enum BrowserKind { firefox, chrome, chromium, brave, edge, vivaldi }`.
  - `Future<List<BrowserProfile>> findBrowserProfiles({String? home})`. It finds Firefox `cookies.sqlite` under `~/.mozilla/firefox/*/`, including the Flatpak path `~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/`. It also finds Chromium-family `Cookies` under `~/.config/<browser>/<profile>/`.
  - `Future<Result<List<Cookie>>> readBrowserCookies(BrowserProfile p, {Future<String?> Function(String app)? keyringSecret})`:
    - Firefox reads `moz_cookies` as plain text.
    - Chromium decrypts the `v10` prefix (AES-128-CBC with key PBKDF2(`'peanuts'`, `'saltysalt'`, 1 iteration, 16 bytes), IV of 16 spaces) and the `v11` prefix (the same, with the password from Secret Service `"<Browser> Safe Storage"`).
    - The reader copies the database and its `-wal` file to a temp dir before opening it read-only (Review Focus 4).
    - It keeps only `.youtube.com` and `.google.com`.
    - Errors become `Err` with a plain message such as "Couldn't read Firefox's cookies", never the cookie values.
  - `class BrowserSignIn implements YtSignInRoute`, labelled "Use the YouTube sign-in from my browser". It lists the found profiles that have a YouTube session, asks the user to pick one and confirm, then builds the session.
  - **Route 1 on Linux:** try an in-app page with a maintained WebKitGTK package (e.g. `desktop_webview_window`) that can read cookies.
    - If it works on this Nobara machine, `ytSignInRoutes()` on Linux is `[thatRoute, BrowserSignIn]`.
    - Otherwise it is `[BrowserSignIn]`, and the reason is recorded in the notes.
    - Timebox route 1 to one attempt, and record the outcome.

- [ ] **Step 1: Write failing tests**, using a temp `home` with built sqlite files:
  - Firefox finds `.youtube.com` SAPISID.
  - Chromium `v10` decrypts a value encrypted in the test with the `peanuts` key.
  - Chromium `v11` uses the injected `keyringSecret`.
  - Non-YouTube cookies are dropped.
  - A database whose `-wal` is present is read through a copy, and the original's bytes and mtime are unchanged afterwards (Review Focus 4).
  - A locked or corrupt file gives `Err` with no cookie text.
  - With no profiles found, `BrowserSignIn.supported()` is false.
- [ ] **Step 2: Run** `flutter test test/innertube/browser_cookies_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the reader and the route. Then attempt route 1 and record the result in `docs/innertube-notes.md`.
- [ ] **Step 4: Run** the test file, then `flutter build linux --release`. Expected: PASS, and it builds.
- [ ] **Step 5: Commit** `feat: sign in to YouTube on Linux (in-app page or browser sign-in)`.

### Task 7: Verification, docs and checklist

**Files:** `docs/PROGRESS.md`, `docs/manual-test-checklist.md`, `docs/innertube-notes.md`, `lib/ui/playlist/playlist_page.dart` (carry-over)

- [ ] **Step 1: Carry-over from Plan 6's review:** add `if (!mounted) return;` at the top of `PlaylistPage._removeEntry`, with a test where the playlist page is gone before Remove is chosen.
- [ ] **Step 2: Run** `flutter test`, `flutter analyze`, `flutter build apk --release` and `flutter build linux --release`. Expected: all pass.
- [ ] **Step 3: Live check (if the user is available):** sign in on Linux through the app's real route.
  - Check: Home shows the account's rows. A song played past 30 s appears in the account's YouTube Music history. Sign out returns to the regular feed.
  - Record the outcomes (no identifiers) in the notes.
  - If the user isn't available, mark the Task 1 items "manual check pending".
- [ ] **Step 4: Checklist additions:**
  - one sign-in, feed and history check per platform: Android, Windows, Linux (in-app and browser route);
  - expiry: sign out of Google in a browser, then open Home and expect the regular feed and one notice;
  - sign out;
  - a keyring that's locked or missing on Linux.
- [ ] **Step 5: PROGRESS.md:**
  - mark Plan 6 (song menu) and Plan 7 done, with rulings and parked items;
  - note the Linux packages Linux sign-in needs (`libsecret`, plus WebKitGTK if route 1 is used);
  - next is Plan 8 (synced lyrics), then Plan 9 (listening statistics), then device sync and packaging.
- [ ] **Step 6: Commit** `docs: Plan 7 verification, checklist and progress`.
