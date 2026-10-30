# Songies

A personal music player for Android, Windows and Linux, built with Flutter.

Plan 1 covers the local library: scan folders of MP3 files (referenced in
place, never copied), playlists, search, a queue with shuffle and repeat, and
media-key / notification / lock-screen controls. Data lives in a local SQLite
database; every row carries sync metadata for the later device-sync plan.

## Syncing devices

Songies can keep your library, playlists and settings the same on your phone
and computers, with no account or cloud. Open Settings, then Sync devices, on
both devices. One shows a 6-digit code and the other types it. After that,
syncing is one tap. Both devices must have Sync devices open at the time, and
they must be on the same network. Your music files are copied across too.

On Linux, allow port 47823/tcp and the mdns service in the firewall, and have
Avahi installed so devices can find each other; without Avahi you can still use
Connect by address. On Windows you may be asked to allow private networks. On
Android, sync is available only while the app is open on that page.

## Development

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows     # or: -d linux, -d <android device>
```

See `docs/manual-test-checklist.md` for the checks that need a real device.
