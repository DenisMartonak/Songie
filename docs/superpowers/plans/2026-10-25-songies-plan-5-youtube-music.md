# Songies Plan 5: YouTube Music browse, search and instant streaming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Songs start playing about as soon as they're tapped. Songies also gets YouTube Music's search, home feed, artist, album and playlist pages, and radio queues.

**Architecture:**
- **Innertube client:** a small hand-written client (`lib/innertube/`) talks to YouTube's app API. It has two roles:
  - **Player:** the `player` endpoint, impersonating an ordered list of app clients, produces stream URLs. It sits behind a new `StreamSource` interface, falls back to the existing `YtDlpClient`, and keeps the existing `StreamResolver` cache.
  - **YouTube Music:** the web client (`WEB_REMIX`) endpoints `search`, `browse` and `next` produce typed models through defensive, per-row parsers.
- **New screens:** the Home feed rows and the new Search, Artist and Album/Playlist pages sit on those models and reuse Plan 4's widgets.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Riverpod, go_router, drift (no schema change), `dart:io` `HttpClient` behind an injectable transport, and the existing yt-dlp clients.

**Spec:** `docs/superpowers/specs/2026-10-25-songies-youtube-music-design.md`. It builds on `docs/superpowers/specs/2026-10-21-songies-design.md` and Plans 1–4.

**Branch:** `plan-5-youtube-music`, made from `plan-4-alive-ui-themes`. Plans 3 and 4 aren't merged yet.

## Global Constraints

- **Streaming order:**
  - Innertube `player` with each client in `kPlayerClients`, in order.
  - Then `YtDlpClient.resolveStream`.
  - Then the existing Plan 3 skip-and-notice behaviour.
  - A failing Innertube route never surfaces an error by itself.
- **Audio choice:** prefer opus, then m4a, then the best other audio-only format, with the highest bitrate within each. Same as yt-dlp's `bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio`.
- **Stream URL expiry:** read from the URL's `expire` query parameter (unix seconds). Keep the existing `StreamResolver` margins and clear the cache on any network change.
- **Settings:**
  - `kWifiOnly` ('wifi_only') now means downloads only. Its UI label is **"Wi-Fi only downloads"**.
  - The new key is `kWifiOnlyStreaming = 'wifi_only_streaming'`: device-local, default **false** on every platform. Its label is **"Wi-Fi only streaming"**.
  - Search, browse and cover art ignore both keys.
- **Visitor id:**
  - YouTube's `visitorData` is stored device-local under `kYtVisitorData = 'yt_visitor_data'`.
  - It is sent as the `X-Goog-Visitor-Id` header and as `context.client.visitorData` on every Innertube request.
  - It is never synced.
- **Play reports and stats share one rule:** a play is reported once 30 s of the song have been heard, or the whole song if it's shorter. The constant is `kPlayThreshold = Duration(seconds: 30)` in `lib/player/play_rules.dart` (Plan 7 reuses it).
- **No idle work:**
  - Innertube requests come only from user actions, from the prefetch of the next queued song while playing, and from play reports while playing.
  - No timers, no polling, nothing at app start.
- **Tests never touch the network.** Innertube tests use recorded fixtures under `test/fixtures/innertube/` and a fake transport.
- **Searched songs:**
  - A played search, feed or radio result becomes a normal stamped `tracks` row (`source 'yt'`).
  - Library lists, local search and the add-songs picker show only tracks reachable from a non-deleted playlist entry.
  - Recents and history show everything played.
- **Plan 4 rules hold:** Motion tokens only, reduced motion, no looping animation while paused, AA contrast, `Pressable`/`FadeSlideIn`/`SkeletonBox`/`EqualizerBars` reused.
- Every synced row write takes its own `SyncStamp.next()` inside one `guardDb` transaction.
- **Commits end with:**
  - `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01PpGQxwoHbZEvfj8Y1ypZTg`

## Review Focus

1. **YouTube changes a response shape** (a renamed key, a new shelf type, a missing thumbnail). Only that shelf or row disappears, it is logged, and the page still renders. This is pinned in Tasks 3 and 4 with fixtures that have keys deleted.
2. **Every client identity is refused** (HTTP 400/403, or `playabilityStatus` not `OK`). Playback falls through to yt-dlp with no visible error, and the timing log names the route used. This is pinned in Task 2.
3. **Fast typing in Search.** Only the last query's results are shown, and stale responses that arrive late are dropped. This is pinned in Task 8.
4. **An age-restricted, region-blocked or removed song** from search or radio. It goes through the existing unavailable path (`markUnavailable`, quiet skip), not a crash or a retry loop. This is pinned in Task 2, with a `playabilityStatus: UNPLAYABLE`/`LOGIN_REQUIRED` fixture.
5. **The consent response in the EU.** Search and playback still work after **Not now**, and **Accept** is never asked again on that device. This is pinned in Task 9.

---

## File Structure

```
lib/innertube/transport.dart           InnertubeTransport (POST JSON), HttpInnertubeTransport (Task 1)
lib/innertube/clients.dart             ClientIdentity, kPlayerClients, kWebRemix (Task 1)
lib/innertube/innertube_client.dart    InnertubeClient: context, visitor id, consent detection (Task 1)
lib/innertube/player_stream_source.dart  InnertubeStreamSource (Task 2)
lib/player/stream_source.dart          StreamSource, FallbackStreamSource (Task 2)
lib/player/play_rules.dart             kPlayThreshold (Task 6)
lib/innertube/ytm_models.dart          YtmSong, YtmAlbum, YtmArtist, YtmPlaylist, YtmShelf, YtmSearchPage, ... (Task 3)
lib/innertube/ytm_parse.dart           defensive parsers (Tasks 3, 4)
lib/innertube/ytm_service.dart         YtmService: search, next/radio, home, artist, album, playlist (Tasks 3, 4)
lib/innertube/play_reporter.dart       PlayReporter (Task 6)
lib/library/yt_tracks.dart             YtTrackStore: upsert from YtmSong, metadata upgrade (Task 5)
lib/ui/ytm/*                           song row + menu, shelves, artist/album/playlist pages, consent (Tasks 8–10)
```

---

### Task 1: Probe, fixtures and the Innertube client core

**Files:**
- Create:
  - `lib/innertube/transport.dart`
  - `lib/innertube/clients.dart`
  - `lib/innertube/innertube_client.dart`
  - `tool/innertube_probe.dart` (a dev-only script, not shipped)
  - `test/fixtures/innertube/*.json`
  - `docs/innertube-notes.md`
- Modify: `lib/data/settings_repository.dart` (add `kYtVisitorData`), `lib/providers.dart`
- Test: `test/innertube/innertube_client_test.dart`

**Interfaces:**
- Produces:
  - `abstract class InnertubeTransport { Future<InnertubeResponse> post(Uri url, Map<String, Object?> body, Map<String, String> headers); }`, where `InnertubeResponse { int status; Map<String, Object?>? json; }`.
  - `HttpInnertubeTransport implements InnertubeTransport`: `dart:io` `HttpClient`, a 10 s connect and response timeout, and gzip.
  - `class ClientIdentity { String name; String version; int nameId; String userAgent; String host; Map<String, Object?> extraClient; }`.
  - `const List<ClientIdentity> kPlayerClients` (ordered; the starting values come from the probe) and `const ClientIdentity kWebRemix`.
  - `class InnertubeClient(InnertubeTransport t, SettingsRepository settings, {DateTime Function()? now})`:
    - `Future<Result<Map<String, Object?>>> call(ClientIdentity c, String endpoint, Map<String, Object?> body)`
    - `Future<String?> visitorData()`
    - `Future<void> resetVisitor()`
    - `Stream<bool> get consentRequired`
  - `innertubeClientProvider` (`_unwired` plus override in `main.dart`, following the existing provider pattern).

- [ ] **Step 1: Probe and record fixtures** with `dart run tool/innertube_probe.dart`. It uses the real network and is never run by tests. Record `player` responses for `fOT0BUpITw8` and `4D7u5KF7SP8` with each candidate client (visionOS first, then android_vr, tv, ios), plus WEB_REMIX `search` (songs and the all tab), `browse` (home `FEmusic_home`, one artist, one album, one playlist) and `next` (radio for `4D7u5KF7SP8`). Replace client IPs with `203.0.113.1`. Write the working clients, their versions and user agents, and what each returned, into `docs/innertube-notes.md`. Set `kPlayerClients` from it, putting clients that returned plain `url` fields (not `signatureCipher`) first.
- [ ] **Step 2: Write failing tests** in `test/innertube/innertube_client_test.dart`, using a `FakeTransport` that records requests and replays fixtures:
  - `call` sends `context.client.clientName`/`clientVersion` from the identity and `X-Goog-Visitor-Id` when one is stored.
  - A response's `responseContext.visitorData` is stored under `kYtVisitorData` when none is stored, and never overwritten after that.
  - `resetVisitor()` deletes the key, so the next call sends no visitor header.
  - HTTP 400, 403 or 429 gives `Err` with `FailureKind.network` (429 is tagged `throttled` the way `ytErrorKindOf` reads it). A JSON decode failure gives `Err(FailureKind.unknown)`.
  - A consent response (a fixture with a `consent.youtube.com` redirect, or a `FEconsent` browse) emits `true` on `consentRequired`.
- [ ] **Step 3: Run** `flutter test test/innertube/innertube_client_test.dart`. Expected: FAIL.
- [ ] **Step 4: Implement** the three files and the provider. `call` never throws: every error becomes `Err`.
- [ ] **Step 5: Run** the test file. Expected: PASS.
- [ ] **Step 6: Commit** `feat: Innertube client core, client identities and recorded fixtures`.

### Task 2: Instant streams with the yt-dlp fallback, and the split Wi-Fi settings

**Files:**
- Create: `lib/player/stream_source.dart`, `lib/innertube/player_stream_source.dart`
- Modify:
  - `lib/player/stream_resolver.dart`
  - `lib/youtube/ytdlp_client.dart` (`implements StreamSource`)
  - `lib/data/settings_repository.dart`
  - `lib/ui/settings/downloads_settings.dart`
  - `lib/main.dart`
  - `lib/providers.dart`
- Test:
  - `test/innertube/player_stream_source_test.dart`
  - `test/player/stream_source_test.dart`
  - `test/player/stream_resolver_test.dart`
  - `test/ui/settings/downloads_settings_test.dart`

**Interfaces:**
- Consumes: `InnertubeClient.call`, `kPlayerClients` (Task 1).
- Produces:
  - `abstract class StreamSource { String get name; Future<Result<YtStream>> resolveStream(String videoId); }`.
  - `class FallbackStreamSource implements StreamSource`, built as `FallbackStreamSource(List<StreamSource> sources)`. It tries each source in order. An `Err` whose `ytErrorKindOf` is `notFound` (unavailable) is returned at once; any other `Err` moves to the next source. It logs `stream <id> via <name> in <ms> ms` at info level.
  - `class InnertubeStreamSource implements StreamSource` (`name 'innertube'`), built as `InnertubeStreamSource(InnertubeClient c, {List<ClientIdentity> clients = kPlayerClients})`:
    - It remembers the last working client for the session and tries it first.
    - `playabilityStatus.status` other than `OK` maps to `notFound` for `UNPLAYABLE`, `ERROR` and `LOGIN_REQUIRED` with an age reason. Anything else gives a plain `Err` that falls through.
    - A format with only `signatureCipher` is skipped. If no format has a plain `url`, the client counts as failed.
    - It also exposes `PlaybackTracking? trackingFor(String videoId)`, which returns the last `playbackTracking` seen for that id. Task 6 uses it.
  - `StreamResolver(StreamSource source, NetworkStatus net, SettingsRepository settings, …)` replaces its `YtDlpClient` parameter.
  - `const kWifiOnlyStreaming = 'wifi_only_streaming'`.

- [ ] **Step 1: Write failing tests:**
  - **Picking the format, from the fixtures:** opus 251 is chosen over m4a 140, `expiresAt` is taken from the `expire` query parameter, and the user agent of the identity used goes into `headers['User-Agent']`.
  - **Falling through clients:**
    - A 403 on the first client, then `OK` on the second, gives `Ok`, and the next call tries the second client first.
    - Every client failing gives `Err` that is *not* `notFound`.
  - **`playabilityStatus`:** the `UNPLAYABLE` fixture gives `Err` with `ytErrorKindOf == notFound`.
  - **`FallbackStreamSource`:**
    - innertube `Err(network)` followed by a fake yt-dlp `Ok` gives `Ok` from yt-dlp.
    - innertube `notFound` gives `notFound` without calling yt-dlp.
  - **`StreamResolver`:**
    - On mobile data with `kWifiOnlyStreaming` true, it returns the existing Wi-Fi message.
    - With `kWifiOnly` true but `kWifiOnlyStreaming` false, it streams.
  - **Settings → Downloads:** the switch is labelled "Wi-Fi only downloads" and writes `kWifiOnly`. A second switch, "Wi-Fi only streaming", writes `kWifiOnlyStreaming` and is off by default on Android.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** In `main.dart`, wire `StreamResolver(FallbackStreamSource([innertube, ytDlpClient]), …)`. `onStreamMetadata` stays as it is: it fires only when yt-dlp served the stream, because Innertube's `YtStream` has no metadata fields set.
- [ ] **Step 4: Run** `flutter test test/innertube test/player test/ui/settings`. Expected: PASS, and the existing player tests stay green.
- [ ] **Step 5: Commit** `feat: instant streams via Innertube with yt-dlp fallback; separate Wi-Fi only streaming`.

### Task 3: YouTube Music models, search and radio

**Files:**
- Create: `lib/innertube/ytm_models.dart`, `lib/innertube/ytm_parse.dart`, `lib/innertube/ytm_service.dart`
- Test: `test/innertube/ytm_search_test.dart`, `test/innertube/ytm_next_test.dart`

**Interfaces:**
- Consumes: `InnertubeClient.call`, `kWebRemix` (Task 1).
- Produces:
  - **Models:**
    - `class YtmArtistRef { String? browseId; String name; }`.
    - `class YtmSong { String videoId; String title; List<YtmArtistRef> artists; String? album; String? albumBrowseId; int? durationMs; String? thumbnailUrl; bool isVideo; }`, with `String get artistLine` (names joined by ", ").
    - `class YtmAlbum { String browseId; String title; String? artist; String? year; String? thumbnailUrl; String? playlistId; }`.
    - `class YtmArtist { String browseId; String name; String? thumbnailUrl; }`.
    - `class YtmPlaylist { String browseId; String title; String? author; String? thumbnailUrl; }`.
  - `enum YtmSearchKind { songs, videos, albums, artists, playlists }`.
  - `class YtmSearchPage { List<Object> items; String? continuation; }`, where the items are a single model type per kind.
  - `class YtmRadio { List<YtmSong> songs; String? continuation; YtmSong? current; }`, where `current` carries the rich metadata of the seed song.
  - **`class YtmService(InnertubeClient c)`:**
    - `Future<Result<YtmSearchPage>> search(String query, YtmSearchKind kind, {String? continuation})`. It uses the `params` filter values for each kind, recorded in `docs/innertube-notes.md`.
    - `Future<Result<YtmRadio>> radio(String videoId, {String? continuation})`, which calls `next` with `playlistId: 'RDAMVM<videoId>'`.
  - **`ytmServiceProvider`.**

- [ ] **Step 1: Write failing tests** from the fixtures:
  - **Songs search:**
    - At least 10 `YtmSong`, each with a `videoId`, a title, at least 1 artist and a `durationMs`.
    - Artist runs have `browseId` values starting with `UC`.
    - The thumbnail picked is the largest, rewritten to `w544-h544`.
  - **Search tabs:** the videos, albums, artists and playlists searches each parse into their own model.
  - **Defensive parsing:**
    - A fixture copy with one row's `title` deleted gives one item fewer and no throw.
    - A fixture with an unknown renderer type gives the known items only.
  - **Radio:** 20 or more songs, not including the seed song. `current.album` is set for `4D7u5KF7SP8`. There is a `continuation` token.
  - **Errors:** a transport `Err` from `search` or `radio` is passed through unchanged.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Write the parsers as small functions per renderer (`musicResponsiveListItemRenderer`, `musicTwoRowItemRenderer`, `musicCardShelfRenderer` and so on). Each returns `null` on any missing piece and is wrapped in try/catch that logs at debug level.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: YouTube Music search and radio with defensive parsers`.

### Task 4: Home feed, artist, album and playlist browse

**Files:**
- Modify: `lib/innertube/ytm_models.dart`, `lib/innertube/ytm_parse.dart`, `lib/innertube/ytm_service.dart`
- Test: `test/innertube/ytm_browse_test.dart`

**Interfaces:**
- Consumes: Task 3's models and `YtmService`.
- Produces:
  - `class YtmShelf { String title; List<Object> items; }`, where the items are a mix of `YtmSong`, `YtmAlbum`, `YtmArtist` and `YtmPlaylist`.
  - `class YtmHome { List<YtmShelf> shelves; String? continuation; }`.
  - `class YtmArtistPage { YtmArtist artist; List<YtmSong> topSongs; List<YtmAlbum> albums; List<YtmAlbum> singles; List<YtmArtist> similar; String? radioPlaylistId; }`.
  - `class YtmAlbumPage { YtmAlbum album; List<YtmSong> tracks; }`. Track rows inherit the album's art when they have none.
  - `class YtmPlaylistPage { YtmPlaylist playlist; List<YtmSong> tracks; String? continuation; }`.
  - On `YtmService`:
    - `Future<Result<YtmHome>> home({String? continuation})`
    - `Future<Result<YtmArtistPage>> artist(String browseId)`
    - `Future<Result<YtmAlbumPage>> album(String browseId)`
    - `Future<Result<YtmPlaylistPage>> playlist(String browseId, {String? continuation})`

- [ ] **Step 1: Write failing tests** from the fixtures:
  - **Home:** 3 or more shelves, each with a non-empty title and 1 or more items. A shelf whose items all fail to parse is dropped.
  - **Artist:** the name is set, there are 1 or more top songs, and albums and similar artists are non-empty for the recorded artist.
  - **Album:** the tracklist count matches the fixture, `album.playlistId` starts with `OLAK5uy_`, and the tracks carry the album title.
  - **Playlist:** the first page of tracks parses, and `continuation` is set when the fixture has one.
  - **Defensive parsing:** removing a whole shelf's `contents` key still returns the other shelves.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** on the Task 3 parsers.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: YouTube Music home, artist, album and playlist browse`.

### Task 5: Track rows for searched songs, library-only lists and the metadata upgrade

**Files:**
- Create: `lib/library/yt_tracks.dart`
- Modify:
  - `lib/library/search_repository.dart` (`searchTracks` and `allTracks` become playlist-reachable only)
  - `lib/library/library_repository.dart` (if `updateTrackMetadata` needs a "fill only" mode)
  - `lib/main.dart`
  - `lib/providers.dart`
- Test: `test/library/yt_tracks_test.dart`, `test/library/search_repository_test.dart`

**Interfaces:**
- Consumes: `YtmSong`, `YtmRadio.current` (Task 3), and the existing `LibraryRepository.updateTrackMetadata` and `ArtCache`.
- Produces:
  - **`class YtTrackStore(AppDatabase db, SyncStamp stamp, ThumbnailFetcher thumbnails)`, where `ThumbnailFetcher` is the existing class in `lib/youtube/thumbnail_fetcher.dart`:**
    - `Future<Result<Track>> upsert(YtmSong s)`:
      - It inserts a stamped `tracks` row: source `'yt'`, `ytVideoId`, title, `artistLine`, album, `durationMs`, `searchText` built the way imports build it.
      - It returns the existing row when the `ytVideoId` is already known. For an existing row it fills only fields that are empty or equal to the channel name.
      - It queues the cover through the existing thumbnail and art path (`yt2-` refs).
    - `Future<List<Track>> upsertAll(List<YtmSong> s)`.
    - `Future<void> upgradeFrom(Track t, YtmSong rich)`: the same fill-only rule, as one stamped write. Nothing is written if nothing changed.
  - `ytTrackStoreProvider`.

- [ ] **Step 1: Write failing tests:**
  - Upserting a new song creates exactly one row, and upserting the same `videoId` twice still gives one row with the same id.
  - An imported row with `artist == '<channel name>'` and a null album is upgraded by `upgradeFrom`. A row whose album is already set keeps its album.
  - `upgradeFrom` with identical data writes nothing (the stamp doesn't change).
  - `searchTracks('x')` and `allTracks()` exclude a track that is in no playlist, and include one with an active entry. A track whose only entry is tombstoned is excluded.
  - `recentTracks` still includes the playlist-less track after a play is recorded.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** For the reachability filter, use an `EXISTS` subquery on `playlist_entries` joined to non-deleted `playlists`, following the scanner's subquery style.
- [ ] **Step 4: Run** `flutter test test/library`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: track rows for searched songs; library lists show playlist songs only`.

### Task 6: Play reports to YouTube

**Files:**
- Create: `lib/player/play_rules.dart`, `lib/innertube/play_reporter.dart`
- Modify: `lib/main.dart`
- Test: `test/innertube/play_reporter_test.dart`

**Interfaces:**
- Consumes:
  - `InnertubeStreamSource.trackingFor(videoId)` (Task 2), which returns a `PlaybackTracking`.
  - `PlayerService.states` (`queue`, `index`, `playing`, `position`, `duration`).
- Produces:
  - `const kPlayThreshold = Duration(seconds: 30)`.
  - `bool reachedPlay(Duration heard, Duration? length)`: true when `heard >= kPlayThreshold`, or when `length != null` and `heard >= length` (songs shorter than the threshold).
  - `class PlayReporter(Stream<PlayerState> states, InnertubeStreamSource src, InnertubeTransport t, {DateTime Function()? now})`, with `void dispose()`.
  - `PlaybackTracking { Uri playbackUrl; Uri watchtimeUrl; }` is defined in Task 2's file.

- [ ] **Step 1: Write failing tests**, using fake states and a fake transport:
  - Playing 31 s of a YouTube track sends one GET to its `playbackUrl` (with the `ver=2&cpn=<16 chars>` parameters YouTube's web app adds, as the probe notes record) and one `watchtimeUrl` report.
  - Playing 31 s again after a seek sends no second report for the same play.
  - Pausing at 29 s and resuming: the report is sent only once the heard time passes 30 s. Paused time doesn't count.
  - A 20 s song played to the end is reported.
  - A local track, or a YouTube track with no tracking (the yt-dlp route), sends nothing.
  - A transport error is logged and nothing is retried.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Count heard time from `position` advancing while `playing`, and reset it when the track identity changes. Wire it in `main.dart`.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `feat: report played songs to YouTube for a personal feed`.

### Task 7: Queue commands and radio

**Files:**
- Modify: `lib/player/player_service.dart`
- Create: `lib/player/radio_controller.dart`
- Test: `test/player/player_queue_commands_test.dart`, `test/player/radio_controller_test.dart`

**Interfaces:**
- Consumes: `YtmService.radio` (Task 3) and `YtTrackStore.upsertAll` and `upgradeFrom` (Task 5).
- Produces:
  - On `PlayerService`:
    - `Future<void> playNext(List<Track> tracks)` inserts after the current index.
    - `Future<void> addToQueue(List<Track> tracks)` appends.
    - Both keep the shuffle order sensible: they are inserted into `_queue` and `_original` at matching places.
  - **`class RadioController(PlayerService p, YtmService ytm, YtTrackStore store)`:**
    - `Future<void> playWithRadio(YtmSong seed)` upserts the seed, then calls `playQueue([seedTrack])`.
    - Then, in parallel with the stream start, it fetches `radio(seed.videoId)`, upserts the songs, calls `addToQueue`, and calls `upgradeFrom(seedTrack, radio.current)` when `current` is present.
    - When the player reaches the second-to-last song of a radio queue, it fetches the continuation once and appends it.
    - `Future<void> startRadio(Track t)` does the same for an existing track.
    - A radio failure leaves the seed playing and logs.
    - **When imported songs get the metadata upgrade** (the spec's "no extra request" rule):
      - An imported song is upgraded when it is a radio seed (`radio.current`), or when it shows up in any YouTube Music result (search, feed, album or radio), through `upsert`'s fill-only rule.
      - An imported song played straight from your playlist through the light route makes no extra request. It keeps the metadata it has, which yt-dlp still upgrades whenever it serves the stream or a download.
      - Record this in the report.

- [ ] **Step 1: Write failing tests:**
  - `playNext` with 2 tracks while playing index 3 of 10 makes the queue indexes 4 and 5 those tracks.
  - `addToQueue` appends, and with shuffle on, the new tracks come after the current one.
  - `playWithRadio` starts the seed before the radio response arrives. A test gate holds the radio until after `playQueue`.
  - When the radio arrives, the queue length is 1 plus the radio count.
  - Reaching the second-to-last song fetches the continuation exactly once.
  - A radio `Err` leaves the queue at length 1, with no notice shown.
  - Playing a playlist normally (not radio) never fetches a continuation.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/player`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: play next, add to queue and YouTube Music radio queues`.

### Task 8: Search page with YouTube Music results, and the song row

**Files:**
- Create: `lib/ui/ytm/ytm_song_row.dart`, `lib/ui/ytm/ytm_song_menu.dart`, `lib/ui/ytm/ytm_result_tiles.dart`
- Modify: `lib/ui/search/search_page.dart`, `lib/providers.dart`
- Test: `test/ui/search_page_test.dart`, `test/ui/ytm/ytm_song_row_test.dart`

**Interfaces:**
- Consumes:
  - `YtmService.search` (Task 3)
  - `RadioController.playWithRadio`, and `PlayerService.playNext`/`addToQueue` (Task 7)
  - `YtTrackStore.upsert` (Task 5)
  - the existing add-to-playlist sheet
- Produces:
  - `ytmSearchProvider.family((String query, YtmSearchKind kind))`, an autoDispose `FutureProvider` that returns `YtmSearchPage`.
  - `YtmSongRow({required YtmSong song, VoidCallback? onTap})`. When `onTap` is null it plays with radio.
  - `showYtmSongMenu(BuildContext, WidgetRef, YtmSong)` offers Play next, Add to queue, Add to playlist, Go to artist, Go to album and Start radio. Go to artist and Go to album are hidden when their ids are null.

- [ ] **Step 1: Write failing widget tests**, using fake providers:
  - Typing "daft" shows the "In your library" section first (when there are local matches), then the tabs **Songs · Videos · Albums · Artists · Playlists**, with Songs selected.
  - Tapping a song row calls `playWithRadio` with that song.
  - The ⋯ menu's Add to playlist upserts the song and opens the existing playlist picker.
  - Typing "da" then "daft" quickly, with "da" answering last, shows only "daft" results.
  - Offline gives "You're offline", with library results still shown. An error gives "Couldn't load — Retry", and Retry refetches.
  - The empty query keeps Plan 4's "Search your library" state.
  - Rows use `Pressable` and `FadeSlideIn` with distinct ids, and nothing animates once settled.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Tab switches keep each tab's results for the query. The existing `searchDebounce` drives the remote query too.
- [ ] **Step 4: Run** `flutter test test/ui`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: YouTube Music search results with tabs, song rows and menu`.

### Task 9: Home feed rows, the consent screen and resetting recommendations

**Files:**
- Create: `lib/ui/ytm/ytm_shelf_row.dart`, `lib/ui/ytm/consent_sheet.dart`
- Modify:
  - `lib/ui/home/home_page.dart`
  - `lib/ui/settings/settings_page.dart` (YouTube section)
  - `lib/providers.dart`
- Test: `test/ui/home_page_test.dart`, `test/ui/ytm/consent_sheet_test.dart`, `test/ui/settings_test.dart`

**Interfaces:**
- Consumes: `YtmService.home` (Task 4), `InnertubeClient.consentRequired`, `resetVisitor` (Task 1), `RadioController` (Task 7).
- Produces:
  - `ytmHomeProvider`, a session-cached `FutureProvider` refreshed only by pull-to-refresh or invalidate.
  - `YtmShelfRow({required YtmShelf shelf})`, a horizontal list of cards. A song card plays with radio. Album, artist and playlist cards push the Task 10 routes.

- [ ] **Step 1: Write failing widget tests:**
  - Home shows the existing sections first, then one `YtmShelfRow` per shelf with its title.
  - While loading it shows `SkeletonBox` rows. The shimmer stops after the load or an error.
  - Pull to refresh refetches once. Opening Home again in the same session doesn't refetch.
  - Offline hides the feed area with "Connect to see recommendations" and keeps the rest of Home.
  - `consentRequired == true` shows the sheet once, titled **"YouTube needs you to accept its terms"** with **Accept** and **Not now**. Not now closes it, and search and playback still work afterwards. Accept is recorded so the sheet never shows again on this device.
  - Settings → YouTube → **Reset YouTube recommendations** asks to confirm, then calls `resetVisitor` and invalidates `ytmHomeProvider`.
  - With paused playback and the feed loaded, no frame is scheduled once settled.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Accepting consent sends the response the probe recorded (see `docs/innertube-notes.md`). If the probe found no consent flow from this machine, Accept stores a device-local `yt_consent_given` flag and retries with the `SOCS` cookie value the notes give.
- [ ] **Step 4: Run** `flutter test test/ui`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: YouTube Music home feed, consent and reset recommendations`.

### Task 10: Artist, album and YouTube Music playlist pages

**Files:**
- Create: `lib/ui/ytm/artist_page.dart`, `lib/ui/ytm/album_page.dart`, `lib/ui/ytm/ytm_playlist_page.dart`
- Modify: `lib/router.dart` (`/ytm/artist/:id`, `/ytm/album/:id`, `/ytm/playlist/:id` inside each tab branch, like `playlist/:id`)
- Test: `test/ui/ytm/artist_page_test.dart`, `test/ui/ytm/album_page_test.dart`, `test/router_test.dart`

**Interfaces:**
- Consumes:
  - `YtmService.artist`, `album`, `playlist` (Task 4)
  - `RadioController` (Task 7)
  - `YtTrackStore.upsertAll` (Task 5)
  - `YtImportService.importPlaylist(String input)`
  - Plan 4's playlist hero pieces (`playlistHeroTop`, the sliver hero), extracted into a shared widget where the album page needs them
- Produces: the three routes, and `context.goYtmArtist(id)`, `goYtmAlbum(id)` and `goYtmPlaylist(id)` helpers.

- [ ] **Step 1: Write failing widget tests:**
  - **Artist page:** shows the name, Top songs (up to 5, with "Show all" when there are more), Albums, Singles and Fans also like.
    - **Play** plays the top songs in order.
    - **Radio** calls `startRadio`, using the artist's radio playlist.
  - **Album page:** shows the cover, title, artist and year and the tracklist.
    - Tapping track 3 calls `playQueue(albumTracks, startIndex: 2)` with radio off.
    - **Shuffle** plays the album shuffled.
    - **Import as playlist** calls `importPlaylist('https://music.youtube.com/playlist?list=<OLAK id>')`. When it succeeds it shows the existing import result and offers to open the new playlist.
  - **YouTube Music playlist page:** shows the tracklist. Scrolling to the end loads the continuation once. Import as playlist uses the playlist's URL.
  - **Loading and errors:** a load error shows "Couldn't load — Retry". The hero text reaches at least 4.5:1 contrast over the cover-derived top, on a near-white cover.
  - **Router:** `/ytm/album/MPREb_x` opens the album page inside the shell, and Back returns to Search.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Pages reuse `FadeSlideIn`, `Pressable`, `SkeletonBox` and Plan 4's hero contrast helper.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat: artist, album and YouTube Music playlist pages`.

### Task 11: Timing check, docs, checklist and builds

**Files:** `docs/PROGRESS.md`, `docs/manual-test-checklist.md`, `docs/innertube-notes.md`

- [ ] **Step 1:** Run `flutter test`, `flutter analyze`, `flutter build apk --release` and `flutter build linux --release`. Expected: all pass, with both builds made.
- [ ] **Step 2: Real-network timing on Linux.** Run the release build. Play 5 songs from search with the light route, then 5 with Innertube disabled through a debug-only flag (`--dart-define=SONGIES_FORCE_YTDLP=true`, read in `main.dart`). Record the `stream … via … in … ms` log lines in `docs/innertube-notes.md`.
- [ ] **Step 3: Checklist additions:**
  - Searching a song and tapping it plays it within about a second, and radio fills the queue.
  - Home shows YouTube Music rows below your library.
  - Artist, album and playlist pages open and play. **Import as playlist** works.
  - Wi-Fi only streaming is off after the update. With it on, mobile data blocks streaming but not browsing.
  - The EU consent sheet appears once.
  - Reset YouTube recommendations works.
  - A searched song doesn't appear in Library lists but appears in Recents.
  - With Wi-Fi off and Innertube blocked (a firewall rule), songs still play through yt-dlp.
- [ ] **Step 4: `PROGRESS.md`:**
  - Mark Plan 5 done, with its rulings and the items parked from its reviews.
  - Next is Plan 6 (synced lyrics). The roadmap becomes: 6 lyrics, 7 statistics, 8 device sync, 9 packaging.
- [ ] **Step 5: Commit** `docs: Plan 5 verification, checklist and progress`.
