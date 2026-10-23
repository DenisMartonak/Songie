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

## Known follow-ups

- Remove `dependency_overrides: flutter_rust_bridge` once smtc_windows is rebuilt against frb ≥ 2.13.
