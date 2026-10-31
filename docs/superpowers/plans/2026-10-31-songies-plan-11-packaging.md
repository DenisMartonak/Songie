# Songies Plan 11: Packaging, Releases and In-App Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pushing a `vX.Y.Z` tag makes GitHub build and publish a signed APK, a Windows installer and a Linux AppImage. Songies on every platform then finds the new release, asks, downloads, verifies and installs it.

**Architecture:**
- **Updater core:** pure Dart in `lib/update/`.
  - Parsing the GitHub "latest release" JSON and comparing versions.
  - A throttled checker that remembers a skipped version.
  - A verifying downloader.
- **Installing:** goes through one `UpdateInstaller` interface with three implementations:
  - an Android method channel (a Kotlin plugin with a FileProvider);
  - a silent Inno Setup run on Windows;
  - an AppImage swap on Linux.
- **Packaging:** lives in `windows/installer/` and `tool/`.
- **CI:** one GitHub Actions workflow builds and publishes everything.

**Tech Stack:** Flutter 3.47.8, Dart 3.13, Riverpod 3, Kotlin (Android plugin), Inno Setup 6, appimagetool / linuxdeploy, GitHub Actions. New package: `url_launcher: ^6.3.1`.

**Spec:** `docs/superpowers/specs/2026-10-31-songies-packaging-design.md`. Read it before any task. Where this plan and the spec disagree, the spec wins.

## Global Constraints

- **Branch:** `plan-11-packaging`, made from `plan-10-device-sync`. Don't push or merge.
- **Release repo:** owner `DenisMartonak`, repo `Songie`. It is overridable only by `--dart-define=SONGIES_UPDATE_REPO=owner/repo`, and release builds never set it.
- **API:** `GET https://api.github.com/repos/<owner>/<repo>/releases/latest`, anonymous, with `Accept: application/vnd.github+json`. A 404 (private repo or no releases) means "no update".
- **Asset names:**
  - `songies-X.Y.Z.apk`
  - `songies-X.Y.Z-windows-setup.exe`
  - `songies-X.Y.Z-x86_64.AppImage`
  - `SHA256SUMS` (the `sha256sum` format: `<hex>  <name>`)
  - `version.json` (`{"version":"X.Y.Z","build":N}`)
- **Releases:**
  - The tag `vX.Y.Z` must equal the `X.Y.Z` in `pubspec.yaml`, and `N` must be greater than the last release's `version.json` build. Otherwise the workflow fails.
  - Drafts and pre-releases are ignored.
- **Checking:**
  - At startup, once, **3 s** after the first frame, and at most once per **12 h** (the setting `update_last_check_ms`).
  - Whenever the user taps the Settings → About button "Check for updates".
- **"Not now":** stores the setting `update_skipped_version` = `X.Y.Z`. The startup check stays silent for that version and asks again for a newer one. The button always shows it.
- **Verifying:** SHA-256 must match `SHA256SUMS`. On Android, the APK's signer must equal the installed app's, and its versionCode must be greater than the installed one.
- **Wi-Fi only:** on Android, the existing `kWifiOnly` setting applies to update downloads. On mobile data, offer **Download anyway**.
- **Exact copy:**
  - "Songies X.Y.Z is available"
  - buttons "Update now" and "Not now"
  - "Check for updates"
  - "Couldn't check for updates. Check your connection."
  - "No updates found."
  - "Open download page"
  - "Download anyway"
- **Windows installer:** Inno Setup, per user (`PrivilegesRequired=lowest`), installs into `{localappdata}\Programs\Songies` with a fixed `AppId`. The silent update runs `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` and the installer starts Songies when it finishes. Uninstalling keeps `%APPDATA%\Songies` unless the user ticks a box.
- **AppImage:** built on `ubuntu-22.04`. It bundles libmpv and its media libraries, but never GTK, libsecret, D-Bus or Avahi.
- **Android release build:** stays unshrunk (no `minifyEnabled`), one universal APK.
- **Secrets:** never committed, never logged, never placed in a built file. `key.properties` and `*.jks` / `*.keystore` are git-ignored.
- **Earlier rules still hold:** tests never touch the network or real home directories; no idle work beyond the agreed startup check; `Motion.of(context)`; AA contrast via `SongiesColors`.
- **Commits** end with a Co-Authored-By line naming the model that wrote them, and:
  `Claude-Session: https://claude.ai/code/session_01Pjntruw24Wq5rjHruQoDNn`
- **Checks before each commit:** `flutter analyze` is clean and `flutter test` passes (the stats "under 500 ms" timing test is known flaky). Use `dart format` on touched files only.

## Review Focus

1. **Offline or a slow network at startup.** The check must never delay startup or show an error. Test in Task 4: a startup check with a transport that throws, or never answers within 10 s, shows nothing, and a check timeout exists.
2. **A release missing this platform's file** (the Windows job failed, say). There is no prompt on that platform, and the others still update. Test in Task 1 (`pickAsset` returns null) and Task 2 (`check` yields `UpToDate`).
3. **Not enough disk space, or the download is cut.** A partial file never gets installed, and the next attempt starts clean. Test in Task 2: a download stream that errors leaves no file at the final path.
4. **The AppImage sitting in a folder the user can't write to.** "Open download page" is offered instead of failing mid-swap. Test in Task 3 (the Linux installer reports `cannotReplace`).
5. **Version strings with a `v` prefix or a build suffix** (`v1.2.0`, `1.2.0+7`), and a two-part tag (`1.2`). Compare correctly, or reject. Test in Task 1.

---

### Task 1: Release model, version compare, asset pick, checksums

**Files:**
- Create: `lib/update/release.dart`
- Test: `test/update/release_test.dart`

**Interfaces:**
- Produces:
  - `class AppVersion implements Comparable<AppVersion>`, with:
    - `final int major, minor, patch`;
    - `static AppVersion? tryParse(String s)`: accepts an optional leading `v` and drops a `+build` suffix; requires exactly three numeric parts, else null;
    - `toString()` gives `X.Y.Z`.
  - `enum UpdatePlatform { android, windows, linux }`, with `String assetName(AppVersion v)` producing the names from Global Constraints.
  - `class ReleaseAsset { final String name; final Uri url; final int size; }`
  - `class Release`, with:
    - `final AppVersion version; final String notes; final Uri htmlUrl; final List<ReleaseAsset> assets;`
    - `static Release? fromGitHubJson(Map<String, Object?> json)`: null for drafts, pre-releases or a bad tag. `notes` comes from `body` (empty when null).
    - `ReleaseAsset? pickAsset(UpdatePlatform p)` and `ReleaseAsset? get checksums`.
  - `Map<String, String> parseSha256Sums(String text)`: maps a file name to lowercase hex, ignoring blank and malformed lines.

- [ ] **Step 1: Write the failing tests.**
  - `parses v1.2.3 and 1.2.3+7 the same`.
  - `rejects 1.2 and 1.2.3.4 and empty`.
  - `orders 1.10.0 above 1.9.9`.
  - `fromGitHubJson skips drafts and prereleases`.
  - `pickAsset finds each platform file and returns null when missing`.
  - `parseSha256Sums reads sha256sum output and skips junk lines`.
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/update/release_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: release model and version compare for updates`).

### Task 2: Update checker and verifying downloader

**Files:**
- Create: `lib/update/update_checker.dart`, `lib/update/update_downloader.dart`
- Modify: `lib/data/settings_repository.dart` (keys `kUpdateLastCheckMs = 'update_last_check_ms'`, `kUpdateSkippedVersion = 'update_skipped_version'`), `lib/core/paths.dart` (`AppPaths.updates` = `<appData>/updates`)
- Test: `test/update/update_checker_test.dart`, `test/update/update_downloader_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `typedef FetchJson = Future<Map<String, Object?>?> Function(Uri url);` returns null on 404 and throws on other failures. The default implementation uses `dart:io` `HttpClient` with a **10 s** timeout and the GitHub accept header.
  - `sealed class UpdateCheck`, with:
    - `UpdateAvailable(Release release, ReleaseAsset asset)`;
    - `UpToDate()`;
    - `CheckFailed(Object error)`.
  - `class UpdateChecker`, with:
    - `UpdateChecker({required FetchJson fetch, required SettingsRepository settings, required AppVersion current, required UpdatePlatform platform, String repo = kUpdateRepo, DateTime Function() now = DateTime.now})`;
    - `Future<UpdateCheck?> checkAtStartup()`: null when throttled (less than 12 h since the last check) or when the result is the skipped version. It records the check time either way and never throws;
    - `Future<UpdateCheck> checkNow()`: ignores the throttle and the skip;
    - `Future<void> skip(AppVersion v)`.
  - `const String kUpdateRepo = String.fromEnvironment('SONGIES_UPDATE_REPO', defaultValue: 'DenisMartonak/Songie');`
  - `class UpdateDownloader`, with:
    - `UpdateDownloader({required Directory dir, HttpClient Function()? client})`;
    - `Stream<DownloadProgress> download(Release r, ReleaseAsset a, {UpdateCancel? cancel})`: it fetches `SHA256SUMS` first, streams the asset into `<dir>/<name>.part`, checks the SHA-256 and renames it. It ends with `DownloadDone(File file)` or `DownloadFailed(DownloadError kind)`.
  - `enum DownloadError { network, checksumMismatch, noChecksum, cancelled }`, `class DownloadProgress { int received, total; }`, `class UpdateCancel`.

- [ ] **Step 1: Write the failing tests** (with fakes: `FetchJson` returns canned JSON, and the downloader gets a local `HttpServer` on loopback).
  - `startup check is throttled for 12 hours`.
  - `startup check stays quiet for the skipped version but offers a newer one`.
  - `checkNow ignores skip and throttle`.
  - `404 is UpToDate`.
  - `network error at startup returns CheckFailed silently and never throws`.
  - `release without this platform's asset is UpToDate` (Review Focus 2).
  - `download verifies sha256 and renames`.
  - `checksum mismatch deletes the file`.
  - `missing SHA256SUMS fails as noChecksum`.
  - `cut download leaves no file at the final path` (Review Focus 3).
  - `cancel removes the part file`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: update checker and verifying downloader`).

### Task 3: Platform installers

**Files:**
- Create: `lib/update/update_installer.dart` (the interface plus the Windows and Linux implementations), `lib/update/android_update_installer.dart`
- Create: `android/app/src/main/kotlin/com/songies/songies/UpdaterPlugin.kt`, `android/app/src/main/res/xml/update_paths.xml`
- Modify: `android/app/src/main/kotlin/com/songies/songies/MainActivity.kt` (register the plugin, following the existing plugins), `android/app/src/main/AndroidManifest.xml` (`REQUEST_INSTALL_PACKAGES`, a `FileProvider` with authority `${applicationId}.updates`), `pubspec.yaml` (`url_launcher: ^6.3.1`)
- Test: `test/update/update_installer_test.dart`

**Interfaces:**
- Consumes: Task 2's `File`.
- Produces:
  - `sealed class InstallOutcome`, with:
    - `Installing()`: the app is about to quit, or the system installer is open;
    - `NeedsPermission()`: Android "Install unknown apps" is off;
    - `Rejected(String reason)`: wrong signer, or not newer;
    - `CannotReplace()`: Linux, not running from a writable AppImage;
    - `InstallFailed(Object error)`.
  - `abstract class UpdateInstaller`, with:
    - `Future<bool> canSelfUpdate()`;
    - `Future<InstallOutcome> install(File file)`;
    - `Future<void> openPermissionSettings()` (a no-op on desktop).
  - `class WindowsUpdateInstaller implements UpdateInstaller`: starts the installer detached with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`, then calls `quit()`.
  - `class LinuxUpdateInstaller implements UpdateInstaller`, constructed with `Map<String, String> env`, `Future<Never> Function() quit` and a process starter:
    - `canSelfUpdate()` is true only when `env['APPIMAGE']` names a file whose folder is writable;
    - `install` copies the download to `<folder>/.<name>.part`, runs chmod 755, renames it over `APPIMAGE`, starts the new file detached, then calls `quit()`.
  - `class AndroidUpdateInstaller implements UpdateInstaller`, using MethodChannel `songies/updater`:
    - `inspect(path)` → `{sameSigner: bool, versionCode: int, installedVersionCode: int}`;
    - `canInstall()` → bool;
    - `openInstallSettings()`;
    - `install(path)`.
    - It rejects when `!sameSigner` or `versionCode <= installedVersionCode`.
  - `Future<void> openDownloadPage(Uri htmlUrl)` (url_launcher, external).
  - `Future<Never> quitForUpdate(AppDatabase db)` in `lib/update/update_installer.dart`: closes the database, then calls `exit(0)`.
  - `final updateInstallerProvider = Provider<UpdateInstaller>(...)`, which picks the implementation by platform.

- [ ] **Step 1: Write the failing tests** (fakes for the process starter, `quit`, `env`, and a mocked method channel).
  - `windows starts the installer silently, then quits`.
  - `linux swaps the AppImage atomically and relaunches`.
  - `linux without APPIMAGE cannot self update`.
  - `linux in a read-only folder cannot replace` (Review Focus 4).
  - `android rejects a different signer`.
  - `android rejects an older or equal versionCode`.
  - `android without install permission asks for it`.
  - `android happy path calls install`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.** In Kotlin, read signers with `PackageManager.getPackageArchiveInfo(path, GET_SIGNING_CERTIFICATES)` and compare them with the installed app's (use `GET_SIGNATURES` below API 28). `canRequestPackageInstalls()` covers API 26+. Install through `ACTION_VIEW` with a FileProvider URI and `FLAG_GRANT_READ_URI_PERMISSION`. Store downloads under the app's external files `updates/` folder, which `update_paths.xml` covers.
- [ ] **Step 4: Run all tests and analyze, then run `flutter build apk --release` to confirm the plugin compiles.**
- [ ] **Step 5: Commit** (`feat: platform update installers`).

### Task 4: Update flow and UI

**Files:**
- Create: `lib/update/update_controller.dart`, `lib/ui/update/update_dialog.dart`
- Modify: `lib/app.dart` (start the startup check once, 3 s after the first frame), `lib/ui/settings/settings_page.dart` (`_AboutSection`: version row plus a "Check for updates" button with its result), `lib/providers.dart` (`updateCheckerProvider`, `updateControllerProvider`)
- Test: `test/update/update_controller_test.dart`, `test/ui/update_dialog_test.dart`, update `test/ui/settings_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3, `networkStatusProvider` (`NetworkKind`), and `kWifiOnly` / `wifiOnlyDefault`.
- Produces: `class UpdateController extends Notifier<UpdateState>`, with:
  - `Future<void> startup()` and `Future<void> checkNow()`;
  - `Future<void> accept()`, which downloads, then installs;
  - `void notNow()`, which calls `skip`;
  - `void cancel()`.
- `sealed UpdateState`:
  - `Idle`, `Checking`;
  - `Available(Release, ReleaseAsset)`;
  - `NoUpdate`, `CheckError`;
  - `Downloading(received, total)`, `WaitingForWifi`;
  - `Installing`, `NeedsPermission`, `Failed(String message)`;
  - `ManualOnly(Uri htmlUrl)`, when `canSelfUpdate()` is false.

**Behaviour:**
- **Startup:** the check shows the dialog only for `UpdateAvailable`, and shows nothing for anything else.
- **The button:** "Checking…", then the dialog, or "No updates found.", or "Couldn't check for updates. Check your connection."
- **The dialog:**
  - title "Songies X.Y.Z is available";
  - the release notes, about 600 characters, scrollable;
  - buttons "Update now" and "Not now", or "Open download page" when only a manual update is possible.
- **On mobile data with Wi-Fi only on (Android):** the dialog says so and offers "Download anyway".
- **While downloading:** progress with Cancel. The user can dismiss the dialog and keep listening. When the download is done, "Install now" appears.

- [ ] **Step 1: Write the failing tests.**
  - `startup shows the dialog only when an update is available`.
  - `startup offline or slow shows nothing and does not block` (Review Focus 1: a fake fetch that never completes; the app keeps working, and the controller gives up after the 10 s timeout).
  - `not now skips the version`.
  - `wifi only on mobile data waits and offers download anyway`.
  - `accept downloads then installs`.
  - `checksum failure shows Failed and installs nothing`.
  - `manual only offers the download page`.
  - `settings button shows No updates found / connection error`.
  - `dialog copy is exact`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: in-app update prompt and Check for updates`).

### Task 5: Android release signing and releasing guide

**Files:**
- Modify: `android/app/build.gradle.kts` (a release `signingConfig` read from `android/key.properties` or the environment variables `SONGIES_KEYSTORE_PATH`, `SONGIES_KEYSTORE_PASSWORD`, `SONGIES_KEY_ALIAS`, `SONGIES_KEY_PASSWORD`; without them, fall back to the debug key with a Gradle warning "Release build signed with the DEBUG key: it cannot update a release install"), `.gitignore` (`android/key.properties`, `*.jks`, `*.keystore`)
- Create: `docs/releasing.md`

**Contents of `docs/releasing.md`** (plain language):
1. Create the keystore once with `keytool -genkeypair -v -keystore songies-release.jks -keyalg RSA -keysize 4096 -validity 36500 -alias songies`.
2. Back up the keystore and passwords outside the repo, and say why.
3. Add the four GitHub secrets, plus `SONGIES_KEYSTORE_BASE64` (the base64 of the `.jks`).
4. Make a release: bump `version:` in `pubspec.yaml` and `appVersion`, commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. The first-time phone switch: sync to a PC with device sync, uninstall, install the release APK, pair again and sync back. Downloads and sign-in are redone; settings are not carried over.
6. The first-time Windows switch from the loose build folder.
7. SmartScreen: "More info", then "Run anyway".
8. Linux: make the AppImage executable, plus the firewall and Avahi notes for sync.
9. The checklist before making the repo public (it points to Task 8's script).

- [ ] **Step 1: Verify locally.** `flutter build apk --release` without `key.properties` still succeeds and prints the warning. With a throwaway keystore and the env vars set (in the scratchpad, never committed), the APK verifies with `apksigner verify --print-certs` and shows the throwaway certificate.
- [ ] **Step 2: Write `docs/releasing.md`.**
- [ ] **Step 3: Run all tests and analyze.**
- [ ] **Step 4: Commit** (`feat: release signing config and releasing guide`).

### Task 6: Windows installer and Linux AppImage

**Files:**
- Create: `windows/installer/songies.iss`, `tool/build_appimage.sh`, `linux/packaging/songies.desktop`, `linux/packaging/AppRun` (if the tooling needs it)
- Test: `test/tool/packaging_files_test.dart`

**Interfaces:**
- Produces:
  - `songies.iss`:
    - takes `/DAppVersion=X.Y.Z` and `/DSourceDir=<release bundle>`;
    - outputs `songies-X.Y.Z-windows-setup.exe`;
    - has a fixed `AppId` (a newly generated GUID, written into the file once);
    - `PrivilegesRequired=lowest`, `DefaultDirName={localappdata}\Programs\Songies`;
    - Start menu and optional desktop shortcuts;
    - `[Run]` launches Songies after install (silent too, `skipifnotsilent` unchecked);
    - `CloseApplications=yes`;
    - the uninstall asks whether to delete `%APPDATA%\Songies`, default No.
  - `tool/build_appimage.sh <version>`:
    - runs on Ubuntu 22.04 after `flutter build linux --release`;
    - builds an AppDir from `build/linux/x64/release/bundle`, with the desktop file and the app icon from `assets/`;
    - bundles libmpv and its media libraries with linuxdeploy, excluding GTK, glib, libsecret, D-Bus and Avahi;
    - outputs `songies-X.Y.Z-x86_64.AppImage`.

- [ ] **Step 1: Write a failing test** that checks the packaging files: `songies.iss` contains `PrivilegesRequired=lowest`, `{localappdata}\Programs\Songies`, an `AppId=` line and `/VERYSILENT`-compatible `[Run]` flags; the desktop file has `Exec=` and `Icon=`.
- [ ] **Step 2: Run it and confirm it fails.**
- [ ] **Step 3: Write the files.**
- [ ] **Step 4: Run `tool/build_appimage.sh 1.0.0` locally** (Nobara is fine for a smoke check; CI builds on 22.04). Confirm the AppImage starts, and `ldd` on the bundled player library resolves. If the local machine lacks a tool, install it in the scratchpad, never system-wide without asking. Report the outcome. The Windows installer is first built in Task 7's CI.
- [ ] **Step 5: Run all tests and analyze.**
- [ ] **Step 6: Commit** (`feat: Windows installer script and Linux AppImage build`).

### Task 7: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`, `tool/check_release_version.dart`
- Test: `test/tool/check_release_version_test.dart`

**Interfaces:**
- Produces:
  - `tool/check_release_version.dart --tag vX.Y.Z --pubspec pubspec.yaml [--previous version.json]`: exits non-zero with a clear message when the tag doesn't match the pubspec `X.Y.Z`, when `appVersion` in `lib/core/app_version.dart` differs, or when the build isn't greater than the previous one. With `--write version.json`, it writes the new file.
  - **The workflow:**
    - **Triggers:** `push: tags: ['v*']` and `workflow_dispatch` (build only, no release).
    - **Jobs:**
      - `checks` (ubuntu-22.04): checkout, pinned Flutter 3.47.8, `flutter pub get`, `flutter analyze`, `flutter test`, and on tags, the version check against the previous release's `version.json` (downloaded with `gh release download` when one exists).
      - `android` (needs `checks`): decode `SONGIES_KEYSTORE_BASE64` into the runner's temp dir, `flutter build apk --release` with the signing env vars, rename to `songies-X.Y.Z.apk`, upload the artifact.
      - `linux` (ubuntu-22.04, needs `checks`): install the build dependencies (GTK and the mpv dev packages), `flutter build linux --release`, `tool/build_appimage.sh`, upload.
      - `windows` (windows-latest, needs `checks`): `flutter build windows --release`, install Inno Setup through choco, `iscc windows/installer/songies.iss /DAppVersion=... /DSourceDir=...`, upload.
      - `publish` (tags only, needs all): download the artifacts, write `SHA256SUMS` with `sha256sum` over the three files, write `version.json`, then `gh release create vX.Y.Z --generate-notes` with all five assets.
    - Secrets are referenced only through `${{ secrets.* }}`, never echoed. The keystore file is deleted at the end of the job.
    - `permissions: contents: write` only on `publish`.

- [ ] **Step 1: Write the failing tests** for the version checker: `matching tag passes`, `mismatched tag fails`, `appVersion mismatch fails`, `build not increasing fails`, `no previous release passes`, `writes version.json`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement the checker and the workflow.**
- [ ] **Step 4: Validate the workflow syntax** with `actionlint` if available (fetched into the scratchpad), else `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/release.yml`. Report which ran. Don't push. Running the workflow on GitHub happens after the branch is pushed, by the user or with their go-ahead.
- [ ] **Step 5: Run all tests and analyze.**
- [ ] **Step 6: Commit** (`feat: release workflow`).

### Task 8: Secret scan before going public

**Files:**
- Create: `tool/scan_secrets.sh`

**Interfaces:**
- Produces: `tool/scan_secrets.sh`, which scans **all history** (`git log -p --all`) and the current tree for:
  - file names matching `*.jks`, `*.keystore`, `key.properties`, `.env*`, `*.pem` (excluding test fixtures under `test/`, which it lists separately);
  - patterns: `-----BEGIN .*PRIVATE KEY-----`, `ghp_`/`github_pat_`, `AKIA[0-9A-Z]{16}`, `SAPISID`/`__Secure-3PSID` followed by `=` and a long value, `password\s*[:=]\s*\S{6,}`.
  - It also runs `gitleaks detect --log-opts=--all` when `gitleaks` is on PATH.
  - It prints each hit with the commit and path, and exits 1 on hits, 0 when clean.
  - It never rewrites anything.

- [ ] **Step 1: Write the script.** Test it on a temporary repo in the scratchpad: plant a fake private key in one commit and a clean file in another; the script reports the planted one and exits 1, and exits 0 on a clean repo.
- [ ] **Step 2: Run it on this repo.** Record the output in the report. Every hit is reported, not fixed: the user decides.
- [ ] **Step 3: Commit** (`feat: secret scan for the whole history`).

### Task 9: Checklist, docs and builds

**Files:**
- Modify: `docs/manual-test-checklist.md` (a Plan 11 section), `docs/PROGRESS.md`, `README.md` (install and update paragraph)
- Create: `docs/plan-11-session-log.md`

- [ ] **Step 1: Write the Plan 11 checklist section.** It covers:
  - the first tagged release on GitHub (the workflow green, five assets);
  - installing on each platform from the release;
  - the first-time phone switch from the debug build;
  - the first-time Windows switch;
  - an update from one release to the next on each platform, with the library intact;
  - "Not now", then a newer version asks again;
  - an offline startup is silent, and the offline button shows the message;
  - SmartScreen;
  - the AppImage on a clean Fedora/Nobara;
  - the read-only AppImage folder offers the download page;
  - the `SONGIES_UPDATE_REPO` test build against a public test repo;
  - the secret scan before going public.
- [ ] **Step 2: Run the full checks:** `flutter analyze`, `flutter test`, `flutter build apk --release`, `flutter build linux --release` and `tool/build_appimage.sh`. Record counts and sizes.
- [ ] **Step 3: Update `PROGRESS.md` and the session log** with what's done, what's unverified (the workflow on GitHub, Windows installer runs, device installs) and the next steps.
- [ ] **Step 4: Commit** (`docs: Plan 11 checklist and progress`).
