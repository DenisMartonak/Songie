# Manual test checklist

Tick items as you verify them on a real device. Do these once playback is reachable from the UI.

## Media controls

Android
- [ ] The notification shows the album art, title and artist, a draggable seek bar, and previous / play-pause / next plus shuffle and repeat buttons.
- [ ] The shuffle and repeat buttons change appearance when toggled (shuffle on; repeat all; repeat one).
- [ ] The first time playback starts on Android 13+, the notification permission prompt appears, and playback is not blocked while it is open.
- [ ] Tapping the notification opens the app on Now Playing (needs the Task 11 router wiring).
- [ ] Lock screen controls work (play/pause, next, previous, seek).
- [ ] A Bluetooth headset play/pause button works.
- [ ] Unplugging wired headphones or disconnecting Bluetooth pauses playback.
- [ ] Paused for 10 minutes, the notification becomes swipe-dismissible.
- [ ] After that, pressing play in the app resumes the same queue and the notification returns.

Windows
- [ ] The media flyout (volume popup) shows the art, title, artist and the previous / play-pause / next controls.
- [ ] Keyboard media keys (play/pause, next, previous) control the app.

Linux (Nobara)
- [ ] The KDE or GNOME media applet shows the art, title and artist, with previous / play-pause / next.
- [ ] Seeking from the applet works, and media keys work through the desktop.
- [ ] The applet's progress bar advances while playing.


## Add music folder

Android
- [ ] Library → + → Add music folder opens the system folder picker.
- [ ] Picking Music adds its MP3s.
- [ ] Picking Downloads shows the "can't be used" message.

## Plan 1 end-to-end

Do each item on every platform listed. Build with `flutter run -d windows`, `flutter run --release -d <android>` and `flutter run -d linux` (Nobara).

1. Add a real music folder with "create playlist" (Your Library, then Add, then Add music folder; or Settings, then Add folder): the playlist appears with art.
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
2. Reorder, remove + undo, and rename in the playlist.
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
3. Play, then next / previous, shuffle and repeat-one.
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
4. Search with an accented artist (e.g. type the name without the accent).
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
5. Delete one MP3 on disk, then rescan (Settings, Rescan): the song shows "File missing", and playback skips it.
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
6. Tick the Media controls checklist above for the platform.
  - [ ] Windows
  - [ ] Android
  - [ ] Linux
7. Android only: screen off for 5 minutes while playing: it is still playing.
  - [ ] Android
8. Idle Windows RAM (Task Manager, paused, window open): record the number in the commit message. Target 150 MB or less.
  - [ ] Windows

Also check these:
- [ ] Android: open a playlist from a Home tile (and from a Search result), press the system Back button: it returns to Home (Search) and does not close the app.
- [ ] Retag an MP3 in an external tagger, then rescan: the song keeps its place in its playlists, shows the new title / artist, and still plays (no "File missing").
- [ ] Android: Locate on a "File missing" song by choosing a folder repairs the song, and the folder does not appear in Settings, Music folders.

Also check Settings on each platform:
- [ ] Windows: sidebar Settings opens it; folder Rescan / Remove (with confirmation) / Add folder work; Storage shows sizes; Export log opens a save dialog.
- [ ] Android: the Home gear opens it, and Back returns; Export log saves a file you can find in the chosen location.
- [ ] Linux: sidebar Settings opens it; Export log opens a save dialog.

## YouTube

Import and sync
- [ ] Import by link: Your Library, Add, Import from YouTube, paste a playlist link. The playlist appears with art and every song.
  - [ ] Android
  - [ ] Windows
  - [ ] Linux
- [ ] Import by Share: in the YT Music app, Share a playlist to Songies. The import dialog opens with the link filled in. (Android)
- [ ] Importing the same playlist again says it already exists and does not add a copy.
- [ ] Sync with YouTube after adding a song on YouTube: the new song is appended at the end.
- [ ] Remove a song on YouTube, then sync: it is flagged as removed. Try both Keep (it stays) and Delete (it goes).
- [ ] Private or deleted videos show as unavailable and are skipped during playback.

Streaming
- [ ] A YouTube song streams and plays with no ads.
- [ ] A YouTube song plays on Android, in both builds (this checks that stream headers reach YouTube without the local proxy, and that release shrinking kept youtubedl-android).
  - [ ] Debug APK
  - [ ] Release APK
- [ ] Tapping a YouTube song shows it as the current song (loading) right away, before the stream starts.
- [ ] The next song starts without a long gap.
- [ ] Wi-Fi only on, mobile data: streaming is blocked with the "Wi-Fi only" message. (Android)
- [ ] Offline: playing a YouTube song shows the offline message and stops.

yt-dlp
- [ ] Settings, Update yt-dlp works on Android.
- [ ] Settings, Update yt-dlp works on desktop.
- [ ] Windows: on a fresh install, Settings, Install yt-dlp downloads it and shows the version. (The install step runs `--version` on `yt-dlp.exe.download` before renaming it; check that this works there and that antivirus doesn't block it.)
- [ ] Windows: Update yt-dlp while a YouTube song is streaming. The update finishes (or fails with a message) and the song keeps playing or stops cleanly.
- [ ] Nobara: "Use system yt-dlp" works with the distro's yt-dlp, and Update explains that the package manager does it.

Windows release build (left for the PC, because Plan 2 was verified on Nobara)
- [ ] `flutter build windows --release` succeeds.
- [ ] Idle RAM (Task Manager, paused, window open) is 150 MB or less. Record the number.

## Plan 3: fixes and downloads

Android downloads
- [ ] Turning on a playlist download shows the notification with "x of y" and a progress bar.
- [ ] Locking the phone mid-download keeps it running.
- [ ] Wi-Fi off with Wi-Fi only on → "Paused — waiting for Wi-Fi", and it resumes when Wi-Fi returns.
- [ ] Airplane mode → paused offline.
- [ ] Finishing posts "Downloaded n songs".
- [ ] Downloaded songs play in airplane mode.

Linux downloads (in-app; only the yt-dlp part was checked headlessly, see PROGRESS.md)
- [ ] Import the known test playlist, turn on Download beside "Sync with YouTube", wait for 3 songs to finish. `.webm`/`.m4a` files exist in `~/.local/share/songies/library/yt/`.
- [ ] Playing a downloaded song uses the file (log line `FileSource`).
- [ ] Turning the download off with **Remove** deletes the files.

All platforms
- [ ] Home/Library always open their root.
- [ ] Skipping shows "Skipped …".
- [ ] Covers are sharp on Now Playing.

## Plan 4: a living UI and themes

Colours, motion and battery
- [ ] Colours follow each new song within a second, smoothly.
- [ ] Skipping fast never shows a skipped song's colours.
- [ ] Paused Now Playing for 5 minutes → the battery/CPU graph is flat (Android) / CPU use < 1 % (desktop task manager).
- [ ] Reduce animations removes motion.

Themes and fonts
- [ ] Importing a font works, and a non-font file is refused.
- [ ] A theme exported on one device imports on another.
- [ ] The three built-ins look as specified.

From the task reviews
- [ ] Outfit and JetBrains Mono show real bold weights.
- [ ] Now Playing: dragging it down shows the app underneath; rotating the phone mid-drag and pressing Back mid-drag freeze nothing; the blur stays smooth while dragging (performance overlay).
- [ ] Playlist page: the header is readable over a pale cover; long titles fit with Android's Large font; nothing sits under a side notch in landscape.
- [ ] Shell: swiping the mini player skips; the bottom-nav icon bounces; the desktop scrubber and volume thicken on hover; sidebar hover shows on a light theme.
- [ ] Themes: make, edit, export and import a theme that uses an imported font; a light theme looks right in dialogs and switches.

## Plan 5: YouTube Music

Search, Home and pages
- [ ] Searching a song and tapping it plays it within about a second, and radio fills the queue.
- [ ] Home shows YouTube Music rows below your library.
- [ ] Artist, album and playlist pages open and play. **Import as playlist** works.
- [ ] A searched song doesn't appear in Library lists but appears in Recents.

Network and settings
- [ ] Wi-Fi only streaming is off after the update. With it on, mobile data blocks streaming but not browsing.
  Upgrade note: someone who had "Wi-Fi only" on before the update will now stream on mobile data, because the new "Wi-Fi only streaming" setting defaults to off. They must turn it on again to keep streaming on Wi-Fi only.
- [ ] With Wi-Fi off and Innertube blocked (a firewall rule), songs still play through yt-dlp.

Consent and recommendations
- [ ] The EU consent sheet appears once.
- [ ] Reset YouTube recommendations works.

## Plan 7: YouTube sign-in

Per platform (Android, Windows, Linux): sign in, check the feed, play a song past 30 s and check the history.
- [ ] Android: Settings → Sign in to YouTube opens Google's page; after signing in, Home shows your rows, and a song played past 30 s appears in your YouTube Music history.
- [ ] Windows: same check through the WebView2 page.
- [ ] Windows: the build succeeds with `desktop_webview_window` registered (it fetches its own WebView2 SDK at configure time, x64/ARM64 only, Flutter 3.44 or later), and Settings sign-in on Windows still opens the WebView2 page (flutter_inappwebview_windows).
- [ ] Windows build needs `nuget.exe` on PATH and the WebView2 runtime.
- [ ] Linux, in-app page: Sign in to YouTube opens the WebKitGTK window; after signing in, Home shows your rows and a played song appears in history.
- [ ] Linux, browser route with Firefox: "Use the YouTube sign-in from my browser" asks first, lists the profile, and signs in.
- [ ] Linux, browser route with a Chromium-family browser (Chrome, Chromium, Brave): same check, including the keyring unlock prompt.
- [ ] If Google says "This browser or app may not be secure", close the page; nothing changes (still signed out, no error, regular feed).
- [ ] Expiry: sign out of Google in a browser, then open Home. Expect the regular feed and one notice ("YouTube sign-in expired — showing the regular feed"), and the Settings row says "Sign in again".
- [ ] Sign out: Home returns to the regular feed; the Settings row goes back to "Sign in to YouTube".
- [ ] A locked keyring on Linux shows the explanation ("Sign-in needs a keyring (KWallet or GNOME Keyring), which isn't available"), and the rest of Settings and the app work.

## Plan 8: lyrics

Phone (Android), desktop Linux and Windows. Where a check says "desktop", do it on both Linux and Windows.
- [ ] A mainstream YouTube song shows timed lyrics, and the current line is highlighted and follows the song (phone: Lyrics tab on Now Playing; desktop: the right-side panel).
- [ ] Tapping a line seeks to it.
- [ ] Scrolling the lyrics by hand pauses following; it resumes after 5 s.
- [ ] A local file with a sidecar `.lrc` next to it uses that file's lyrics, and the credit says "Lyrics from the file".
- [ ] An obscure song shows "No lyrics found" and a Search again button; Search again tries once more.
- [ ] In airplane mode, lyrics you already viewed still show; a song you never opened lyrics for shows "Lyrics need a connection".
- [ ] With reduced motion on, the lyrics jump to the current line instead of scrolling.
- [ ] While paused, nothing moves (no scrolling, no shimmer).
- [ ] Desktop: the lyrics panel stays open when you switch tabs (Home, Library, Search), and the player bar Lyrics button toggles it.
- [ ] Android tablet (or a phone in landscape, 720 dp or wider) and a desktop window under 1000 px: opening the lyrics panel collapses the sidebar to icons, nothing overflows (no yellow-black stripes), and closing it gives the sidebar back.
- [ ] Desktop: the Now Playing dialog has a Lyrics tab.
- [ ] The credit line is right: "Lyrics from LRCLIB", "Lyrics from YouTube Music" (with YouTube's own credit line when given) or "Lyrics from the file".
- [ ] The desktop player bar still fits at a narrow window (about 720 px): the volume slider shrinks and the Lyrics button stays visible.

## Plan 9: listening stats

Phone (Android), desktop Linux and Windows. Where a check says "desktop", do it on both Linux and Windows. The card is "Your listening" on Home; tapping it opens the stats page.
- [ ] Play a song for 1 minute. The card's minutes and plays go up (about 1 minute, 1 play).
- [ ] Pause for a minute. The minutes don't grow while paused.
- [ ] Skip a song after 10 s. The minutes grow but the plays don't.
- [ ] With repeat-one on, let a short song loop twice. That gives 2 plays.
- [ ] On the stats page, switch between 7 days, 1 month, 6 months and 12 months. The numbers change and the chart bars look right (no overflow, the newest bar on the right).
- [ ] Show top 10 works for top artists and for top songs.
- [ ] Tapping a top song plays it.
- [ ] Tapping a top artist opens Search with the artist's name (artist pages aren't linked yet).
- [ ] A song with a featured artist (for example "Artist A, Artist B", or "Artist A feat. Artist B" on a local file) counts for the main artist only.
- [ ] Play a song shorter than 30 s all the way to its end. It counts as 1 play.
- [ ] Play a local file with no artist tag (it shows "Unknown artist"). It is left out of top artists, but its minutes count.
- [ ] Force-quit the app in the middle of a song. At most about 30 s of that song is lost.
- [ ] Phone: the card is compact, and your playlists stay visible on Home without scrolling far.

## Plan 10: device sync

Removed: home-network sync was replaced by cloud sync (see Cloud sync below).

## Plan 11: packaging and in-app updates

Needs a GitHub repo (public, or a public test repo for the test-build item) and two released versions to update between. Version numbers below are examples. See [releasing.md](releasing.md) for how to make a release.
- [ ] The first tagged release: push `v1.0.0`. The workflow run goes green and the Releases page shows five assets: the APK, the Windows setup exe, the AppImage, `SHA256SUMS` and `version.json`.
- [ ] The release APK, installed on a phone from the release page, opens and plays music.
- [ ] The Windows setup exe installs for the current user (no administrator prompt), and Songies starts from the Start menu.
- [ ] The AppImage runs on Linux after `chmod +x`.
- [ ] First-time phone switch from the debug build: sign in and let it sync first, uninstall the debug build, install the release APK, sign in again and let it sync. The library returns; downloads, sign-in and settings need redoing, as the guide says.
- [ ] First-time Windows switch: install the setup exe over a machine that used the loose build folder. The installed app finds the library in `%APPDATA%\Songies`.
- [ ] On mobile data with downloads set to Wi-Fi only: the dialog says "You're on mobile data, and downloads are set to Wi-Fi only." with "Close" and "Download anyway".
- [ ] Update, Android: with release 1.0.0 installed, publish 1.1.0 (higher build number). The app shows "Songies 1.1.0 is available" with "Update now" and "Not now"; Update now downloads it, then "Install now" installs it over the top. The library, playlists and settings are still there.
- [ ] Update, Windows: same check. The installer closes the app, installs silently, and the new version opens by itself. The library is intact.
- [ ] Update, Linux: same check with the AppImage in a writable folder. The app replaces itself and relaunches as the new version. The library is intact.
- [ ] "Not now": on "Songies X.Y.Z is available", tap "Not now". The next start stays quiet about that version. Publish a newer one and the app asks again.
- [ ] Offline start: with no network, starting the app shows nothing about updates. Settings, Check for updates then shows "Couldn't check for updates. Check your connection."
- [ ] Settings, Check for updates when already current: it shows "No updates found."
- [ ] Android: back out of the system install screen. The app does not hang; the dialog still says "Finish installing on the Android screen." with a "Close" button, and you can close it and try the update again (a known rough edge: it may need the download repeated).
- [ ] Windows SmartScreen: the first run of the setup exe may say "Windows protected your PC". More info, then Run anyway, works. The same may appear for an in-app update.
- [ ] Windows uninstall: Uninstall asks "Also delete your Songies library, downloads, settings and sign-in?" (default No). Answering No keeps `%APPDATA%\Songies`. Answering Yes deletes it and `%APPDATA%\com.songies\Songies` (the stored sign-in and the YouTube sign-in browser profile); after reinstalling, the app is signed out. A now-useless Songies entry may remain in Windows Credential Manager.
- [ ] The AppImage on a clean Fedora/Nobara (or one without libmpv installed): it starts and plays music, so libmpv is bundled correctly.
- [ ] The AppImage built by the release workflow on a live Ubuntu session (a USB stick, nothing installed): it starts and plays music, so libcurl (needed by the crash reporter) and libmpv are bundled correctly.
- [ ] After the first release, open Sentry, the project's Settings, then Debug Files: there are uploads for Android, Windows and Linux, all for `songies@X.Y.Z+N`.
- [ ] Crash reports from a tagged release: on an installed release with Send crash reports on, make the app hit an error (for example a crash on Windows or Linux). Within a few minutes the error shows in Sentry, Issues, with release `songies@X.Y.Z+N` and environment `production`.
- [ ] Turn Send crash reports off and cause the same error again: nothing new arrives in Sentry. Turn it back on and the next one arrives.
- [ ] Open one of those reports in Sentry and read the whole event (also the raw JSON, from the "{ }" button): Debug Meta lists only file names such as `songies.exe` or `libmpv.so.2`, never a folder; the user has only an id; and the user name, song titles and file paths appear nowhere.
- [ ] The release workflow run has the artifacts `symbols-android`, `symbols-linux` and `symbols-windows`.
- [ ] AppImage in a read-only folder (for example `chmod a-w` on the folder): an update offers "Open download page" instead of replacing itself.
- [ ] Test build against a public test repo: build with `--dart-define=SONGIES_UPDATE_REPO=<you>/<test-repo>`, put a release with higher version there, and check the app finds and offers it. (A normal build looks at `DenisMartonak/Songie`.)
- [ ] The secret scan before going public: run `tool/scan_secrets.sh` and read every finding. Today it reports 2 known false positives (the plan doc quoting the key pattern, and Chromium's `'peanuts'` constant in `test/innertube/browser_cookies_test.dart`). Anything else is new. Then work through the list in releasing.md section 10.

## Age-restricted songs

Use `S4-2QqwHf5c` ("HOMOŠLERKY (Full Song)").

- [ ] Signed out: playing it skips with "Age-restricted — sign in to YouTube to play it" and a Sign in action; the song is not marked unavailable.
- [ ] Desktop, signed in, Node or Deno on PATH: it plays (log: `stream S4-2QqwHf5c via innertube>yt-dlp+age`).
- [ ] Desktop, signed in, no runtime: picking it asks to download the helper (about 45 MB); Download installs Deno and plays it; Not now skips it. Reaching it by queue advance never asks.
- [ ] Settings shows the helper's state; Remove deletes Songies' Deno.
- [ ] Android, signed in (in-app sign-in): it plays, no prompt.
- [ ] Signed in with an account that can't watch it: "This YouTube account isn't valid for age-restricted songs".
- [ ] Download it (signed in): the download completes.
- [ ] After upgrading, songs previously marked unavailable get one more try (log: `Unflagged N unavailable YouTube songs`).

## Favorites

- [ ] A fresh install shows Favorites first in the library, with a star cover.
- [ ] The star next to the playing song (desktop player bar, phone Now Playing) fills when tapped and the song appears at the top of Favorites.
- [ ] Stars on search results, playlist rows, Home recents, YouTube Music song rows, the queue and stats top songs all toggle.
- [ ] Starring a YouTube Music search result that isn't in the library adds it to the library and to Favorites.
- [ ] The song menu shows Add to Favorites / Remove from Favorites.
- [ ] Favorites has no Rename or Delete; its download switch works.
- [ ] Two devices: star a song on each, sync, both have both; un-star one on one device, sync, it's gone on both, with no conflict prompt.

## Equalizer

- [ ] Settings → Playback → Equalizer lists Off, Bass boost, Vocal, Rock, Pop, Classical, Electronic, Acoustic.
- [ ] Linux: picking Rock while a song plays changes the sound at once; note any gap or click when switching. Off sounds like before.
- [ ] Linux: the preset holds on the next song, after the queue ends and you play again, and after a restart.
- [ ] Windows: the row reads "Not available on Windows yet" (the equalizer is off there until a Windows run proves the filter; see the spec).
- [ ] Android: same, through the phone's equalizer.
- [ ] The preset survives a restart and applies to the next song, a YouTube stream and a downloaded file alike.

## Report a bug

- [ ] A release build (from the workflow) shows Settings → Report a bug; a local debug build without the webhook hides it.
- [ ] Sending with a description under 10 characters is refused; a longer one sends.
- [ ] The report arrives in the Discord channel with the app version, device, log and screenshot.
- [ ] A report that contains @everyone or @here in the description fires no mention or notification.
- [ ] The form cannot be closed while it is sending.

## Accounts

Phone (Android), desktop Linux and Windows. First do the one-time setup in `docs/supabase.md`. Use two test email addresses you can read.
- [ ] Signed out, the app works as before: no prompt at launch, and Settings → Account (the first section) offers Sign up and Log in.
- [ ] Sign up with email, a password of 8+ characters and a free username. A 6-digit code arrives by email; typing it logs you in and the Account section shows your username and email.
- [ ] The username field lowercases as you type, shows "3–20 letters, numbers, _ or .", and says "That username is taken." for a taken name (try your first account's name in a different case).
- [ ] Sign up with a password of 7 characters: refused with "At least 8 characters".
- [ ] Sign up again with the first email: "That email already has an account. Log in, or reset your password." and no code screen.
- [ ] A wrong or expired code: "That code is wrong or has expired."; Send a new code sends one that works.
- [ ] Log in with a wrong password: "Wrong email or password."
- [ ] Log in to an account whose email isn't confirmed yet: the app asks for the code.
- [ ] Forgot password: a code arrives; the code and a new password log you in; the old password no longer works.
- [ ] Change username: the new name shows at once and after a restart; a taken name is refused.
- [ ] Change picture: it shows as a round picture in Settings and (desktop) in the top bar; after another change the old file is gone from the `avatars` bucket in the dashboard. Remove picture brings back the letter circle.
- [ ] Desktop: the top-bar avatar sits right of the search field and left of the window buttons (or at the right end of the search row without the custom title bar), and opens Settings → Account; signed out it is a person icon with a "Log in" tooltip.
- [ ] Log out, then restart: still signed out. Log in, then restart: still signed in.
- [ ] Airplane mode (or the Supabase project paused): the app starts and plays music; account actions say "Couldn't reach the server. Check your connection."
- [ ] Delete account: the confirmation reads "Delete your account? Your username and picture are removed. Your music on this device stays."; afterwards you're signed out, your library is untouched, the user is gone from Authentication → Users, and the username can be signed up again.
- [ ] Database rules (review the migration; the dashboard SQL editor runs as the owner and skips them): a signed-in user can't change someone else's profile or upload outside their own `<user id>/` folder in `avatars`. In the SQL editor, `select public.username_available('somename');` returns only true or false.

## Cloud sync

Two devices (phone and desktop) signed in to the same account, and a second account. First apply `supabase/migrations/20261106120000_cloud_sync.sql` (see `docs/supabase.md`).
- [ ] In the dashboard, Database, Publications: `supabase_realtime` does **not** list `sync_rows`. Storage shows a private `sync-files` bucket (10 MB limit, fonts and images only).
- [ ] Realtime: with both devices open, add a song to a playlist on one; it appears on the other within seconds without a restart. In the dashboard, Realtime, Inspector, join the private channel `sync:<user id>` (as that user): each push shows a `changed` message with only a `server_seq`. Joining another user's `sync:<id>` as yourself is refused.
- [ ] Table Editor, `sync_rows`: after signing in on a device with a library, rows appear for that user only (`user_id` is theirs), one per synced row.
- [ ] Database rules (review the migration; the SQL editor runs as the owner and skips them): a signed-in user can read only their own `sync_rows`, can't insert, change or delete them except through `push_rows`, and can touch only their own `<user id>/` folder in `sync-files`.
- [ ] Upgrade from a version with Sync devices (database schema 8): the app opens with the library, playlists and settings intact; Settings has no Sync devices entry, the desktop sidebar has none, and the old `sync` folder under the app data folder is gone.
- [ ] Delete account: that user's `sync_rows` and `sync-files/<user id>/` folder are gone; the other account's rows stay.

## Known follow-ups

- Remove `dependency_overrides: flutter_rust_bridge` once smtc_windows is rebuilt against frb ≥ 2.13.
