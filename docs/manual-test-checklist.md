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

Also check Settings on each platform:
- [ ] Windows: sidebar Settings opens it; folder Rescan / Remove (with confirmation) / Add folder work; Storage shows sizes; Export log opens a save dialog.
- [ ] Android: the Home gear opens it, and Back returns; Export log saves a file you can find in the chosen location.
- [ ] Linux: sidebar Settings opens it; Export log opens a save dialog.

## Known follow-ups

- Remove `dependency_overrides: flutter_rust_bridge` once smtc_windows is rebuilt against frb ≥ 2.13.
