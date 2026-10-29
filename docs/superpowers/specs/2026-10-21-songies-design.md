# Songies — Design Spec

**Date:** 2026-10-21
**Status:** Draft, awaiting review
**Owner:** personal project (single user)

## 1. Summary

Songies is a personal music player for **Android (sideloaded APK), Windows and Linux (Fedora/Nobara)**. It plays local MP3s and YouTube Music playlists (imported by link, streamed ad-free or downloaded via yt-dlp), keeps imported playlists in sync with YouTube on demand, and syncs the whole library between the user's devices over the local network. The UI is Spotify-leaning, with a theme engine (colors, fonts, corner roundness, follow-album-cover) inspired by Limusic. It must stay light on RAM/CPU on PC and on battery on the phone.

## 2. Goals and non-goals

### Goals
- Import public/unlisted YouTube Music playlists by pasting a link (or Android Share).
- "Sync with YouTube" button per imported playlist: append new songs, flag removed ones.
- Create playlists from local `.mp3` files.
- Stream YouTube tracks ad-free; download playlists for offline via yt-dlp.
- Two-way LAN sync of playlists, themes, local MP3s and imported fonts between any pair of the user's devices.
- Spotify-leaning UI with a saveable, syncable theme engine.
- Synced lyrics from free sources.
- Low idle footprint: nothing runs in the background except playback.

### Non-goals (v1)
- iOS / macOS builds; Play Store / Microsoft Store distribution.
- YouTube account sign-in, private playlists, "Liked Music".
- Searching the YouTube catalog (search covers the user's own library only).
- Writing changes back to YouTube.
- Desktop mini player, Last.fm/ListenBrainz scrobbling, Discord presence, music videos.
- Cloud/internet sync between devices (LAN only).
- Transcoding to MP3 / ffmpeg.

## 3. Decisions log

| Topic | Decision |
|---|---|
| Audience | Single user, sideloaded APK + desktop builds |
| Platforms | Android, Windows, Linux (AppImage) |
| Framework | Flutter (one codebase) |
| YT access | Public/unlisted playlist links only, no sign-in |
| YT sync semantics | Append new songs; flag songs missing on YT as `removed_on_yt` (user decides) |
| Imported playlists | Fully editable locally; sync only appends and never undoes user edits |
| User-deleted YT songs | Never re-added (tracked in `yt_seen`) |
| Device sync payload | Playlist data + themes + local MP3 files + imported fonts. YT audio is **not** transferred; each device downloads its own |
| Conflict handling | Two-way auto merge; prompt once per playlist on true conflicts |
| Device topology | Any device can sync with any paired device |
| Audio format | Native YT Opus (~130–160 kbps), m4a fallback, no conversion |
| Playing undownloaded YT song | Stream it (fresh URL via yt-dlp) |
| Download toggle | Per playlist, **per device** (not synced) |
| Visual direction | Spotify-leaning layout + theme engine (Limusic-style) |
| Lyrics | Yes: local `.lrc` / embedded tags, then LRCLIB |
| Mini player, scrobbling | No |

## 4. Architecture

```
┌──────────────────── UI (Flutter widgets) ────────────────────┐
│ Home · Search · Library · Playlist · Now Playing · Lyrics    │
│ Sync Devices · Theme Editor · Settings                       │
└──────────────────────────────┬───────────────────────────────┘
                               │ Riverpod providers
┌──────────────────────────────┴───────────────────────────────┐
│ Core services (pure Dart, platform-agnostic, unit-testable)  │
│  LibraryService   playlists, tracks, entries, local folders  │
│  YtImportService  import + sync-with-YouTube diff            │
│  StreamResolver   videoId → short-lived audio URL (cached)   │
│  DownloadService  queue, progress, retry, pause/resume       │
│  PlayerService    queue, shuffle, repeat, gapless prefetch   │
│  LyricsService    local → LRCLIB lookup, cache               │
│  ThemeService     themes, fonts, album-color extraction      │
│  PeerSyncService  discovery, pairing, change exchange, merge │
└───────┬──────────────────┬──────────────────┬────────────────┘
        │                  │                  │
┌───────┴──────┐  ┌────────┴────────┐  ┌──────┴───────────────────┐
│ SQLite       │  │ YtDlp adapter   │  │ Audio adapter            │
│ (drift)      │  │ Android:        │  │ Android: just_audio      │
│              │  │  youtubedl-     │  │  (ExoPlayer) +           │
│              │  │  android via    │  │  audio_service           │
│              │  │  platform chan. │  │ Desktop: just_audio_     │
│              │  │ Desktop:        │  │  media_kit (libmpv)      │
│              │  │  bundled yt-dlp │  │  + MPRIS (Linux) /       │
│              │  │  binary         │  │  SMTC (Windows)          │
└──────────────┘  └─────────────────┘  └──────────────────────────┘
```

Principles:
- Platform differences live **only** in the yt-dlp and audio adapters (plus file-picker/permissions glue). Everything above is shared Dart.
- Every core service depends on interfaces (`YtDlp`, `AudioBackend`, `Clock`, `HttpClient`, `FileStore`) so tests can inject fakes.
- **No idle work:** no polling, no background sync, no always-on server. YouTube sync, device sync and lyrics fetches happen only on user action. The LAN server runs only while the Sync Devices screen is open.
- Android playback runs in a foreground media service (`audio_service`) so it survives screen-off. Desktop: closing the window either quits or minimizes to tray (setting; default quit).

### Key packages (expected; confirm versions at plan time)
`flutter_riverpod`, `drift` + `sqlite3_flutter_libs`, `just_audio`, `just_audio_media_kit`, `audio_service`, `audio_service_mpris` (Linux), `smtc_windows` (Windows), `bonsoir` (mDNS), `palette_generator` (cover colors), an ID3 tag reader (e.g. `audio_metadata_reader`), `file_picker`, `path_provider`. Android native: `youtubedl-android` (Kotlin, via platform channel).

### Storage layout
- Database: `<appData>/songies.db`
- YouTube audio: `<appData>/library/yt/<videoId>.<opus|m4a>`
- Local MP3s received via device sync: `<appData>/library/local/<sha256>.mp3`
- Local MP3s the user adds are **referenced in place** (no copy). On Android, via the system picker with persisted access (or `READ_MEDIA_AUDIO`).
- Artwork cache: `<appData>/art/<hash>.jpg` (downscaled to ≤ 512 px)
- Imported fonts: `<appData>/fonts/<sha256>.<ttf|otf>`
- Desktop yt-dlp binary: `<appData>/bin/yt-dlp[.exe]`
- `<appData>` = app-specific storage (Android `getExternalFilesDir`, Windows `%APPDATA%\Songies`, Linux `~/.local/share/songies`).

## 5. Data model

### Synced tables
Every synced row has: `id` (UUID v4), `clock` (HLC string, see §5.2), `origin_device` (device id), `deleted` (bool tombstone), `local_seq` (int, see §5.2).

| Table | Fields (besides common) |
|---|---|
| `tracks` | `source` (`yt`/`local`), `yt_video_id?`, `title`, `artist`, `album?`, `duration_ms`, `artwork_ref?`, `file_hash?` (sha256, local only), `unavailable` (bool) |
| `playlists` | `name`, `cover_ref?`, `source` (`local`/`yt`), `yt_playlist_url?`, `last_yt_sync_at?` |
| `playlist_entries` | `playlist_id`, `track_id`, `position` (fractional index string), `status` (`active`/`removed_on_yt`), `kept` (bool: user chose to keep despite removal on YT), `added_at` |
| `yt_seen` | `playlist_id`, `video_id` (unique pair) |
| `themes` | `name`, `spec_json` (see §9) |
| `fonts` | `family`, `file_hash`, `ext` |
| `lyrics` | `track_id`, `kind` (`synced`/`plain`/`none`), `body`, `source`, `fetched_at` (synced so devices don't refetch) |

Identity rules:
- A YouTube track is unique by `yt_video_id`. A local track is unique by `file_hash`. Inserting a duplicate reuses the existing track row, so the same MP3 added on two machines dedupes.

### Device-local tables (never synced)
| Table | Fields |
|---|---|
| `local_files` | `track_id`, `path`/`uri`, `state` (`none`/`queued`/`downloading`/`done`/`failed`), `bytes`, `error?` |
| `playlist_device_prefs` | `playlist_id`, `download_enabled` |
| `library_folders` | `path`/`uri`, `last_scan_at` |
| `peers` | `device_id`, `name`, `cert_fingerprint`, `pair_key`, `last_sent_seq`, `last_received_seq`, `last_sync_at` |
| `settings` | key/value: active theme id, wifi-only, close-to-tray, port, etc. |
| `stream_cache` | `video_id`, `url`, `expires_at` (in-memory is acceptable) |

### 5.1 Ordering
`position` is a fractional index string (lexicographically ordered; inserting between `a` and `b` yields a key between them). Appends generate a key after the current max. Reorders change only the moved entry's key, so concurrent reorders/inserts on different devices merge without renumbering.

### 5.2 Clocks and change tracking
- **HLC (hybrid logical clock):** `"<wall_ms>-<counter>-<device_id>"`, totally ordered. Updated on every local write and advanced past any received clock. Used for last-writer-wins.
- **`local_seq`:** a per-device monotonically increasing integer assigned whenever a row is written locally, **including rows applied from a peer**. "Changes since last sync with peer P" = rows with `local_seq > peers[P].last_sent_seq`. This ensures changes received from device C are forwarded when syncing with B (transitive propagation).
- **Content hash:** each row's syncable fields hash to a short digest used to detect "same change arrived from both sides".

## 6. YouTube import, sync and streaming

### 6.1 Import
1. Input: pasted URL (`music.youtube.com/playlist?list=…` or `youtube.com/playlist?list=…`), or Android Share intent from the YT Music app. Validate and extract the `list` id.
2. Run `yt-dlp --flat-playlist -J <url>` through the adapter. Parse entries: `id`, `title`, `channel`/`uploader`, `duration`, thumbnails.
3. Clean metadata: strip a trailing ` - Topic` from channel names to get the artist. Use the square YT Music thumbnail if present, otherwise center-crop 16:9 to square. Cache artwork ≤ 512 px.
4. Create the `playlists` row (`source=yt`), the `tracks` (dedupe by video id), and `playlist_entries` in YouTube order. Insert every id into `yt_seen`.
5. Full per-track metadata (`artist`, `track`, `album` fields from yt-dlp's YT Music extractor) replaces the rough values when the track is downloaded or first streamed.

### 6.2 Sync with YouTube (button per YT playlist)
Fetch the current id list (same flat call), then in one transaction:
- **New:** ids not in `yt_seen` for this playlist → append entries at the end (YouTube's relative order among them), add to `yt_seen`. If the playlist has downloads enabled on this device, queue them.
- **Gone:** entries with `status=active` and `kept=false` whose video id isn't in the fetched list → `status=removed_on_yt`.
- **Back:** entries with `status=removed_on_yt` whose id reappears → `status=active`.
- Entries the user deleted are tombstoned and their ids remain in `yt_seen`, so they are **never re-added**.
- User reorders/additions are untouched. Update `last_yt_sync_at`.
- Entries with `kept=true` are never flagged again.
- UI: removed songs render greyed with a "removed on YT" tag and the actions **Delete** (tombstone the entry) and **Keep** (set `status=active`, `kept=true`).

### 6.3 Streaming
- Tapping an undownloaded YT track → `StreamResolver` runs `yt-dlp -f "bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio" -g <id>` and caches the URL until its `expire` parameter (minus 10 min margin).
- `PlayerService` resolves the **next** track's URL ~20 s before the current one ends, for a gapless transition.
- If **Wi-Fi only** is on and the device is on a metered network, streaming is blocked with an inline "Wi-Fi only" notice.
- No ads: the raw media stream is played directly. (This bypasses YouTube's player and is against YouTube's ToS. Accepted for personal use.)

## 7. Downloads

- Format selector: `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`. No post-processing, no ffmpeg.
- Output: `<appData>/library/yt/<videoId>.<ext>`, written to `.part` and renamed on completion. yt-dlp's `--continue` handles resume.
- Queue concurrency: 2 on Android, 3 on desktop. FIFO by request, per-track progress, per-playlist aggregate ring.
- Toggle: "Download" per playlist, stored in `playlist_device_prefs` (device-local). Turning it off offers to delete that playlist's files that no other downloaded playlist references.
- Wi-Fi only (Android default **on**): the queue pauses on metered networks.
- Storage readout per playlist and total in Settings.

### Failure handling
| Failure | Behavior |
|---|---|
| Video private/removed/region-blocked | Mark track `unavailable`, skip, continue queue |
| HTTP 429 / throttling | Pause queue, exponential backoff (30 s → 10 min), resume |
| Network lost | Pause; resume on connectivity change |
| Extractor error (yt-dlp outdated) | Mark failed, show banner "Downloads failing — update yt-dlp?" |
| Disk full | Pause queue, show error |

### yt-dlp updates
- Settings → **Update yt-dlp**. Android: `youtubedl-android`'s updater. Desktop: download the latest release binary for the platform from the official `yt-dlp/yt-dlp` GitHub releases, verify against the release's `SHA2-256SUMS`, and replace atomically.
- Linux: if the user prefers, a setting points to the system `yt-dlp` instead of the bundled one.

## 8. Device sync (LAN)

### 8.1 Discovery
- While the **Sync Devices** screen is open, the app starts an HTTPS server (default port 47823, falls back to a free port) and advertises `_songies._tcp` via mDNS (`bonsoir`) with TXT `id`, `name`, `port`. It also browses for other devices.
- Closing the screen stops the server and advertisement.
- Fallback: manual "Connect by IP:port".
- First-run help: Windows firewall prompt; on Fedora/Nobara the screen shows the `firewall-cmd` command to open the port and mDNS.

### 8.2 Identity and pairing
- On first launch each device generates a `device_id` (UUID) and a self-signed TLS certificate/key (stored in app data).
- **Pairing (once per pair):**
  1. Device A taps "Pair new device" → shows a 6-digit code (valid 2 min).
  2. On device B the user picks A from the discovered list and enters the code.
  3. B connects over TLS (A's cert not yet trusted) and sends `{B_id, B_name, B_cert_fp, nonce_B, HMAC(code, A_fp‖B_fp‖nonce_B)}`.
  4. A verifies the HMAC (binding both certificate fingerprints to the code defeats a MITM without the code), replies with its own HMAC proof plus a random 32-byte `pair_key`.
  5. Both store the peer's `cert_fingerprint` and `pair_key`.
  6. 5 failed attempts invalidate the code.
- After pairing: connections use TLS with the **pinned** peer certificate, and every request carries an HMAC (using `pair_key`) over method, path, timestamp and body hash. Requests older than 60 s are rejected.
- Settings lists paired devices with **Unpair**.

### 8.3 Sync run (either side initiates; the initiator is "I", the other "R")
1. **Hello:** exchange ids, app/schema versions. Abort with a clear message if schemas are incompatible.
2. **Pull:** I requests R's changes since I's stored `peers[R].last_received_seq`, and R returns its rows with a higher `local_seq`, paginated. I computes its own outgoing set (rows with `local_seq > last_sent_seq[R]`).
3. **Merge (on I):**
   - Row only in one set → take it.
   - Row in both sets with equal content hash → no-op.
   - Row in both with different content:
     - `playlists` / `playlist_entries` → **conflict**, grouped per playlist.
     - `tracks`, `themes`, `fonts`, `lyrics`, `yt_seen` → last-writer-wins by HLC, silently. (Track metadata isn't user-editable in v1. `yt_seen` is a set, so the union always wins.)
   - Deletion vs edit on the same playlist → conflict.
   - Additions from both sides never conflict.
4. **Resolve:** I shows one prompt per conflicting playlist: **Keep this device's / Keep \<peer\>'s / Keep both** (keep both = the peer's version becomes a new playlist "\<name\> (from \<peer\>)" with new ids).
5. **Apply:** I sends the merged result for R to apply. Each side applies in a single DB transaction and assigns new `local_seq`. Watermarks advance **only after both sides confirm**. An interrupted sync leaves both unchanged, and rerunning is safe (merge is idempotent).
6. **Files:** each side lists the `file_hash`es it needs (local tracks/fonts referenced but absent). Files stream over `GET /files/<sha256>` with Range support, are written to `.part`, hash-verified, then renamed. Progress shows in the UI and can be cancelled.
7. **After sync:** each device queues YouTube downloads for playlists that have downloads enabled **on that device**.

### 8.4 Protocol surface (HTTPS, JSON)
`POST /pair/start`, `POST /pair/confirm`, `GET /hello`, `GET /changes?since=<seq>&cursor=…`, `POST /apply`, `POST /commit`, `GET /files/<sha256>`. All JSON bodies include a `schema_version`.

## 9. Themes

### Theme spec (`themes.spec_json`)
```json
{
  "base": "charcoal | black | light",
  "background": "#121212",
  "surface": "#2a2a2a",
  "text": "#ffffff",
  "accent": "#1db954",
  "followCover": true,
  "glowStrength": 0.65,
  "cornerRadius": 12,
  "fontFamily": "Outfit",
  "fontFileHash": null,
  "fontScale": 1.0,
  "blurNowPlaying": true
}
```
- Built-in themes: **Default** (charcoal, `#1db954`, Inter, radius 6), **Album glow** (followCover, radius 12, Outfit), **Terminal** (black, `#00e5ff`, JetBrains Mono, radius 0). Built-ins are read-only, and editing one creates a copy.
- Bundled fonts: Inter, Outfit, JetBrains Mono (OFL licensed). Users can import `.ttf`/`.otf`. The file is copied to `<appData>/fonts/`, registered at runtime with `FontLoader`, and synced by hash.
- **Follow cover:** `palette_generator` runs once per track on the downscaled artwork. The result (dominant + vibrant colors) is cached in memory and on disk, so a track's colors are never computed twice. Accent, header glow, mini-player tint and Now Playing background derive from it, and text contrast is checked (WCAG AA against the background, falling back to white/black text).
- Blur is optional, because it's the most expensive effect on low-end phones.
- Theme editor: base, background/surface/text/accent pickers (presets + custom), follow cover, glow strength, corner radius, font (bundled/imported), font scale, blur toggle. Actions: Duplicate, Export (`.songies-theme.json`, font embedded as base64 if imported), Import, Save. Live preview while editing.
- The active theme is device-local (`settings`). The theme list syncs.

## 10. Lyrics

Replaced by 2026-10-29-songies-lyrics-design.md

- A Lyrics tab next to Queue on Now Playing (phone). On desktop, a right-side panel toggled from the player bar.
- Lookup order, stopping at the first hit:
  1. Local track: a sidecar `<same name>.lrc` next to the file, then embedded `SYLT`/`USLT` ID3 frames.
  2. LRCLIB `GET https://lrclib.net/api/get?artist_name=&track_name=&album_name=&duration=` (duration in seconds; accept a match within ±2 s). Send the `User-Agent: Songies/<version>` header as LRCLIB asks.
  3. LRCLIB `/api/search` fallback, filtered by duration ±2 s.
  4. Prefer `syncedLyrics`, otherwise `plainLyrics`, otherwise `kind=none`.
- Fetched only when the tab/panel is opened (and the next track is prefetched only if the panel is open). Results, including "none", are cached in `lyrics` and synced. A "none" result is retried after 30 days or by a manual "Search again".
- Synced view: the current line is highlighted and auto-scrolled, and tapping a line seeks to it. Manual scrolling pauses auto-scroll for 5 s.

## 11. UI

Layout is fixed and Spotify-leaning; themes change only colors, fonts, radius and effects.

**Phone (bottom nav: Home · Search · Library)**
- *Home:* greeting + header glow, 2×N quick-access tiles (recent playlists), "Your playlists" cards with a download badge/progress ring, "Recently played".
- *Search:* local library search (songs, artists, playlists). Instant filtering, using SQLite FTS5.
- *Library:* playlists list with filter chips (All · YouTube · Local · Downloaded) and a "+" menu: New playlist, Import from YouTube, Add music folder.
- *Playlist:* hero (cover, name, source, count, duration, offline size, last YT sync), actions (Play, Shuffle, **Sync with YouTube** for YT playlists, **Download** toggle, ⋯). Track rows with drag-to-reorder, swipe actions, and the "removed on YT" state.
- *Bottom nav:* Spotify-style tabs, each an icon above its label (Home · Search · Library).
  - Active tab: white label, and either the filled icon (Home = filled house) or a bolder stroke (Search magnifier, Library "books on a shelf").
  - Inactive tabs: grey outline icons.
  - The nav sits on a gradient fade into the background.
- *Mini-player:* floats above the nav with an ~8 px gap. It's tinted by theme/cover, has a thin progress line, and expands on tap.
- *Now Playing:* blurred cover background, large art, title/artist, downloaded indicator, scrubber, shuffle/prev/play/next/repeat, Queue and Lyrics tabs. Swipe down to collapse.
- *Sync Devices, Theme Editor, Settings:* reached from the Home header avatar/gear.

**Desktop (Windows/Linux)**
- Custom title bar with search (Ctrl+K).
- Left sidebar: Home, Search, Sync devices, then the Library list (collapsible to icons).
- Main pane: same pages as the phone, with wider track tables (#, Title/Artist, Album, Duration).
- Bottom player bar: now playing (left), transport + scrubber (center), Lyrics, Queue, volume (right).
- Media keys via SMTC (Windows) / MPRIS (Linux). Keyboard: Space play/pause, Ctrl+←/→ prev/next.

**System media controls ("now playing" notification)**
- **Android:** a persistent media notification while a song is playing or paused, using `audio_service` with a MediaSession, like Spotify's. It shows:
  - album art, title and artist, with the system tinting the card from the art on Android 12+
  - a seek bar you can drag
  - Previous · Play/Pause · Next, plus Shuffle and Repeat as custom actions (Android 13+ shows these in the expanded controls and Quick Settings media player)
  - Tap opens Now Playing.
  - The same controls appear on the **lock screen**, in the Quick Settings media panel, and work from **Bluetooth/wired headset buttons**. Headphones unplugging or Bluetooth disconnecting pauses playback.
  - After 10 minutes paused, the service stops and the notification becomes dismissible, so nothing stays alive while idle. Pressing play on the headset or lock screen within that window resumes playback.
- **Windows:** SMTC integration. Art, title, artist and prev/play/next appear in the volume/media flyout and on the lock screen, and the keyboard media keys control the app.
- **Linux:** MPRIS integration. KDE Plasma's media applet and GNOME's top-bar media controls show art, title and artist with prev/play/next and seeking. Media keys work through the desktop environment.
- Metadata and artwork update on every track change. Artwork is passed from the local art cache (no network fetch).

**Feedback states:** skeleton loaders on import, inline progress on sync/download, snackbars for errors with a Retry action, empty states with a primary action (e.g. "Import a YouTube playlist").

## 12. Error handling (cross-cutting)

- All service operations return typed results (`Ok` / `Failure(kind, message)`). The UI maps failure kinds to user-facing messages. There are no silent catch-alls.
- Long operations (import, YT sync, downloads, device sync, file transfer) are cancellable and report progress through streams.
- **DB:** all multi-row changes in transactions, and migrations are versioned in drift with tests.
- **Invalid YT URL / playlist not found / private:** clear message, nothing written.
- **Missing local file** (moved/deleted): the track shows "file missing" with a **Locate** action. The track is skipped during playback.
- **Android:** if battery optimization kills playback, the app suggests exempting it (with a link to the system setting).
- **Logging:** a rolling local log file (≤ 2 MB), viewable/exportable from Settings for debugging.

## 13. Testing

- **Unit (pure Dart, fast):**
  - YT sync diff: new, gone, back, user-deleted never returns, user order preserved
  - fractional index generation
  - HLC ordering/advancement
  - merge rules and conflict grouping
  - `local_seq` transitive propagation (A→B→C)
  - pairing HMAC verification
  - lyrics matching (duration tolerance, fallback order)
  - LRC parsing
  - theme spec validation and contrast fallback
- **Integration:**
  - drift DB against an in-memory SQLite
  - `FakeYtDlp` adapter returning canned JSON fixtures (no network in tests)
  - `FakeAudioBackend` for player-queue behavior
- **Two-instance sync tests:** spin up two `PeerSyncService`s with separate DBs on localhost and run full pair → sync → conflict → resolve → file transfer scenarios.
- **Widget tests** for key screens (playlist page states, theme editor live preview).
- **Manual test checklist per release:** real import of a known public playlist, download with Wi-Fi-only on and off, phone↔Windows and phone↔Nobara sync, media keys on each OS, background playback with the screen off, notification/lock-screen/Bluetooth-headset controls on Android.

## 14. Milestones

1. **Foundation:** Flutter project for Android/Windows/Linux, drift schema + migrations, Riverpod wiring, Default theme, navigation shell (phone + desktop layouts).
2. **Local library + playback:** add folders/files, tag reading, local playlists (create, edit, reorder), player with queue/shuffle/repeat, background playback, system media controls (Android notification + lock screen + headset buttons, Windows SMTC, Linux MPRIS), search.
3. **YouTube import + sync + streaming:** yt-dlp adapters (Android platform channel, desktop binary), import flow + Android Share, Sync with YouTube, removed-on-YT UI, stream resolver with prefetch.
4. **Downloads:** queue, per-device toggle, Wi-Fi only, failure handling, yt-dlp updater, storage readouts.
5. **Themes + lyrics:** theme engine, editor, font import, follow-cover palette, lyrics service + UI.
6. **Device sync:** identity/certs, discovery, pairing, change exchange, merge + conflict UI, file transfer.
7. **Packaging:** signed release APK (personal keystore), Windows installer (Inno Setup or MSIX), Linux AppImage. Bundle the yt-dlp binary per desktop platform.

## 15. Risks

| Risk | Mitigation |
|---|---|
| YouTube changes break yt-dlp | One-tap updater; adapter isolates the dependency |
| YouTube requires PO tokens / blocks some clients | Keep the yt-dlp args configurable in an advanced setting; update yt-dlp |
| `youtubedl-android` lags upstream | Its updater pulls the latest yt-dlp; the library itself is pinned |
| Android kills the background service | `audio_service` foreground service; battery-optimization prompt |
| mDNS blocked (firewall, AP isolation) | Manual IP:port fallback; firewall help text |
| APK size (~60–80 MB from bundled Python) | Accepted |
| LRCLIB availability | Cached results; lyrics are non-critical |
