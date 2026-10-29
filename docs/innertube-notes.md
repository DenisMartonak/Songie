# Innertube notes (Plan 5 probe)

Probed 2026-10-25 on Linux (Nobara), from an EU home connection, with `dart run tool/innertube_probe.dart` (the probe is a dev tool: it uses the real network and is never imported by `lib/` or tests). Client values come from yt-dlp master `yt_dlp/extractor/youtube/_base.py` `INNERTUBE_CLIENTS`, fetched the same day.

## Request shape (all endpoints)
- `POST https://<host>/youtubei/v1/<endpoint>?prettyPrint=false`, JSON body `{"context": {"client": {...}}, ...endpoint fields}`.
- `context.client`: `clientName`, `clientVersion`, `userAgent`, `hl: "en"`, `utcOffsetMinutes`, the identity's extra fields, and `visitorData` once one is known. The probe also sent `gl: "US"` and `timeZone: "UTC"`; the app sends no `gl`, so YouTube picks the region from the IP.
- Headers: `Content-Type: application/json`, `User-Agent`, `X-YouTube-Client-Name` (numeric id), `X-YouTube-Client-Version`, `Origin: https://<host>`, `X-Goog-Visitor-Id` once known. Redirects are not followed.
- `player` body: `videoId`, `playbackContext.contentPlaybackContext.html5Preference: "HTML5_PREF_WANTS"`, `contentCheckOk: true`, `racyCheckOk: true` (as yt-dlp sends). None of the clients below needs `signatureTimestamp` (yt-dlp marks them `REQUIRE_JS_PLAYER: False`, except tv).
- No API response set any cookie.

## Visitor id: required for `player`
- Most WEB_REMIX responses (search, browse, the home page) carry `responseContext.visitorData`, an opaque base64 string; not all do (the `next` radio response's `responseContext` has none). A real visitor id encodes the visitor's country, so it is never committed: fixtures hold `FAKE_VISITOR_DATA`.
- **A `player` call without a visitor id fails**: VISIONOS and ANDROID_VR both return HTTP 200 with `playabilityStatus.status: "LOGIN_REQUIRED"`, reason "Sign in to confirm you're not a bot" (fixture `player_visionos_no_visitor_4D7u5KF7SP8.json`). With the visitor id from a WEB_REMIX `browse`, the same call returns `OK`. Checked three times in a row each way. So the stream source (Task 2) must make sure a visitor id is stored before its first `player` call (any WEB_REMIX call stores one).

## Player clients
| Client (yt-dlp key) | clientName / version / nameId | Result for both videos |
|---|---|---|
| visionos | `VISIONOS` / `1.02` / 101 | `OK`. Audio 139, 140, 249, 250, 251, all with plain `url` (no `signatureCipher`). Ranged GET of 251 with the client UA: 206 `audio/webm`. Has `playbackTracking`, also `serverAbrStreamingUrl` (SABR, unused). URL has `c=VISIONOS`. |
| android_vr | `ANDROID_VR` / `1.65.10` / 28 | `OK`. Audio 139, 140, 249, 251 (no 250), all plain `url`. Ranged GET of 251: 206 `audio/webm`. Has `playbackTracking`. yt-dlp's source says "Since 2026.08.17, ALL formats are 403'd with version 1.65.10"; that was not the case from here today (only the first 1 KB was fetched). |
| tv | `TVHTML5` / `7.20260707.07.00` / 7 | `UNPLAYABLE`, "The page needs to be reloaded." No formats. (yt-dlp needs the JS player for tv.) |
| ios | `IOS` / `21.26.4` / 5 | `OK`, audio 139, 140, 249, 250, 251 listed but with **neither** `url` nor `signatureCipher` (SABR only, needs a PO token). Its response also carries a consent flow (see Consent). |

User agents and extra `context.client` fields, verbatim from yt-dlp (all verified by the calls above):
- VISIONOS: UA `Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15`; `deviceMake: Apple`, `deviceModel: RealityDevice17,1`, `osName: visionOS`, `osVersion: 26.5.23O471`.
- ANDROID_VR: UA `com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip`; `deviceMake: Oculus`, `deviceModel: Quest 3`, `androidSdkVersion: 32`, `osName: Android`, `osVersion: 12L`.
- TVHTML5: UA `Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)`; no extra fields.
- IOS: UA `com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)`; `deviceMake: Apple`, `deviceModel: iPhone16,2`, `osName: iPhone`, `osVersion: 18.3.2.22D82`.

**`kPlayerClients` = [VISIONOS, ANDROID_VR]**, the two that returned plain `url` audio. TVHTML5 and IOS are left out: neither gave a playable URL, and trying them would only delay the yt-dlp fallback.

**Unavailable songs (ruling R12, supersedes R2's stop-on-notFound).** `InnertubeStreamSource` still returns `notFound` when every client reports a video-level status (UNPLAYABLE, an ERROR that isn't "reload", or an age LOGIN_REQUIRED). That verdict is a heuristic, so `FallbackStreamSource` no longer stops on it: an earlier source's `notFound` moves on to yt-dlp like any other failure, and only the LAST source's `notFound` (yt-dlp's) marks the song unavailable. Cost: about 2 s once per truly dead song.

### Stream URLs and `playbackTracking`
- Format URL: `https://rrN---sn-<node>.googlevideo.com/videoplayback?expire=<unix s>&ei=..&ip=<client ip>&id=..&itag=251&...&mime=audio%2Fwebm&clen=..&dur=..&c=VISIONOS&...&sig=..&lsig=..`. `expire` is about 6 h after the response (`streamingData.expiresInSeconds` is `21540`). Each format also has `bitrate`, `averageBitrate`, `contentLength`, `approxDurationMs`, `audioQuality`, `loudnessDb`.
- `playbackTracking` (visionOS and android_vr): `videostatsPlaybackUrl`, `videostatsDelayplayUrl`, `videostatsWatchtimeUrl`, `ptrackingUrl`, `qoeUrl`, `atrUrl` (each `{baseUrl}`), plus `videostatsScheduledFlushWalltimeSeconds` and `videostatsDefaultFlushIntervalSeconds`. The base URLs are `https://s.youtube.com/api/stats/playback?cl=..&docid=<videoId>&ei=..&ns=yt&plid=..&el=detailpage&len=<seconds>&of=..&vm=..` (watchtime the same path `/api/stats/watchtime`). Tasks 2 and 6 read playback and watchtime from here.

## YouTube Music (WEB_REMIX)
- Identity: `WEB_REMIX` / `1.20260707.12.00` / 67, host `music.youtube.com`. yt-dlp gives no UA for it; we send yt-dlp's default desktop UA (Chrome 148 on Windows, as in the Plan 2 notes).
- `search` with only `query` (the all tab): `contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents` = one `itemSectionRenderer` with a `messageRenderer` ("About these results"), one `musicCardShelfRenderer` (top result, here the artist Daft Punk, with 3 rows), then **29 `itemSectionRenderer`s holding one `musicResponsiveListItemRenderer` each** (not one `musicShelfRenderer` per kind as older ytmusicapi parsers expect).
- `search` with a filter `params` (songs): an `itemSectionRenderer` then one `musicShelfRenderer` with 20 `musicResponsiveListItemRenderer`s and a `continuations` token.
- Search filter `params`, read live from the all tab's `chipCloudChipRenderer` chips:

  | Filter | `params` |
  |---|---|
  | Songs | `EgWKAQIIAWoSEAUQCRADEAQQEBAKEA4QFRAR` |
  | Videos | `EgWKAQIQAWoSEAUQCRADEAQQEBAKEA4QFRAR` |
  | Albums | `EgWKAQIYAWoSEAUQCRADEAQQEBAKEA4QFRAR` |
  | Artists | `EgWKAQIgAWoSEAUQCRADEAQQEBAKEA4QFRAR` |
  | Community playlists | `EgeKAQQoAEABahIQBRAJEAMQBBAQEAoQDhAVEBE%3D` |
  | Featured playlists | `EgeKAQQoADgBahIQBRAJEAMQBBAQEAoQDhAVEBE%3D` |
  | (also Episodes `...AkgB...`, Podcasts `...AlAB...`, Profiles `...AlgB...`) | |

  The filter is the first bytes (`EgWKAQI` + `I`/`Q`/`Y`/`g` for songs/videos/albums/artists; `EgeKAQQoA` + `EAB`/`DgB` for community/featured playlists); the tail after `Wo`/`ah` lists result options, and its order changed between two runs an hour apart (`EAUQCRADEAoQBBAQEBUQDhAR` earlier), both accepted. ytmusicapi builds the same prefixes. Send the value as-is (the `%3D` included, as the web client does). For "playlists" use Community playlists, or merge both.
- `browse` `FEmusic_home`: `singleColumnBrowseResultsRenderer.tabs[0]...sectionListRenderer` with 3 `musicCarouselShelfRenderer` shelves on the first page ("Quick picks" of `musicResponsiveListItemRenderer`s, "Take it easy", "All hits" of `musicTwoRowItemRenderer`s) and a continuation for more.
- Artist (`UCRr1xG_2WIDs18a6cIiCxeA`, Daft Punk): `musicImmersiveHeaderRenderer` header, a top-songs `musicShelfRenderer` and carousels (albums, singles, videos, related).
- Album (`MPREb_K8qWMWVqXGi`, Random Access Memories): `twoColumnBrowseResultsRenderer`, `musicResponsiveHeaderRenderer` header, 13 tracks in `secondaryContents`' `musicShelfRenderer`, album playlist id `OLAK5uy_kNhM2yaBTOVwrcZJepB1C9P3-n5_Sfy5c`, and an "Other versions" carousel.
- Playlist (`VLPL-hvaaoSDXQJpFhQYRkEjc_Zh4Sd65c-e`): `musicResponsiveHeaderRenderer`, the first page of tracks (about 40 rows) and a continuation.
- `next` radio for `4D7u5KF7SP8`: body `videoId`, `playlistId: RDAMVM4D7u5KF7SP8`, `params: wAEB`, `isAudioOnly: true`, `enablePersistentPlaylistPanel: true`, `tunerSettingValue: AUTOMIX_SETTING_NORMAL`. The queue is in `...musicQueueRenderer.content.playlistPanelRenderer.contents` (`playlistPanelVideoRenderer`s, the first is the seed) with continuations.

- Continuations (search, `next`) are sent ytmusicapi-style: URL params `ctoken=<token>&continuation=<token>&type=next` plus `continuation` in the body. **Unverified live until Task 11** (the fixtures only have FAKE_ tokens).

## Consent
- `GET https://music.youtube.com/` with no cookies: **302 to `https://consent.youtube.com/m?...`** from here. With `Cookie: SOCS=CAI`: 200, no redirect.
- The Innertube API itself was **not** redirected: every POST above returned 200 with normal content, without any cookie, and the WEB_REMIX responses carry no consent marker. So search, browse and playback work without consent from here.
- The **IOS** player response does carry a consent flow: `onResponseReceivedActions[0].startEomFlowCommand.eomFlowRenderer.webViewRenderer.url` = `https://consent.youtube.com/yt-app-main?...&vd=<visitorData>...` with `consentMoment: CONSENT_MOMENT_INITIAL`. `InnertubeClient` treats a `https://consent.youtube.com/` link anywhere in a response, a 3xx to consent.youtube.com, or an `FEconsent` browse id as "consent required".
- How open-source clients get past it: yt-dlp sets the cookie `SOCS=CAI` on `.youtube.com` ("accept all", `_initialize_consent`) unless the user's own cookies already consented; ytmusicapi and NewPipe send the same kind of `SOCS` cookie. For Task 9: **Accept** stores a device-local consent flag and from then on sends `Cookie: SOCS=CAI` on Innertube requests; Not now sends nothing extra.

## Fixtures (`test/fixtures/innertube/`)
Each file is `{"status": <http status>, "json": <response>}`, compact JSON (read with `jq`).
- `player_<client>_<videoId>.json` for visionos, android_vr, tv, ios and both videos; `player_visionos_no_visitor_4D7u5KF7SP8.json` (LOGIN_REQUIRED).
- `search_all.json`, `search_songs.json` (query "daft punk"), `browse_home.json`, `browse_artist.json`, `browse_album.json`, `browse_playlist.json`, `next_radio.json`.
- `consent_browse_handcrafted.json` is **hand-crafted** (no consent page was served to the API from here): a minimal browse response whose `navigateAction` points at `FEconsent`.

Scrubbed (the repo is public):
- Client IP → `203.0.113.1` (query `ip=` and `/ip/` path pairs in manifest URLs).
- Every key containing `visitorData` (also `updatedVisitorData` in the IOS consent flow) → `FAKE_VISITOR_DATA` (also the `vd=` parameter in consent links); `trackingParams`/`clickTrackingParams` → `FAKE_TRACKING_PARAMS`; `continuation`/`token` → `FAKE_CONTINUATION`/`FAKE_TOKEN`; `serializedShareEntity`, `serializedContextData`, `responseId`, `eventId`, `rolloutToken`, `queueContextParams` → fixed fakes; URL parameters `fexp` and `initcwndbps` → `FAKE_FEXP`/`FAKE_CWND`.
- URL parameters `ei vm sig lsig n pot cpn of s id plid oid bui spc xpc` → `FAKE_*`, `gcr` → `zz`, `mn` → `sn-fake`, and `rrN---sn-<node>.googlevideo.com` hosts → `rr1---sn-fake.googlevideo.com`. So fixture URLs keep their shape and `expire`, but do not play.
- The probe fails if any seen IP or visitor id is left in a fixture, or if any string value base64-decodes to visitor-shaped data (protobuf `0x0A 0x0B` + 11 chars). `test/innertube/fixtures_scrubbed_test.dart` runs the same check on every committed fixture.

Trimmed (to keep the repo small): dropped `frameworkUpdates`, `responseContext.serviceTrackingParams` and other web response context, `storyboards`, `attestation`, `playerConfig`, ad fields, `annotations`, `endscreen`, `cards`, `captions`, `heartbeatParams`, `messages`, `description`, sign-in `modalEndpoint`s; menus keep only navigation entries (Go to artist/album, radio), not queue/library/feedback service entries; `musicCarouselShelfRenderer` lists are cut to 6 items; the radio queue to 25 songs. Search result shelves, album and playlist track lists are complete.

## Live check (Plan 5 Task 11, 2026-10-27)
Run from this Linux host with the dev-only tool `tool/stream_timing.dart` (`flutter test tool/stream_timing.dart`, output sent to a scratch file and read before copying). It takes the first 5 songs of a live "daft punk" song search and resolves each through the real `InnertubeStreamSource` and then through `YtDlpClient` (yt-dlp 2026.10.26, the app's binary in `~/.local/share/songies/bin`). This times the stream lookup only, not player start-up. Only video ids, routes, times, counts and statuses are recorded here.

Timing, second run (the first run gave the same picture: Innertube 68–148 ms, yt-dlp 2196–2493 ms):

| Video | Innertube | yt-dlp |
|---|---|---|
| `khnokW3Mw24` | 140 ms (includes the one-time visitor-id bootstrap) | 2266 ms |
| `qe8Q7mjxjig` | 87 ms | 2288 ms |
| `LxgnIhjQFuE` | 86 ms | 2105 ms |
| `a7Wask21bew` | 108 ms | 2241 ms |
| `ZFZM6jDTWd4` | 120 ms | 1972 ms |

The log lines, as printed:
```
stream khnokW3Mw24 via innertube in 140 ms
stream qe8Q7mjxjig via innertube in 87 ms
stream LxgnIhjQFuE via innertube in 86 ms
stream a7Wask21bew via innertube in 108 ms
stream ZFZM6jDTWd4 via innertube in 120 ms
stream khnokW3Mw24 via yt-dlp in 2266 ms
stream qe8Q7mjxjig via yt-dlp in 2288 ms
stream LxgnIhjQFuE via yt-dlp in 2105 ms
stream a7Wask21bew via yt-dlp in 2241 ms
stream ZFZM6jDTWd4 via yt-dlp in 1972 ms
```
Every Innertube resolve succeeded on the first client, so none fell through to yt-dlp. In the app, `--dart-define=SONGIES_FORCE_YTDLP=true` (debug and profile builds only) leaves Innertube out, to compare the two routes end to end.

Live checks (all pass):
- **(a) Search continuation (ruling R6):** the songs search's first page had 20 songs and a token. The continuation returned 20 more songs, all 20 new (none repeated from page one), and a next token.
- **(b) Radio continuation:** radio from `khnokW3Mw24` gave 49 songs plus the seed as `current`, and a token. The continuation returned 49 more, all new, and a next token.
- **(c) Artist radio:** the first "daft punk" artist result's page had 5 top songs and an `RDEM…` radio playlist id. `next` with that playlist and the first top song (`khnokW3Mw24`) as the seed returned 49 songs and the seed as `current`. The artist page's `musicDescriptionShelfRenderer` section was skipped and logged, as designed.
- **(d) Consent:** not asked (0 consent events, consent not given). As in the probe above, the API isn't consent-gated from this host.

## Signed in (Plan 7 probe)

**UNVERIFIED — manual check pending.** Status after Plan 7 Task 7 (2026-10-28): the live sign-in check was not run. The personal feed, history attribution and expiry detection are all "manual check pending", and so is the Task 1 probe. The probe (`tool/innertube_auth_probe.dart`) is written but has not been run. No exported cookies file was available while Task 1 ran (2026-10-28, about 10 minutes of waiting). Everything below comes from how ytmusicapi and yt-dlp document signed-in requests. The two fixtures are hand-crafted from the Plan 5 `browse_home.json`, and they stay hand-crafted (R4). Personal feed, history attribution and expiry detection stay unverified until the manual check below passes.

### Running the probe (the manual check)
1. Export a Netscape `cookies.txt` from a browser signed in to music.youtube.com, to a path **outside the repo**.
2. `flutter test tool/innertube_auth_probe.dart --dart-define=COOKIES=<path> --dart-define=OUT=<scratch dir> > <scratch dir>/probe.log`. This runs under the Flutter test runner for the same reason as `stream_timing.dart`: plain `test()`, so real HTTP works.
3. Read `probe.log`. Then update this section with **only** statuses, marker values and yes/no findings, and remove the UNVERIFIED line. **Delete the cookies file** afterwards (the probe never deletes it).
4. Raw responses stay in `<scratch dir>/raw` and are never committed. The probe refuses an `OUT` inside the repo. Ruling R4: real signed-in responses are never saved as fixtures, scrubbed or not, because they reveal the account's listening taste. If the run shows a shape the fixtures lack (a different marker place, a refusal status, a new shelf renderer), reproduce it **by hand** in the hand-crafted fixtures below.

What it sends: about 11 requests, 2 s apart, no loops. It sends Home four ways (signed out; cookies + Authorization; cookies only; the same cookie names with fake values, which stands in for an expired session). It sends an anonymous VISIONOS `player` for video A and a signed-in WEB_REMIX `player` for video B. Then it sends one play report each way (playback + watchtime, `et=35`, with nothing played), all with the session. Last, it reads `FEmusic_history` once. Public videos: **A = `fOT0BUpITw8`** gets the anonymous tracking URLs and **B = `4D7u5KF7SP8`** gets the signed-in ones (both from the Plan 5 probe). It prints only statuses, counts, marker values, URL parameter *names*, the positions of A and B in history, and shelf titles from a fixed list of generic ones (`<other>` otherwise).

### Headers for a signed-in WEB_REMIX Home (expected, to verify)
- The usual WEB_REMIX request (Request shape above), plus:
  - `Cookie:` the browser's cookies for `.youtube.com`. The ones that matter are `SID`, `HSID`, `SSID`, `APISID`, `SAPISID`, the `__Secure-1P*`/`__Secure-3P*` pairs and `LOGIN_INFO`.
  - **What Songies keeps and sends (ruling R8):** only the unexpired cookies a browser would send to `https://music.youtube.com`, that is, domain `youtube.com`, `.youtube.com` or `music.youtube.com`. No google.com cookie of any kind (not `accounts.google.com`'s `LSID`, `__Host-GAPS` or `__Host-1PLSID`, nor www/mail/docs cookies). This matches what ytmusicapi uses. `YtSessionFromCookies.build` applies it on every sign-in route, and the browser reader reads only `youtube.com` hosts. A cookie whose name or value can't go in a `Cookie` header (RFC 6265 cookie-octets; a value may be wrapped in DQUOTEs) is dropped when the session is built.
  - Play reports: the signed-in headers go only to an `https` URL on `youtube.com` or a subdomain of it. Any other tracking URL is sent without the session.
  - `Authorization: SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> https://music.youtube.com")>`, where `<ts>` is Unix seconds (ytmusicapi). yt-dlp also appends `SAPISID1PHASH …` and `SAPISID3PHASH …`, built the same way from `__Secure-1PAPISID` and `__Secure-3PAPISID`. When `SAPISID` is missing, yt-dlp uses `__Secure-3PAPISID` in its place.
  - `X-Goog-AuthUser: 0`, `X-Origin: https://music.youtube.com` (and `Origin`).
- Unknown until the probe runs: whether cookies without `Authorization` already give a personal Home (variant 3), and whether `X-Goog-Visitor-Id` matters when signed in. The probe sends no visitor id signed in. Brand accounts (`onBehalfOfUser`/datasync id) are out of scope.

### Signed-in marker (expected, to verify)
- **Signed in:** `responseContext.serviceTrackingParams[]` has an entry (`service: "GFEEDBACK"`) whose `params` holds `{"key": "logged_in", "value": "1"}`. `responseContext.mainAppWebResponseContext.loggedOut` is `false`.
- **Signed out:** the same param with `"value": "0"`, and `loggedOut: true`.
- Plan 5's fixtures dropped `serviceTrackingParams`. The Plan 7 fixtures keep that list, reduced to the `logged_in` param, and keep `mainAppWebResponseContext` reduced to `loggedOut`.
- **Expired session:** unknown whether Google answers a stale session with HTTP 200 and `logged_in=0` (the case the marker fixture models) or refuses it with 401/403. Task 3 treats both as "expired" (constraints: "a refused or signed-out Home response"). The probe's variant 4 records which one happens.

### Anonymous tracking attributes: unknown
Unknown whether Plan 5's anonymous `playbackTracking` URLs (VISIONOS `player`) count in the account's history when sent with the session cookies. Until the probe answers it, Task 4 takes the safe route (ruling R1): when a play qualifies, one signed-in WEB_REMIX `player` call fetches account tracking URLs, used for the report only, never for streaming. If the probe finds A in history, that extra call can be dropped.

### Known risks: signing in inside an embedded web view
- Google may refuse to sign in inside an embedded web view, on both Android (WebView) and Windows (WebView2). It then shows "This browser or app may not be secure" instead of the password step. The page loads Google's own `ServiceLogin?service=youtube&continue=https://music.youtube.com/` with the web view's default user agent.
- What the user sees if that happens: they close the page, and nothing changes. They stay signed out, with no error, and the regular feed keeps working.
- Other YouTube Music clients sign in successfully with this same web view flow on Android. Whether Google accepts it from WebView2 on Windows is unverified (Windows checklist item).

### Sign-in on Linux (Task 6, 2026-10-28)
Two routes, in this order: **"Sign in to YouTube"** (Google's page in a WebKitGTK window) and **"Use the YouTube sign-in from my browser"**.

**Route 1, in-app page (`lib/innertube/webkit_sign_in.dart`): works mechanically, sign-in itself unverified.**
- Package: `desktop_webview_window` 0.4.0 (MixinNetwork, published 2026-10-18; WebKitGTK 4.1 + libsoup 3, no runner changes). It builds on this Nobara machine in debug and release.
- One timeboxed probe (a throwaway `-t` entry point, deleted): `WebviewWindow.create()` opened a native window in the built app and loaded `https://music.youtube.com/`. `navigationState` reported the redirect to `consent.youtube.com` (EU) and the end of loading. `getAllCookies()` returned that page's `.youtube.com` cookies with name, value, domain and path (5 cookies, signed out: `SOCS`, `YSC`, `VISITOR_PRIVACY_METADATA`, `__Secure-YEC`, `__Secure-YENID`; only names were printed). `close()` and `WebviewWindow.clearAll()` worked.
- The route watches `navigationState` (event-driven, no polling). Once the window is on `music.youtube.com` and done loading, it reads the cookies; when they hold a session (`SAPISID`/`__Secure-3PAPISID` on `.youtube.com`) it closes the window. `getAllCookies()` answers the cookies of the current URL only, so the session is the `.youtube.com` set (R8: google.com cookies are never kept), which is enough for SAPISIDHASH. Expired cookies are dropped.
- Web data: cookies stay in memory (no cookie file in the default WebKit context). `clearAll()` runs before the window opens, after it closes and on Sign out. On Linux the plugin's `clearAll` starts WebKit's clear without waiting for it to finish (`webkit_website_data_manager_clear` with no callback), so the Dart call returns early.
- WebKit keeps salt and cache folders in `<XDG data home>/com.songies.songies` and `<XDG cache home>/com.songies.songies` (default `~/.local/share` and `~/.cache`). Sign out (`forget()`) also deletes these two folders, best effort. The paths are always the fixed child `com.songies.songies` (the Linux application id), never a parent. Relative XDG values are ignored, and without an absolute `HOME` the defaults are skipped.
- **Not verified:** a real Google sign-in in WebKitGTK. Google may answer "This browser or app may not be secure" for an embedded WebKit user agent (see the risk above). Then the user closes the window and uses route 2.
- The plugin also registers on Windows (WebView2 SDK fetched from NuGet at build time). Songies doesn't use it there; the Windows build is unverified here (checklist item).
- `libwebkit2gtk-4.1` becomes a runtime dependency of the Linux build.

**Route 2, browser cookies (`lib/innertube/browser_cookies.dart`, `browser_sign_in.dart`).**
- Profiles: Firefox `~/.mozilla/firefox/*/` and `~/.config/mozilla/firefox/*/` (newer Firefox, including this machine's Flatpak Firefox, keeps its profiles there), LibreWolf `~/.librewolf`, Waterfox `~/.waterfox`, and the Flatpak paths of ruling R3 (`~/.var/app/<id>/…`). Chromium family: `~/.config/<browser>/<profile>/` (`Network/Cookies` or `Cookies`) for Chrome (stable, Beta, Dev), Chromium, Brave, Edge and Vivaldi, plus the Flatpak Chrome, Chrome Dev, Chromium, ungoogled Chromium, Brave, Edge and Vivaldi paths.
- Flow (ruling R7): the route first asks "Use your browser's YouTube sign-in?". Then it lists the browser profiles found **by path only**; no cookie database is copied or read, not even names or hosts. Only the one profile the user picks is read (and, for Chromium, decrypted). A profile without a YouTube sign-in says so ("<browser> (<profile>) isn't signed in to YouTube") and the list comes back. Only unexpired cookies on `youtube.com`, `.youtube.com` or `music.youtube.com` are kept (R8); google.com cookies are never read. Firefox's `expiry` is seconds or (newer versions) milliseconds; Chromium's `expires_utc` is microseconds since 1601 (0 = session cookie). Firefox container cookies (non-empty `originAttributes`) are left out.
- Chromium: `v10` = AES-128-CBC, key PBKDF2-HMAC-SHA1(`peanuts`, `saltysalt`, 1, 16), IV 16 spaces. `v11` = the same with the password from the keyring: Secret Service `SearchItems(application=chrome|chromium|brave)`, preferring the item labelled "<Browser> Safe Storage" (an unlock prompt may appear), then KWallet's own API (`<Browser> Keys` / `<Browser> Safe Storage`). Edge uses Chromium's and Vivaldi uses Chrome's password (yt-dlp's mapping). The empty password is tried as a fallback. A cookie DB with `meta.version` ≥ 24 has a 32-byte SHA-256 of the host before each value, which is stripped.
- Review Focus 4: the database and its `-wal`/`-shm` are copied into a fresh temp directory set to 0700, the copy is opened with `OpenMode.readOnly`, and the directory is deleted afterwards. The original is never opened.
  - Before each copy, leftover `songies_cookies_*` directories in the temp folder that belong to this user (from a crash mid-read) are deleted. Links are never followed.
  - A browser may write while the files are copied. SQLite checks each `-wal` frame against the `-wal` header's salt and the frame checksums, not against the main file, and ignores frames that don't match: a torn copy loses only the newest writes. If the main file's size or mtime changed during the copy, it is copied once more.
- Errors are plain ("Couldn't read Firefox's cookies", "Couldn't unlock Google Chrome's cookies: its key in the keyring isn't available"). They have no cause attached, and logs carry only the exception type.
- Known gap: a Chromium **Flatpak** that stores its password through libsecret's in-sandbox file keyring (`~/.var/app/<id>/data/keyrings/`, unlocked through the Secret portal) can't be decrypted from outside the sandbox. Songies then shows the "Couldn't unlock" message. This machine has no such keyring today: its Flatpak Chromium-family browsers have no profiles yet.
- Real-home check (names and counts only, nothing decrypted): one profile found, one Firefox profile, with a YouTube sign-in present. The keyring is KWallet 6, with the Secret Service compatibility enabled.

### Plan 7 fixtures (hand-crafted, permanent)
These are the permanent signed-in fixtures, not placeholders for a recording (ruling R4). A live probe run changes them only by hand, to match a shape it found.
- `home_signed_in.json`: `browse_home.json` with `logged_in=1` and `loggedOut: false`. Its second and third shelves are retitled "Listen again" and "Mixed for you". "Listen again" carries a `strapline` (`Test User`) and a fake avatar (`https://example.invalid/fake_photo.jpg`), the way YouTube Music labels that shelf with the account.
- `home_signed_out_marker.json`: `browse_home.json` with `logged_in=0` and `loggedOut: true`.
- In both, every channel id is mapped to the public `UCRr1xG_2WIDs18a6cIiCxeA`. `fixtures_scrubbed_test.dart` fails on `SAPISID`, `SID=`, `HSID=`, `SSID=`, `APISID=`, `SIDCC` (whole words), `__Secure-`, `LOGIN_INFO`, `datasyncId`, an email shape or a `lh3.googleusercontent.com/a/` account photo in any fixture, and on any channel id other than that one in the `home_signed_*` fixtures. (The Plan 5 fixtures hold public artist channels.)
