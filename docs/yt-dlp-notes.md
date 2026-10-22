# yt-dlp behaviour notes (Plan 2 feasibility probe)

Probed 2026-10-22 on Windows with official `yt-dlp.exe` **2026.10.21** (SHA-256 `33121d19...9f555`, verified against the release `SHA2-256SUMS`). The binary is not in the repo.

## Verdict
Not blocked. Audio formats (opus/webm 251, m4a 140) are returned **without** any extra component, with one WARNING (see "JS runtime caveat"). Direct URLs are playable.

## Playlists used
- Flat import: `https://music.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI` ("Popular Music Videos", YouTube official, 182 entries).
- Private/deleted: `https://www.youtube.com/playlist?list=PLYwq8WOe86_xGmR7FrcJq8Sb7VW8K3Tt2` (taken from yt-dlp's own test suite; real playlist with `[Private video]` and `[Deleted video]` entries). `playlist_with_private.json` is a real trimmed capture, not hand-crafted.
- Stream: `https://music.youtube.com/watch?v=fOT0BUpITw8`.

## Working commands
```
yt-dlp --flat-playlist -J <playlist url>
yt-dlp -J -f "bestaudio[acodec=opus]/bestaudio[ext=m4a]/bestaudio" --no-playlist https://music.youtube.com/watch?v=<id>
```
- `music.youtube.com/playlist?list=` works; yt-dlp prints `WARNING: [youtube:tab] YouTube Music is not directly supported. Redirecting to https://www.youtube.com/playlist?list=...` (stderr, exit 0). `music.youtube.com/browse/VL<id>` also works.
- Flat playlist JSON: `_type: "playlist"`, `id`, `title`, `playlist_count`, `webpage_url` (rewritten to youtube.com), `entries[]`. Each entry: `_type:"url"`, `ie_key:"Youtube"`, `id`, `url` (music.youtube.com/watch?v=ID if the input was a music URL, else www.youtube.com), `title`, `duration` (int seconds), `channel`, `channel_id`, `uploader`, `thumbnails[]` (several sizes), `view_count`, `availability` (null for normal entries). Key off `id`, not the `url` host.
- The artist is the video's `channel`/`uploader` (may be a label or channel rather than the artist).
- Large playlists are slow (162 entries took a while; a 20000-entry uploads playlist took over 2 minutes). Use a generous timeout.
- A `watch?v=` URL given to `--flat-playlist -J` returns a single full video JSON (no `_type: playlist`, has `formats`), exit 0. So "not a playlist" is detected by absent `entries`, not by an error.

## Private / deleted entries (flat)
Entries are kept: `title` is `"[Private video]"` or `"[Deleted video]"`, `duration: null`, `channel`/`channel_id`/`uploader*: null`, `thumbnails` = `https://i.ytimg.com/img/no_thumbnail.jpg`, `availability: null`, `id` and `url` still present. Parser rule: skip entries with null `duration` and null `channel` (or those two exact titles). Titles that merely start with `[` (e.g. "[ORIGINAL] Kid cussing...") are valid videos. Some entries in huge playlists have `title: null`.

## Streaming
Selected format: `format_id 251`, `ext webm`, `acodec opus`, `abr` ~134.8, `protocol https`, `container webm_dash`, ~3.9 MB. Other audio-only formats: 249 (opus ~51), 250 (opus ~68), 139 (m4a ~49), 140 (m4a ~129). With `-J` the selected format's fields are merged at top level and also listed in `requested_downloads[0]` (`requested_formats` is null for a single format).
- `url`: `https://rrN---sn-*.googlevideo.com/videoplayback?expire=<unix>&ei=..&ip=<client ip>&id=..&itag=251&...&c=VISIONOS&sig=..&lsig=..`
- `expire` query param: unix seconds, about 21600 s (6 h) after extraction. Re-resolve before then (use a safety margin, e.g. 5 min). URL is bound to the client `ip`.
- `http_headers`: `User-Agent` (Chrome 148 Windows UA), `Accept`, `Accept-Language`, `Sec-Fetch-Mode: navigate`. A ranged GET (`Range: bytes=0-1023`) returned 206 `audio/webm` both with the UA and with curl's default headers; pass the yt-dlp headers to the player anyway.
- Fixture `stream_opus.json`: client IP replaced by `203.0.113.1`, only audio formats kept.

## Warnings and errors (stderr)
| Case | Exit | stderr |
|---|---|---|
| Any YouTube video extract | 0 | `WARNING: [youtube] No supported JavaScript runtime could be found. Only deno is enabled by default; to use another runtime add  --js-runtimes RUNTIME[:PATH]  to your command/config. YouTube extraction without a JS runtime has been deprecated, and some formats may be missing. See  https://github.com/yt-dlp/yt-dlp/wiki/EJS  for details on installing one` |
| Nonexistent playlist (valid id shape) | 1 | `ERROR: [youtube:tab] <id>: YouTube said: The playlist does not exist.` (stdout `null`) |
| Malformed playlist id | 1 | repeated HTTP 404/400 warnings, then `ERROR: [youtube:tab] <id>: Unable to download API page: HTTP Error 400: Bad Request` |
| Non-YouTube URL | 1 | `ERROR: [generic] foo: Unable to download webpage: HTTP Error 404: Not Found` |
| Nonexistent video | 1 | `ERROR: [youtube] <id>: This video is unavailable` |
| Private video | 1 | `ERROR: [youtube] <id>: Private video. If the owner of this video has granted you access, please sign in. Use --cookies-from-browser or --cookies ...` |
| Removed video | 1 | `ERROR: [youtube] <id>: This video has been removed for violating YouTube's Terms of Service` |
| Network error (simulated with `--proxy http://127.0.0.1:9`) | 1 | `WARNING: ... Unable to connect to proxy ... Retrying (1/3)...` x3 then `ERROR: [youtube:tab] <id>: Unable to download API page: ('Unable to connect to proxy', NewConnectionError(...))` |

Errors always exit 1 with stdout `null` under `-J`; classify by the stderr `ERROR:` line. Network errors: match `Unable to connect`, `Unable to download webpage/API page` without an `HTTP Error 4xx`, getaddrinfo/unreachable. Not testable here: a truly private playlist (expected to look like "does not exist" or a sign-in message).

## JS runtime caveat
yt-dlp warns that no JS runtime was found (only deno enabled by default) and "some formats may be missing", but audio 139/140/249/250/251 were all returned (client `VISIONOS`). No PO token or SABR messages appeared. This may degrade over time; on desktop consider shipping deno or `--js-runtimes`; log the warning rather than failing.

## Android (youtubedl-android)
- Maven Central: `io.github.junkfood02.youtubedl-android:library:0.18.1` (latest, 2025-11-16; versions 0.16.0 to 0.18.1). The README snippet still says 0.16.0 (stale).
- Optional: `...:ffmpeg:<ver>` (only for post-processing such as `--extract-audio`; NOT needed for `-J` / URL resolution) and `...:aria2c`.
- The 0.18.1 AAR (59 MB) bundles the yt-dlp script, Python and a QuickJS runtime (`libqjs.so`) for arm64-v8a, armeabi-v7a, x86, x86_64, so the JS-runtime concern appears covered there. Dependencies: kotlin-stdlib-jdk8 1.7.22, jackson-databind 2.11.1, commons-io 2.5, appcompat 1.4.2, core-ktx 1.8.0. minSdk is not stated in README/POM; verify at integration.
- Requirements: `android:extractNativeLibs="true"`, ABI filters, `mavenCentral()`.
- APIs: `YoutubeDL.getInstance().init(context)` (throws `YoutubeDLException`; call once at startup); `YoutubeDL.getInstance().execute(YoutubeDLRequest(url).apply { addOption("-J"); addOption("--flat-playlist") }, processId, callback)` returns a response with `out` (stdout) and `err`; `getInfo(request)` for single-video info; `destroyProcessById(id)`; `YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE or NIGHTLY)`. Exceptions carry stderr text, so the classification above applies.
