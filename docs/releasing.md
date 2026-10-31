# Releasing Songies

A plain-language guide for making a release. Do steps 1 to 3 once. Step 4 is for every release.

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

## 4. Make a release (every time)

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

## 5. First-time switch on the phone

Your current phone app is signed with a debug key, so it cannot be updated by the release APK. Do this once:

1. Sync the phone to a PC with device sync, so the library is safe on the PC.
2. Uninstall Songies on the phone.
3. Install the release APK (`songies-X.Y.Z.apk` from the GitHub release).
4. Pair the phone with the PC again and sync back.

What does not come back: downloads are fetched again (where downloads are on), you sign in to YouTube again, and settings are not carried over. After this, updates install over the top without losing anything.

## 6. First-time switch on Windows

Until now Windows ran from a loose build folder.

1. Run `songies-X.Y.Z-windows-setup.exe`. It installs just for you (no administrator prompt) into `%LOCALAPPDATA%\Programs\Songies`.
2. Your data lives in `%APPDATA%\Songies`, which is unchanged, so the installed app finds it.
3. Check that everything is there, then delete the old loose folder.

Uninstalling keeps your data unless you tick the box to remove it.

## 7. Windows SmartScreen

The installer is not signed with a paid certificate, so Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**. In-app updates may show this too.

## 8. Linux

1. Make the AppImage executable: `chmod +x songies-X.Y.Z-x86_64.AppImage`, then run it. Keep it in a folder you can write to, so in-app updates can replace it. If it cannot be replaced, the app offers "Open download page" instead.
2. Device sync still needs the firewall opened and Avahi running, exactly as described for device sync (the AppImage cannot change that). On Fedora/Nobara, allow the sync port in firewalld and make sure `avahi-daemon` is enabled.

## 9. Before making the repo public

The in-app update check needs a public repo, and a public repo shows the whole git history. So first:

- [ ] Run the history scan script in `tool/` (added in Task 8 of this plan) and read every finding. Nothing is rewritten automatically; you decide.
- [ ] Confirm no `*.jks`, `*.keystore`, `key.properties`, `.env` files, tokens, cookies or passwords appear in any commit.
- [ ] Confirm the four GitHub secrets exist only as secrets, not in any file.
- [ ] Check for personal data you do not want published (names, emails, paths, device names).
- [ ] Back up the keystore (step 2) if you have not already.
- [ ] Only then switch the repo to public. Nothing in the app needs to change.
