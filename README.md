# Songies

A personal music player for Android, Windows and Linux, built with Flutter.

Plan 1 covers the local library: scan folders of MP3 files (referenced in
place, never copied), playlists, search, a queue with shuffle and repeat, and
media-key / notification / lock-screen controls. Data lives in a local SQLite
database; every row carries sync metadata for the later device-sync plan.

## Development

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows     # or: -d linux, -d <android device>
```

See `docs/manual-test-checklist.md` for the checks that need a real device.
