# Releasing Songies

A plain-language guide for making a release. Do steps 1 to 4 once. Step 5 is for every release.

## 1. Create the signing key (once)

Android only lets an app update over an older copy if both are signed with the same key. So you make one key now and use it forever.

```
keytool -genkeypair -v -keystore songies-release.jks -keyalg RSA -keysize 4096 -validity 36500 -alias songies
```

It asks for a password (twice), then some questions about you (any answers are fine). The key password can be the same as the store password. Write down the alias (`songies`) and both passwords.

Never put `songies-release.jks` inside the repo folder tree you commit. It is git-ignored (`*.jks`, `*.keystore`, `android/key.properties`) as a safety net, but keep it elsewhere anyway.

## 2. Back it up (once)

Copy `songies-release.jks` and the passwords to somewhere safe outside the repo, for example a password manager plus a USB stick or cloud drive you trust.

Why: if you lose the key or the passwords, you can never make an update that installs over the old app. Every phone would have to uninstall Songies (losing its library) to move to a new key. And if the key leaks, anyone could publish fake "updates" that your phone accepts.

## 3. Add the GitHub secrets (once)

Make the text version of the key:

```
base64 -w0 songies-release.jks
```

On GitHub open the repo, then Settings, Secrets and variables, Actions, New repository secret. Add these four:

| Secret | Value |
| --- | --- |
| `SONGIES_KEYSTORE_BASE64` | the long text printed by the command above |
| `SONGIES_KEYSTORE_PASSWORD` | the store password |
| `SONGIES_KEY_ALIAS` | `songies` |
| `SONGIES_KEY_PASSWORD` | the key password |

The release workflow turns the base64 text back into a temporary file during the build and points `SONGIES_KEYSTORE_PATH` at it. You do not set that one yourself on GitHub.

### Building a signed APK on your own PC (optional)

Create `android/key.properties` (git-ignored):

```
storeFile=/full/path/to/songies-release.jks
storePassword=<store password>
keyAlias=songies
keyPassword=<key password>
```

A relative `storeFile` is read from the `android/` folder. Alternatively set the environment variables `SONGIES_KEYSTORE_PATH`, `SONGIES_KEYSTORE_PASSWORD`, `SONGIES_KEY_ALIAS` and `SONGIES_KEY_PASSWORD`. `key.properties` wins if both exist.

With neither, `flutter build apk --release` still works but signs with the debug key and prints "Release build signed with the DEBUG key: it cannot update a release install". Do not hand out such an APK.

## 4. Sentry crash reports (once)

Release builds send anonymous crash reports to Sentry (Settings → Send crash reports, on by default). Without the app's debug symbols, a crash report's stack trace shows only memory addresses. To turn them into function names and line numbers, Sentry needs those symbols, and the workflow uploads them on every release. For that it needs a token.

1. In Sentry open Settings, then Auth Tokens (the page may say Organization Tokens), then Create New Token. Name it `songies-ci`. An organization token already has the scopes the upload needs (`org:ci`: create releases and upload debug files) and knows the Sentry region (EU), so there is nothing else to pick. Copy the token now; Sentry shows it only once.
2. Find the project slug: open the Songies project in Sentry and look at the address bar, for example `https://denis-martonak.sentry.io/projects/songies/`. The part after `projects/` is the slug.
3. On GitHub open the repo, then Settings, Secrets and variables, Actions.
   - On the Secrets tab, New repository secret: `SENTRY_AUTH_TOKEN`, the token from step 1.
   - On the Variables tab, New repository variable: `SENTRY_PROJECT`, the slug from step 2.
4. In Sentry open the project's Settings, then Security & Privacy. These settings also cover native crashes, which the app cannot clean up itself before they are sent.
   - Leave **Store Native Crash Reports** off. Sentry still reads native crash dumps into normal crash reports; it just does not keep the raw dump file, which can hold bits of memory such as song or file names.
   - Turn on **Prevent Storing of IP Addresses**.
   - Under Advanced Data Scrubbing, Add Rule: Method **Replace**, Data Type **Usernames in filepaths**, Source **All fields** (`**`). Save. This hides the user name in any path that still reaches Sentry.

5. Nothing to do for the DSN (the address the app sends reports to). It is written in `.github/workflows/release.yml` as `SONGIES_SENTRY_DSN`, and Sentry shows it under the project's Settings, then Client Keys (DSN). It is public by design (it only lets an app send reports), so it is not a secret. If you ever make a new one in Sentry, change it in the workflow.

What reports and what does not:

- Only a tag push (a real release) builds the app with the Sentry address, so only installed releases send reports. A manual run (Run workflow) and anything you build yourself never send anything.
- If `SENTRY_AUTH_TOKEN` is missing, the release still builds and publishes. Each build job shows the warning "SENTRY_AUTH_TOKEN not set; symbols not uploaded", and crash reports from that release show addresses instead of names. Add the token before the next release. The same goes for a missing `SENTRY_PROJECT` ("SENTRY_PROJECT not set; symbols not uploaded").

### Reading a stack trace from the log

Release builds are made with `--split-debug-info`, so a stack trace in the app's own log (Settings, Export log) shows memory addresses instead of function names. Crash reports in Sentry are decoded by Sentry itself; this is only for the log.

1. Find the release's workflow run on GitHub (Actions, Release, the run for the tag) and download the artifact for the platform: `symbols-android`, `symbols-linux` or `symbols-windows`. GitHub keeps them for 90 days. After that, download the same files from Sentry: the project's Settings, then Debug Files.
2. Copy the trace from the log into a file, for example `trace.txt`, from the line starting with `*** *** ***` to the last `#` line.
3. Run `flutter symbolize -i trace.txt -d <file>.symbols` with the symbols file for the device's CPU, for example `app.android-arm64.symbols` for most phones, `app.linux-x64.symbols` or `app.windows-x64.symbols`. It prints the trace with function names and line numbers.

### Building for Linux on your own PC

The crash reporter needs the libcurl headers to build. Install them once: `sudo dnf install libcurl-devel` (Fedora/Nobara) or `sudo apt install libcurl4-openssl-dev` (Debian/Ubuntu). The workflow installs them on GitHub by itself.

## 4b. Bug reports (once)

The Report a bug form in Settings sends a report to a Discord channel through a webhook. The webhook address is a secret: anyone who has it can post to the channel. It is never in the repo.

1. In Discord open the channel for reports, then Edit Channel, Integrations, Webhooks, New Webhook. Copy the webhook URL.
2. On GitHub open the repo, then Settings, Secrets and variables, Actions, New repository secret: `SONGIES_BUG_WEBHOOK`, the URL from step 1. (Already done for this repo.)
3. Every build the workflow makes (a tag push and a manual run) gets the address. A build without the secret, and anything you build yourself, hides Report a bug.
4. If the address leaks or the channel gets spammed: delete the webhook in Discord, make a new one, update the `SONGIES_BUG_WEBHOOK` secret, and make a new release. Old installs keep the old address and stop working until people update.

## 5. Make a release (every time)

1. Pick the new version, for example `1.1.0`.
2. The version is written in two places. Change both:
   - `version:` in `pubspec.yaml`, for example `version: 1.1.0+2`
   - `appVersion` in `lib/core/app_version.dart`, for example `'1.1.0'`
3. The number after the `+` is the build number. It must go up on every release (1, 2, 3, ...). Android refuses to install a lower one over a higher one, and the workflow fails if it did not go up.
4. Commit and push the change.
5. Tag and push the tag. The tag must be `v` plus the version exactly:
   ```
   git tag v1.1.0 && git push origin v1.1.0
   ```
6. GitHub builds the APK, the Windows installer and the Linux AppImage, then publishes them on the Releases page. If the tag and `pubspec.yaml` disagree, the workflow fails on purpose; fix the version and tag again.

### When something goes wrong

- **First-ever run:** do a manual build first (Actions tab, the release workflow, Run workflow). It builds everything without publishing. Once that is green, push a throwaway tag (for example `v0.0.1-test`, then delete the release and tag afterwards) before the real one.
- **A test fails in CI:** the listening-stats timing test is flaky. If it is the only failure, re-run the failed job.
- **`publish` fails after the release was created:** delete that release on the Releases page (keep the tag), then re-run the workflow. A half-made release blocks the re-run.

## 6. First-time switch on the phone

Songies needs Android 8.0 or newer (the crash reporter requires it).

Your current phone app is signed with a debug key, so it cannot be updated by the release APK. Do this once:

1. Sync the phone to a PC with device sync, so the library is safe on the PC.
2. Uninstall Songies on the phone.
3. Install the release APK (`songies-X.Y.Z.apk` from the GitHub release).
4. Pair the phone with the PC again and sync back.

What does not come back: downloads are fetched again (where downloads are on), you sign in to YouTube again, and settings are not carried over. After this, updates install over the top without losing anything.

## 7. First-time switch on Windows

Until now Windows ran from a loose build folder.

1. Run `songies-X.Y.Z-windows-setup.exe`. It installs just for you (no administrator prompt) into `%LOCALAPPDATA%\Programs\Songies`.
2. Your data lives in `%APPDATA%\Songies`, which is unchanged, so the installed app finds it.
3. Check that everything is there, then delete the old loose folder.

Uninstalling asks "Also delete your Songies library, downloads, settings and sign-in?". The default is No, which keeps your data for a later reinstall; Yes deletes `%APPDATA%\Songies` and the sign-in folder `%APPDATA%\com.songies\Songies` (the stored sign-in and the YouTube sign-in browser profile). A Songies entry may remain in Windows Credential Manager; it only held the key for the deleted sign-in, so it is useless and safe to remove by hand.

## 8. Windows SmartScreen

The installer is not signed with a paid certificate, so Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**. In-app updates may show this too.

## 9. Linux

1. Make the AppImage executable: `chmod +x songies-X.Y.Z-x86_64.AppImage`, then run it. Keep it in a folder you can write to, so in-app updates can replace it. If it cannot be replaced, the app offers "Open download page" instead. An in-app update swaps the new version in under the old file name, so `songies-1.0.0-x86_64.AppImage` may hold 1.1.0 afterwards; Settings → About shows the real version.
2. Device sync still needs the firewall opened and Avahi running, exactly as described for device sync (the AppImage cannot change that). On Fedora/Nobara, allow the sync port (TCP 47823) and mDNS (UDP 5353, for discovery) in firewalld, for example `sudo firewall-cmd --add-port=47823/tcp --add-service=mdns` (add `--permanent` to keep it), and make sure `avahi-daemon` is enabled.

## 10. Before making the repo public

The in-app update check needs a public repo, and a public repo shows the whole git history. So first:

- [ ] Run the history scan: `tool/scan_secrets.sh` (from anywhere inside the repo; it needs bash and GNU grep). It reads the whole git history and prints each finding as a commit, a path and a pattern name, with only the first 4 characters of any match. It exits 0 when clean and 1 when it found something. Nothing is rewritten automatically; you decide.
- [ ] Expect exactly 2 known false positives at the moment: the plan document quotes the private-key pattern, and Chromium's public `'peanuts'` cookie constant appears in `test/innertube/browser_cookies_test.dart`. Anything else is new and needs a look.
- [ ] Confirm no `*.jks`, `*.keystore`, `key.properties`, `.env` files, tokens, cookies or passwords appear in any commit.
- [ ] Confirm the five GitHub secrets (the four signing secrets and `SENTRY_AUTH_TOKEN`) exist only as secrets, not in any file.
- [ ] Check for personal data you do not want published (names, emails, paths, device names).
- [ ] Back up the keystore (step 2) if you have not already.
- [ ] Only then switch the repo to public. Nothing in the app needs to change.
