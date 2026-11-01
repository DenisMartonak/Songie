# Android Auto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Songies works in Android Auto: player controls with a star, a Playlists tab (Favorites first) and a Recently played tab, resume on Play, and the existing stop reasons shown on the car screen.

**Architecture:** `SongiesAudioHandler` (audio_service, already a `MediaBrowserService`) answers browse calls from a pure `AutoBrowseTree` built over the library, Favorites and play-history repositories. Media ids are a small, tested format that `playFromMediaId` decodes back into a `PlayerService.playQueue` call. The star is one more custom action and media control. The manifest declares Songies an Android Auto media app.

**Tech Stack:** Flutter 3.47.8, audio_service 0.18.x, Riverpod, drift; Google's Desktop Head Unit (DHU) for the manual check.

**Spec:** `docs/superpowers/specs/2026-11-01-android-auto-design.md` (built after `docs/superpowers/plans/2026-11-01-favorites.md`).

## Global Constraints

- Tabs (root children, both browsable): `Playlists` (id `root/playlists`), `Recently played` (id `root/recent`).
- Playlists: Favorites first, then the library's order. Inside a playlist: first item `Shuffle` (playable), then its songs (playable).
- Recently played: last 50 songs, newest first; tapping one plays that list from it.
- Media id format: `pl/<playlistId>` (browsable), `pl/<playlistId>/shuffle`, `pl/<playlistId>/t/<index>/<trackId>`, `recent/<index>/<trackId>`. Ids are URL-encoded segments.
- Lists sent to the car are capped at 200 items per level (the queue still holds the whole playlist).
- Star: custom action `favorite`, shown first among custom controls, then shuffle, repeat; icon filled/outlined by the current song's state. It also appears in the phone's notification and lock screen (accepted).
- Play with nothing loaded: resume the last played song, queue = its playlist (from `play_history.playlist_id`), else the Recently played list. Never auto-play on connect.
- Stop reasons (Wi-Fi only, offline) are published as the playback error message to the session.
- Setup doc: README "Android Auto" section — developer mode (tap version 10×) → Unknown sources.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`; the two stats "under 500 ms" tests fail only under full-suite load.

## Review Focus

- A playlist with 1,000 songs: the car gets 201 items (Shuffle + 200), playing song 150 queues all 1,000 from it. → Task 1/2.
- A track id containing `/` (local file ids are UUIDs, YouTube ids `[A-Za-z0-9_-]`): encoding round-trips. → Task 1.
- Play pressed on a fresh start with empty history: nothing plays and nothing crashes. → Task 3.
- A song removed from a playlist after the car listed it: `playFromMediaId` with a stale index still plays the right track (matched by track id, index as a hint). → Task 2.
- Favorites changed on the phone while the car shows Playlists: the car's list refreshes (`notifyChildrenChanged`). → Task 2.

---

### Task 1: Media ids and the browse tree

**Files:** Create `lib/player/auto_browse.dart`; Test `test/player/auto_browse_test.dart`

**Interfaces — Produces:**
- `sealed class AutoId` with `AutoPlaylist(String playlistId)`, `AutoShuffle(String playlistId)`, `AutoPlaylistTrack(String playlistId, int index, String trackId)`, `AutoRecent(int index, String trackId)`, `AutoRoot(String tab)`; `String encodeAutoId(AutoId id)`, `AutoId? decodeAutoId(String s)`.
- `class AutoBrowseTree { AutoBrowseTree({required Future<List<PlaylistSummary>> Function() playlists, required Future<List<Track>> Function(String playlistId) tracksOf, required Future<List<Track>> Function() recent, required Future<Uri?> Function(Track) artUri}); Future<List<MediaItem>> children(String parentId); }` — root → the two tabs; `root/playlists` → Favorites first then others (`playable: false`); `pl/<id>` → `Shuffle` + up to 200 tracks (`playable: true`); `root/recent` → up to 50 tracks.
- [ ] **Step 1: Failing tests:** every `AutoId` kind round-trips through encode/decode, including ids with `/`, `%` and spaces; `decodeAutoId('junk')` is null; `children('root')` = [Playlists, Recently played]; `children('root/playlists')` lists `favorites` first even if summaries list it later; a 1,000-track playlist gives 201 children, first titled `Shuffle`; `children('root/recent')` caps at 50.
- [ ] **Step 2: Run** `flutter test test/player/auto_browse_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: Android Auto browse tree and media ids`

### Task 2: The audio handler answers the car

**Files:** Modify `lib/player/audio_handler.dart` (`getChildren`, `getMediaItem`, `playFromMediaId`, `customAction('favorite')`, controls order, `notifyChildrenChanged` on library/favorites changes); Modify `lib/player/media_controls.dart` (pass the tree and repositories); Test `test/player/audio_handler_test.dart` (extend)

**Interfaces:**
- Consumes: `AutoBrowseTree`, `decodeAutoId` (Task 1); `FavoritesRepository.toggle`, `favoriteIdsProvider` stream (Favorites plan).
- Produces: `static const String favoriteAction = 'favorite';` on `SongiesAudioHandler`.
- `playFromMediaId`: `AutoShuffle` → `playQueue(all tracks, shuffle on, sourcePlaylistId)`; `AutoPlaylistTrack` → `playQueue(all tracks, startIndex: the index whose track id matches, nearest to the given index)`; `AutoRecent` → `playQueue(recent list, startIndex)`.
- [ ] **Step 1: Failing tests** (fake player and repositories): `getChildren('root/playlists')` returns the tree's items; `playFromMediaId('pl/p1/t/2/t3')` → `playQueue` with start at t3; stale index (t3 now at 1) still starts at t3; `playFromMediaId('pl/p1/shuffle')` → shuffle on; `customAction('favorite')` toggles the current song; custom controls are ordered favorite, shuffle, repeat and the favorite icon follows the state; a Favorites change calls `notifyChildrenChanged('root/playlists')`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/player` → PASS.
- [ ] **Step 5: Commit** `feat: Android Auto playlists, recently played and the star`

### Task 3: Resume on Play, stop reasons, manifest, docs

**Files:** Modify `lib/library/play_history_repository.dart` (`Future<({String trackId, String? playlistId})?> lastPlayed()`); Modify `lib/player/audio_handler.dart` (`play()` and `prepare()` with nothing loaded resume; publish `PlayerState.error` as the session's error message); Modify `android/app/src/main/AndroidManifest.xml` (`<meta-data android:name="com.google.android.gms.car.application" android:resource="@xml/automotive_app_desc"/>`); Create `android/app/src/main/res/xml/automotive_app_desc.xml` (`<automotiveApp><uses name="media"/></automotiveApp>`); Modify `README.md` (Android Auto section), `docs/manual-test-checklist.md` (DHU and car run); Tests: `test/library/play_history_repository_test.dart`, `test/player/audio_handler_test.dart`, `test/tool/packaging_files_test.dart` (manifest and xml present)

- [ ] **Step 1: Failing tests:** `lastPlayed()` returns the newest row's track and playlist; empty history → null; handler `play()` with an empty queue and history (t2 from p1) → `playQueue(p1's tracks, start at t2)`; empty history → no call, no throw; a player error `"Wi-Fi only is on — connect to Wi-Fi to stream"` → `playbackState.errorMessage` equals it; packaging test finds the meta-data and `uses name="media"`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Full suite** `flutter analyze && flutter test` → clean; all pass except the two known stats timing tests. Then `flutter build apk --release` succeeds.
- [ ] **Step 5: Commit** `feat: Android Auto resume, error messages, manifest and setup guide`
- [ ] **Step 6: Manual check (user):** DHU or a car, following the checklist section.
