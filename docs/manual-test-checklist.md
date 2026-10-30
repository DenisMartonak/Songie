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

Phone (Android), desktop Linux and Windows. Open Settings and then Sync devices on both devices before each check: the other device must have Sync devices open, because nothing runs in the background. Back up nothing first, but try the large-library check on a copy if you can.
- [ ] Pair by code, phone and Linux: one device shows a 6-digit code, the other types it. They find each other, pair, and run a first sync.
- [ ] Pair by code, phone and Windows (same check).
- [ ] Pair by code, Linux and Windows (same check).
- [ ] A wrong code: the app says the code was wrong and nothing is paired. After 5 wrong tries the code stops working and you need a new one.
- [ ] An expired code: show a code, wait 5 minutes, then type it on the other device. Pairing fails and you need a new code.
- [ ] Connect by address: type the other device's address and the code. Pairing works, including on Linux without Avahi.
- [ ] After pairing, "Your devices" lists the other device; a later sync is one tap on it.
- [ ] Sync with music playing: playback does not stop or stutter, and the queue stays as it was.
- [ ] A clash on a playlist (rename it on both devices, or edit it on both): the prompt offers Keep this device's, Keep the other's and Keep both. Check each choice leaves the right playlist on both devices after the next sync.
- [ ] Delete a playlist on one device and edit it on the other, then sync. The prompt appears, and each choice does what it says.
- [ ] Changes to different parts of one playlist (a song added on one device, the name changed on the other) combine without asking.
- [ ] A large library's first sync (thousands of songs): it finishes, progress moves, memory stays reasonable and the app stays usable. Cancel part-way and sync again; it picks up.
- [ ] An MP3 added on one device arrives on the other and plays. A font added on one device arrives and can be chosen in Settings. A cover arrives too.
- [ ] The summary after a sync reads sensibly ("1 playlist changed", "N files copied").
- [ ] Forwarding: pair A with B and B with C, sync A and B, then B and C. A's changes reach C without A and C ever meeting.
- [ ] Unpair: the device disappears from Your devices, and the other device can no longer sync with this one until you pair again.
- [ ] Linux firewall: allow port 47823/tcp and the mdns service (for example `sudo firewall-cmd --add-port=47823/tcp --add-service=mdns`, add `--permanent` to keep it). Without them the other devices cannot find or reach the Linux machine; with them they can. Discovery needs Avahi; without it, Connect by address still works.
- [ ] Windows: the first time, Windows may ask to allow private networks. Allow it; sync works.
- [ ] Android: with the app paused (switched away) or the tab hidden, the page stops serving, so another device can't connect; coming back makes it available again. A sync that is running keeps going.
- [ ] Leaving the Sync devices page on any device stops it serving (the other device then says it can't find it).

## Known follow-ups

- Remove `dependency_overrides: flutter_rust_bridge` once smtc_windows is rebuilt against frb ≥ 2.13.
