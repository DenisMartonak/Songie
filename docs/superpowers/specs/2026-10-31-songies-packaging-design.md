# Songies: packaging, releases and in-app updates — design

**Status:** agreed in conversation · 2026-10-31
**Becomes:** Plan 11, branch `plan-11-packaging` (made from `plan-10-device-sync`).
**Builds on:** the main design (`2026-10-21-songies-design.md` §14 milestone 7 "Packaging", §2 non-goals) and Plans 1–10.

## Why

The user has been building Songies by hand: the APK and Linux build on the Nobara PC, and the Windows build on a separate Windows PC. They want to install and update Songies on all their devices the easy way. That means downloading it from GitHub, and having the app offer updates by itself.

**Success:** the user marks a new version on GitHub. GitHub builds a signed APK, a Windows installer and a Linux AppImage, and attaches them to a release. On each device, the next time Songies opens it says a new version is available. The user taps **Update now**, Songies downloads the right file and installs it, and the library, settings, sign-in and paired devices are all still there afterwards.

## What the user decided

- **Get it from GitHub.** Users download from the repo's Releases page. There is no store (the main design's non-goal stands).
- **GitHub builds it.** GitHub Actions builds all three files when a new version is marked. The user doesn't build releases by hand any more.
- **In-app updates on every platform.** When the app sees a newer release it offers to update. If the user agrees, it downloads and installs the update:
  - **Android:** downloads the APK and opens the system install screen, where the user confirms. Android requires that confirmation.
  - **Windows:** downloads the new installer and runs it. Songies closes, updates and reopens.
  - **Linux:** downloads the new AppImage, swaps it in for the running one, and restarts.
- **When it checks:** once each time the app opens, plus a **Check for updates** button in Settings.
- **The repo is private for now and will be made public later.** The design assumes a public repo. Until it is public, building and releasing still work, but the in-app check finds nothing and stays quiet (see "Private repo").

## Goals

1. A GitHub Actions workflow that builds, signs and publishes the three files to a GitHub Release when a version tag is pushed.
2. A signed release APK using the user's own key, so updates install over the old app.
3. A Windows installer and a Linux AppImage that run on a clean machine with nothing else installed.
4. An in-app updater: a check at startup and on a button, an "Update now" prompt, download with progress, then install on each platform.
5. A safety check before the repo goes public: no secrets anywhere in the git history.

## Non-goals

- Store distribution (Play Store, Microsoft Store, Flathub): a main-design non-goal.
- iOS and macOS.
- Silent or forced updates. The user always agrees first, and Android always shows its own install screen.
- Delta or patch updates. The whole file is downloaded.
- Beta or pre-release channels.
- Code-signing the Windows installer with a paid certificate (see "Windows SmartScreen").
- Updating yt-dlp. It already has its own updater (Plan 3), unchanged.

## Anti-goals (what would make this a failure even if it works)

- **An update loses the user's data.** The library database, downloads, themes, fonts, the YouTube sign-in or paired devices disappear after an update. On Android this is exactly what happens if a build is signed with a different key, so the key must never change.
- **A leaked secret.** The signing key, its passwords or any other secret appear in the repo, in build logs or inside a built file. This matters doubly because the repo will become public.
- **Installing something that isn't Songies.** The updater must install only a file it downloaded from the project's own GitHub releases over HTTPS, and must check it before installing (see "Checking the download").
- **A nagging app.** Asking again every launch after the user said "Not now", a check that slows down startup, or an error message on every launch when offline.
- **Breaking the "no idle work" rule more than agreed.** The one startup check is the only exception, with no periodic polling and no background downloads before the user agrees.

## How it works

### Versions and releases

- The version lives in `pubspec.yaml` (`version: X.Y.Z+N`, currently `1.0.0+1`). A release is made by pushing a tag `vX.Y.Z` that matches it. The build number `N` must go up with every release, because Android refuses to install a lower one over a higher one.
  - **My call:** the workflow fails if the tag and `pubspec.yaml` disagree, rather than silently rewriting the version.
  - **My call:** it also fails if `N` isn't higher than the latest published release's `N`. The workflow records `N` in a small `version.json` asset on every release for this check.
- **My call:** one universal APK, not split per CPU type, so the asset name and the update file are always the same one.
- The workflow creates the GitHub Release for that tag and attaches the files listed below. **My call:** release notes are generated from the commits since the last release, and the user can edit them on GitHub afterwards.
  - `songies-X.Y.Z.apk`
  - `songies-X.Y.Z-windows-setup.exe`
  - `songies-X.Y.Z-x86_64.AppImage`
  - `SHA256SUMS` (see "Checking the download")
  - `version.json` (the build number, for the check above)
- **Release notes in the app:** the update prompt shows the version and the first part of the release notes.

### Building on GitHub

- **Workflow:** `.github/workflows/release.yml`, triggered by pushing a `v*` tag. It can also be run by hand, which builds without publishing, so the user can check that builds still work.
- **Jobs** (Flutter version pinned to the one the project uses, currently 3.47.8):
  - **Android (Linux runner):** `flutter build apk --release`, signed with the release key.
  - **Linux (Linux runner):** `flutter build linux --release`, then packed into an AppImage.
  - **Windows (Windows runner):** `flutter build windows --release`, then packed into an installer.
  - **Publish:** waits for all three, writes `SHA256SUMS`, creates the release and uploads everything.
- Tests (`flutter test`) and `flutter analyze` run first. A failing test stops the release.
- **Cost (private repo):** private repos get a monthly allowance of free Actions minutes, and Windows minutes count double. One release should fit comfortably. Public repos are free.

### Android signing

- The user creates one release key (a keystore) once, following a short guide in `docs/releasing.md` that the plan writes.
- The key and its passwords are stored as **GitHub repository secrets** and decoded into the build only during the job. They are never committed, never printed in logs, and never placed in the repo.
- `android/app/build.gradle(.kts)` gets a release signing config that reads them from `key.properties` or from environment variables. Without them, it falls back to the debug key so local builds still work, and it warns loudly that such a build can't update a release install.
- `docs/releasing.md` tells the user to keep a backup of the keystore and passwords somewhere safe outside the repo, and explains that losing them means every phone has to uninstall (losing its library) to move to a new key.
- **The first release is a one-time switch.** The phone's current Songies is a debug-signed build, so moving to the release key needs one uninstall and reinstall.
  - **The user decided:** this is handled with instructions only, with no backup feature. `docs/releasing.md` walks through it: sync the phone to a PC with device sync (Plan 10), uninstall, install the release APK, pair again and sync back.
  - The docs also say what doesn't come back that way: YouTube downloads (re-downloaded where downloads are on), the YouTube sign-in (sign in again), and settings.

### Windows installer

- **My call:** Inno Setup (the main design allowed Inno Setup or MSIX). MSIX needs a trusted signing certificate to install, while Inno Setup doesn't.
- It installs **per user** (into `%LOCALAPPDATA%\Programs\Songies`), so installing and updating need no administrator prompt. It has a fixed app id, so a new version upgrades the existing install in place. The app's data stays in `%APPDATA%\Songies`, where the code already keeps it (`lib/core/paths.dart`).
- **The first time is a one-time switch.** Today the Windows PC runs a loose build folder. The user installs once with the installer, and their data is found automatically because the data folder is unchanged. Then they delete the old folder. `docs/releasing.md` says so.
- It creates Start menu and optional desktop shortcuts and an uninstaller. Uninstalling keeps the user's data in `%APPDATA%\Songies` unless the user ticks a box to remove it.
- **Updating:** the app runs the new installer in silent mode and quits. The installer waits for Songies to close (it can't replace files the running app holds), replaces the files and starts Songies again.
- **Windows SmartScreen:** the installer is unsigned, so Windows may show an "unknown publisher" warning the first time. `docs/releasing.md` and the release notes say how to get past it ("More info", then "Run anyway"). In-app updates may show it too. **My call:** accept this. A paid signing certificate is out of scope.

### Linux AppImage

- The Flutter Linux bundle is packed into a single `x86_64` AppImage, along with what it needs to run on a fresh Fedora/Nobara install.
  - **My call: bundle libmpv and its media libraries** (ffmpeg and friends), which the player needs and which are normally a separate system package.
  - **Don't bundle** the desktop's own pieces: GTK, libsecret and the keyring, D-Bus, and Avahi. The system provides those, and bundling them breaks more than it fixes.
  - **My call: build on an Ubuntu 22.04 runner**, so the AppImage runs on any distro at least that new, which includes every current Fedora/Nobara.
- **Updating:** the app downloads the new AppImage next to the running one (into the same folder, as `.part`), checks it, makes it executable and renames it over the old file. It then starts the new file and quits. The `APPIMAGE` environment variable tells the app where its own file is.
- If the app isn't running from an AppImage (a developer build, for example), or its file can't be replaced (no write permission), the update prompt offers **Open download page** instead.
- **Device sync on Linux** still needs the firewall steps and Avahi described in Plan 10; the AppImage can't change that.

### The in-app updater

- **Where it looks:** the GitHub API's "latest release" for the project's repo, owned by `DenisMartonak`, repo `Songie` (one constant in the code). This is a single anonymous HTTPS request with no token, which is why the repo has to be public.
- **When:**
  - Once, a few seconds after the app opens, so startup isn't slowed. **My call:** at most once every 12 hours, so opening and closing the app repeatedly doesn't make repeated requests.
  - Whenever the user taps **Check for updates** in Settings → About. This also shows the current version.
- **What counts as newer:** the release's version is higher than the running one, and the release has the file for this platform. Drafts and pre-releases are ignored.
- **The prompt:**
  - A dialog: "Songies X.Y.Z is available" with the start of the release notes and **Update now** / **Not now**.
  - **Not now** skips that version at startup. The next newer version asks again, and the Settings button always shows it.
- **Download:** shown with progress and **Cancel**, into the app's own folder. It can continue in the background while the user keeps listening, and asks before installing.
- **Checking the download:**
  - The file's SHA-256 must match its line in the release's `SHA256SUMS`.
  - On Android, the APK's signing certificate must match the installed app's, and its build number must be higher, so it can't be a downgrade.
  - A file that fails a check is deleted, the user is told, and nothing gets installed.
- **Android install permission:** if the user declines "Install unknown apps" for Songies, the app explains why it's needed. It offers to open that setting or the download page instead.
- **Android release build:** keeps the current setup (no code shrinking), so the yt-dlp and Python native parts keep working exactly as they do now.
- **Offline or GitHub unavailable:**
  - At startup nothing is shown.
  - From the button, the user sees "Couldn't check for updates. Check your connection."
- **Wi-Fi only:** the existing Wi-Fi-only download setting (Plan 3) also applies to update downloads on Android. On mobile data the prompt says so and offers **Download anyway**.

### Private repo

While the repo is private, the GitHub API returns "not found" for anonymous requests. The updater treats that the same as "no update": silent at startup, and from the button the message "No updates found." Releases are still built and published. The user downloads them by hand while signed in to GitHub. Nothing has to change in the app when the repo is made public.

### Before making the repo public

`docs/releasing.md` includes a checklist, and the plan includes a scan step the user runs before flipping the repo to public. It scans the whole git history for:
- secrets: keys, passwords, tokens, cookies, keystores, `key.properties`, `.env` files;
- personal data that shouldn't be published.

Anything found is reported with the commit, and the user decides what to do. Rewriting history is never automatic.

**My call on the tool:** a small script in `tool/` that greps the history for known secret patterns and file names, and also runs `gitleaks` when it's installed. Nothing has to be installed for the script to work.

## Constraints

- Earlier rules still hold:
  - tests never touch the real network (the GitHub API is faked);
  - secrets are never logged;
  - the sign-in stays in secure storage;
  - no idle work apart from the one agreed startup check.
- **Android:** installing needs `REQUEST_INSTALL_PACKAGES` and a `FileProvider` to hand the APK to the system installer. The first time, the user may be asked to allow "Install unknown apps" for Songies, and the app explains why.
- The plan checks the existing pinned beta packages (`flutter_inappwebview_*`) and the `flutter_rust_bridge` override build on GitHub's runners exactly as they do locally.
- The Windows build can't run on the user's Nobara PC. Windows packaging is verified on GitHub's Windows runner, and the installer is checked by hand on the user's Windows PC.

## Testing the updater before the repo is public

- **My call:** the repo the updater checks can be overridden at build time (`--dart-define=SONGIES_UPDATE_REPO=owner/repo`).
  - Builds from the release workflow never set it.
  - This lets the user try a real update end to end before going public, by pointing a test build at a public test repo holding two releases.
- Otherwise, the end-to-end checks in the manual checklist are done right after the repo is made public.

## Testing

- **Unit tests:**
  - version comparison;
  - release parsing (picking the right file per platform, skipping drafts and pre-releases);
  - the 12-hour limit and the "Not now" rule;
  - checksum and APK-certificate checks, including rejections;
  - offline and "not found" handling.
- **Widget tests:** the update prompt, the Settings → About section and download progress.
- **Platform install steps** (Android intent, Windows silent installer, AppImage swap) are kept behind small interfaces, so the logic is tested with fakes.
- **The workflow** is checked by running it by hand (build without publishing) and then by one real test release.
- **The manual checklist gets a Plan 11 section:**
  - updating from one release to the next on each platform, with the library intact;
  - the first-time switch from the debug build on the phone;
  - SmartScreen on Windows;
  - the AppImage on a clean Fedora/Nobara install;
  - "Not now";
  - checking with no network.

## Left to the builder

- The exact workflow layout and action versions.
- The AppImage tooling.
- The Inno Setup script details.
- Where downloads are stored.
- The Settings → About layout.
- How the APK signing certificate is read on Android.

All within the rules above.
