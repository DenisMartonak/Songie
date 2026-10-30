# Songies: device sync — design

**Status:** agreed in conversation · 2026-10-30
**Becomes:** Plan 10, branch `plan-10-device-sync` (made from `plan-9-stats`). Packaging follows.
**Builds on:** the main design (`2026-10-21-songies-design.md` §5 and §8, which this document updates) and Plans 1–9.

## Why

The user has Songies on several devices (an Android phone, a Windows PC, a Fedora/Nobara Linux PC) and wants the same library on all of them without redoing imports, playlists and themes on each one. Every synced table has carried sync columns (`id`, `clock`, `originDevice`, `deleted`, `localSeq`) since Plan 1 so that this plan could use them.

**Success:** on device A the user opens **Sync devices** and shows a code. On device B they open **Sync devices** and type the code. B finds A on the home network by itself, the two pair, and a sync runs straight away. Afterwards both devices have the same playlists, songs, themes, lyrics and listening history, and A's local MP3s play on B. Next time, one tap on the remembered device syncs again.

## What the user decided

- **Enter a code, and the app finds the device.** The user doesn't pick from a list first. One device shows a code, the other types it, and the app finds whichever device on the network is showing that code. This replaces §8.2 step 2 ("pick A from the discovered list, then enter the code").
- **Devices remember each other.** Pairing happens once per pair of devices. After that, both devices list each other under Sync devices, and syncing is one tap with no code. Unpair is available.
- **Sync goes both ways.** Each device ends up with everything from both, and deletions carry over too.
- **Keep the conflict prompt, but only for real clashes.** Changes to different parts of a playlist combine silently. For example, a rename on one device and two songs removed on the other both survive with no prompt. The prompt appears only when both devices changed the *same* thing differently: the same field of the same row (name, cover, an entry's position or status), or the playlist deleted on one side and edited on the other. Then the user is asked once per playlist: **Keep this device's / Keep \<peer\>'s / Keep both** (§8.3 step 4). The choice settles only the clashing rows, and every non-clashing change from both sides is kept.

## Goals

1. Pair two devices on the same network with a 6-digit code, with no device picking and no address typing in the normal case.
2. A two-way sync of every synced table, with the conflict prompt for playlists and silent last-writer-wins elsewhere.
3. Copy the local MP3s and imported fonts that the other device is missing.
4. Remembered devices: one tap to sync again, and Unpair.
5. Works between any two of Android, Windows and Linux.

## Non-goals

- Syncing over the internet, through a cloud service or a server. LAN only.
- Background or automatic sync. Nothing syncs unless the user taps (main design: "no idle work").
- Copying YouTube audio. Each device streams, or downloads its own copy if downloads are on for that playlist on that device.
- Syncing device-local things: the YouTube sign-in (it stays in secure storage), the Innertube visitor id, settings (active theme, Wi-Fi-only and so on), download on/off per playlist, library folders, download state, and the "Recently played" history (`play_history`).
- Syncing more than two devices at once. Three devices sync pair by pair, and changes pass along (`local_seq` forwarding, §5.2).

## Anti-goals (what would make this a failure even if it works)

- **A stranger on the same Wi-Fi can pair or read the library.** Only someone who has the code can pair, and only paired devices can sync.
- **Lost data.** A playlist, song, listen or file disappears without the user choosing it (through a deletion they made or a conflict choice). An interrupted sync (Wi-Fi drops, app closed) must leave both devices as they were before the sync, and running it again must be safe.
- **Duplicates.** The same YouTube song, the same MP3 or the same imported YouTube playlist shows up twice after a sync. Listening stats count a listen twice.
- **The sign-in leaks.** Cookies or anything else from secure storage are sent to the other device.
- **A server left running.** The app listens on the network outside the Sync devices screen.

## How it works

### The Sync devices screen

- **Where:** Settings → **Sync devices** (my call).
- **While the screen is open** the app runs its HTTPS server and advertises itself over mDNS (`_songies._tcp`, TXT `id`, `name`, `port`), and it browses for other Songies devices. Leaving the screen stops both (§8.1, unchanged).
- **The screen shows:**
  - **Your devices:** the paired devices. Each shows its name, when it was last synced, and whether it is on the network right now. Tap one to sync. Unpair is in that device's ⋯ menu (and in Settings, as §8.2 says).
  - **Pair a new device**, with two buttons: **Show a code** and **Enter a code**.
  - A short note: "The other device needs Sync devices open too."
  - On Linux, the `firewall-cmd` lines to open the port and mDNS. On Windows, a note that the firewall may ask. The Windows prompt itself appears the first time the server starts.

### Pairing by code

1. On device A the user taps **Show a code**. A shows a 6-digit code, valid for **5 minutes** (my call; §8.2 said 2 minutes, which is tight when walking between rooms). A adds `pairing=1` to its mDNS TXT record while the code is showing. **The code itself is never advertised.**
2. On device B the user taps **Enter a code** and types it.
3. B tries the code against every device it can see with `pairing=1`, normally just one. The device whose code matches completes the handshake and both sides end up with the `pair_key`.
   - **The handshake must not let anyone guess the code offline** (my call, changing §8.2). §8.2's `HMAC(code, A_fp‖B_fp‖nonce_B)` fails here: a 6-digit code has only 10^6 values, so a stranger who advertises `pairing=1` would receive B's HMAC, find the code in milliseconds and pair with A. So pairing uses a password-authenticated key exchange (a PAKE such as SPAKE2 or CPace) keyed by the code, with both certificate fingerprints bound into the transcript. A wrong guess teaches an attacker nothing beyond "not this code". If no maintained Dart PAKE exists, the builder implements one on `pointycastle` primitives, with published test vectors.
4. **If no device matches** within about 10 seconds, B says so ("No device showing that code was found. Check the code, and that both devices are on the same Wi-Fi.") and offers **Connect by address**, the §8.1 fallback: the user types A's IP and port (A shows them under its code) and the same handshake runs.
5. **Limits:** 5 wrong attempts on A invalidate A's code (§8.2). B's wrong attempt against a device that isn't the intended one counts against that device's code. That device just shows a fresh code if the user is pairing there.
6. **On success** both devices store the peer (device id, name, pinned certificate fingerprint, `pair_key`), and **the first sync starts immediately** on B (B is the initiator).

From then on, every connection uses TLS with the pinned certificate and per-request HMACs, and requests older than 60 s are rejected, all as in §8.2.

### What syncs

| Table | Merge rule |
|---|---|
| `playlists`, `playlist_entries` | Row-level merge. Rows changed on only one side are taken. A row changed on both sides with different content is a clash, grouped into one prompt per playlist. Additions from both sides never clash. |
| `tracks` | Last-writer-wins by HLC. Matched by natural key (see "Same thing, two ids"). |
| `yt_seen` | Set union. |
| `themes` | Last-writer-wins. The active theme is a setting and does not change. |
| `fonts` | Last-writer-wins. The font file is copied (see Files). |
| `lyrics` | Last-writer-wins. |
| `listens` | Last-writer-wins per row. Listens are only ever added (and pruned after 730 days), so in practice this is a union. The stats page then counts listening from every device. |

### Same thing, two ids

Two devices can create the same thing separately with different row ids:

- the same YouTube song (same `yt_video_id`) or the same MP3 (same `file_hash`), which are unique columns;
- the same font (same `file_hash`);
- the same `yt_seen` pair;
- the same YouTube playlist imported on both devices (same `yt_playlist_url`).

The merge must treat these as one thing. Both devices must pick the **same** surviving id by a deterministic rule (my call: the lexicographically smaller id). They must point every reference at it (playlist entries, lyrics, listens, `local_files` and `playlist_device_prefs` on each device) and tombstone the other row, so that later syncs agree. For two copies of the same imported YouTube playlist, the entries are joined. If the two copies differ in the same way an edited playlist would, the usual conflict prompt applies. The exact mechanics (how a tombstone is kept beside a unique column, for example) are the builder's.

**Entries of YouTube-linked playlists** are matched by (playlist, video), so two devices that each pressed "Sync with YouTube" don't end up with every new song twice (my call). Local playlists keep allowing the same song twice on purpose, so their entries are matched only by id.

**"Keep both" on a YouTube-linked playlist** makes the copy an ordinary local playlist, "\<name\> (from \<peer\>)" without the YouTube link. Otherwise the duplicate rule would join the two again on the next sync (my call).

The open item from Plan 1 belongs here too: re-adding a song whose row was deleted must bring that row back, not fail on the unique column.

### A sync run

§8.3 stands as written: Hello (schema check) → Pull pages of changes since the watermark → Merge on the initiator → Resolve conflicts → Apply on both sides, each in one transaction → advance watermarks only after both confirm → Files → queue YouTube downloads. These changes apply:

- **Interruption** (my call, relaxing §8.3): two devices can't commit at the same instant, so "both unchanged" can't be strict after Apply starts. The rule: each side applies in one transaction, watermarks move only after both confirm, and re-running the sync converges with no loss and no duplicates. A break before Apply leaves both devices unchanged.
- **Progress:** the screen shows the step and the counts ("Sending changes", "Copying 12 songs, 3 of 12"), with **Cancel**. Cancelling before Apply changes nothing. Cancelling during Files keeps the finished files and resumes the rest next time (Range requests on `.part` files).
- **Conflicts** are asked on the initiator. While the user decides, the other device shows "Waiting for \<name\>…". If the user leaves without deciding, nothing is applied.
- **The other device's screen must be open.** A remembered device that isn't on the network is shown as "Not found. Open Sync devices on \<name\>." with **Try again**.
- **Schema mismatch:** "\<name\> runs a different version of Songies. Update both to the same version."
- **After the sync** a short summary: "Synced with \<name\>: 3 playlists changed, 41 songs added, 12 files copied."

### Files

- Local MP3s that a device is missing are copied, then stored at `<appData>/library/local/<sha256>.mp3` (main design storage layout) and recorded in `local_files`. The sender reads the file from wherever it lives: a filesystem path on desktop, or a content URI on Android when the library folder was picked through the system picker.
- A file is written to `.part`, its SHA-256 is checked, then it is renamed. A file that fails the check is discarded and retried once.
- Imported fonts are copied the same way and **registered** when they arrive, so a synced theme using them renders without a restart (open item from Plan 4).
- An MP3 whose source file is gone on the sender is skipped. The song still syncs and shows as unavailable on the receiver until a later sync can copy it.
- Copying respects nothing like Wi-Fi-only, since it is LAN-only by nature.

### Platforms

- **Android:** mDNS needs a multicast lock while the screen is open. The server runs only while the screen is in the foreground, and leaving the app pauses it. A sync already running finishes or fails cleanly.
- **Windows:** the firewall prompt on first server start.
- **Linux:** the firewall note on the screen. Avahi is normally present on Fedora/Nobara.
- Identity: each device generates its `device_id` (it already exists in settings via `SyncStamp`) and a self-signed TLS certificate and key on first use of Sync devices, stored in app data (§8.2).

### Data changes

- New device-local `peers` table (§5 lists the fields), and a schema migration.
- An index on `local_seq` for each synced table (Plan 1 open item).
- `Hlc.parse` rejects non-canonical clocks, such as the wrong number of digits or leading `+` (Plan 1 open item).

## Constraints

- From the main design and every plan since: no idle work, tests never touch the real network (loopback servers in tests are fine), every synced write is stamped, and sign-in secrets and the visitor id are never synced.
- The protocol surface is §8.4, plus whatever pairing-by-code needs. Every JSON body carries `schema_version`.
- Long operations are cancellable and report progress through streams (main design §12).
- Pick maintained packages for mDNS (`bonsoir` was the main design's guess), TLS certificate generation and the HTTPS server, and check their versions at plan time. `pointycastle` is already a dependency.

## Testing

- Merge logic is tested on two in-memory databases: each rule in the table above, the "same thing, two ids" cases, deletions, conflicts with each of the three choices, and idempotence (running the same sync twice changes nothing the second time).
- Transitive forwarding: A↔B, then B↔C, carries A's change to C.
- Interruption: a failure before Apply leaves both databases unchanged. A failure at any later step leaves the watermarks unmoved, and re-running converges to the same result as an uninterrupted sync.
- Pairing: right code, wrong code, expired code, 5 failures, a tampered certificate (MITM), a fake device advertising `pairing=1` (it must learn nothing usable), and a replayed or stale request. All run over loopback.
- File transfer: resume after a cut, hash mismatch, a missing source file.
- The manual checklist gets a Plan 10 section: real pairing and sync across phone ↔ Linux ↔ Windows, firewall steps, and a large library.

## Left to the builder

The pairing endpoint shapes, page sizes, how the merged result is sent for Apply, the TLS and mDNS libraries, the duplicate-id mechanics, and the screen's exact layout, all within the rules above.
