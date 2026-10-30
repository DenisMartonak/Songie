# Songies Plan 10: Device Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pair two Songies devices on the same network by typing a 6-digit code, then sync playlists, songs, themes, fonts, lyrics and listens both ways with one tap, copying the local audio, font and cover files the other side lacks.

**Architecture:**
- **Data:** everything lives in `lib/sync/`, and the steps are pure functions where possible.
  - A `ChangeFeed` reads stamped rows by `local_seq`.
  - A pure `Merger` decides winners and playlist clashes.
  - A `RowApplier` writes a final row set in one transaction. It also merges natural-key duplicates (same video, same file, same YouTube playlist) onto the smaller id, using a new `mergedInto` column.
- **Transport:** HTTPS, run by `dart:io` with a self-signed EC certificate.
  - Pairing uses SPAKE2 (RFC 9382, P-256) keyed by the code.
  - After pairing, the initiator pins the peer's certificate fingerprint and signs every request with an HMAC.
- **Orchestration:** a `SyncRunner` on the initiator drives hello → pull → merge → ask → apply → commit → files → downloads.
  - A `SyncResponder` on the other side answers it.
  - A `SyncHost` runs the server and mDNS (`bonsoir`) only while the Sync devices page is open.

**Tech Stack:**
- Flutter 3.47.8 (`~/development/flutter/bin`, not on PATH), Dart 3.13, Riverpod 3, drift, go_router.
- New packages: `bonsoir: ^7.1.0` (mDNS) and `basic_utils: ^5.8.2` (EC key and self-signed X.509).
- Existing packages used: `pointycastle` (P-256 arithmetic) and `crypto` (SHA-256, HMAC).

**Spec:** `docs/superpowers/specs/2026-10-30-songies-device-sync-design.md`, plus main design §5 and §8, which it updates. Read both before any task. Where this plan and the spec disagree, the spec wins.

## Global Constraints

- **Branch:** `plan-10-device-sync`, made from `plan-9-stats`. Don't push or merge.
- **Schema:** goes from 7 to 8. JSON bodies all carry `"schema_version": 8`, and a mismatch is refused with HTTP 409 `{"error":"schema"}`.
- **Port:** 47823, falling back to any free port. mDNS type `_songies._tcp`, TXT `id`, `name`, `port`, `pairing` (`"1"` or `"0"`). **The code is never advertised, logged or sent in clear.**
- **Code:** 6 digits, zero-padded, from `Random.secure()`. It is valid for **5 minutes**, and 5 pairing attempts (each `/pair/start` that reaches the key exchange, right or wrong) use it up.
- **Requests:** rejected when their time is more than **60 s** from the receiver's clock, after the hello clock offset is applied.
- **Never synced:** settings, `local_files`, `playlist_device_prefs`, `library_folders`, `play_history`, `peers`, the YouTube session or visitor id. The device-local `local_files` and `playlist_device_prefs` are still rewritten when ids merge.
- **Stamping:** every synced write is stamped.
  - Rows applied from a peer keep their `clock` and `originDevice`, and get a fresh `local_seq`.
  - Rows the merge or the dedupe changes (clash winners, merge losers, rewritten references) get a full fresh stamp from `SyncStamp.next()`.
- **No idle work:** no server, mDNS or timers outside the Sync devices page. On Android the server stops when the app is paused, unless a sync is running.
- **Exact copy** (from the spec):
  - "The other device needs Sync devices open too."
  - "No device showing that code was found. Check the code, and that both devices are on the same Wi-Fi."
  - "Not found. Open Sync devices on \<name\>."
  - "\<name\> runs a different version of Songies. Update both to the same version."
  - "Waiting for \<name\>…"
  - "Synced with \<name\>: N playlists changed, N songs added, N files copied."
  - Buttons: "Keep this device's", "Keep \<name\>'s", "Keep both".
- **Earlier rules still hold:** tests never touch the real network (loopback only) or real home directories; `Motion.of(context)`; AA contrast via `SongiesColors`; long operations are cancellable streams.
- **Commits** end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Pjntruw24Wq5rjHruQoDNn`
- **Checks before each commit:** `flutter analyze` is clean and `flutter test` passes. Use `dart format` on touched files only.

## Review Focus

1. **Clocks that disagree.** A phone 10 minutes behind the PC must still sync: `/hello` returns the server's time, and the client signs with that offset. Test in Task 8 (`clock skew of 10 minutes still syncs`).
2. **Music playing during a sync.** A listen written on either side between the pull and the apply is neither lost nor overwritten, and it goes out in the next sync. Test in Task 8 (`write between pull and apply survives`).
3. **The same song added on both devices before their first sync** (the same video searched on both, the same MP3 scanned on both). Afterwards there is one track, and both devices' playlists point at it. Test in Task 3 (unit) and Task 8 (`first sync dedupes shared songs`).
4. **The peer's IP changed since last time** (DHCP). The peer is found again by device id through mDNS, not by the stored address. Test in Task 10 (`remembered peer at a new address`).
5. **The initiator vanishes while the other side waits** (app killed during the conflict prompt). The responder drops its session after 15 minutes of silence, unlocks, and has changed nothing. Test in Task 8 (`abandoned session times out`).

---

### Task 1: Schema 8, canonical clocks, received stamps, reviving deleted local tracks

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart`, then regenerate `lib/data/database.g.dart` (`dart run build_runner build -d`)
- Modify: `lib/core/hlc.dart`, `lib/data/sync_stamp.dart`, `lib/library/library_scanner.dart`, `lib/core/paths.dart` (add `sync` dir)
- Test: `test/data/migration_test.dart` (v7→v8), `test/core/hlc_test.dart`, `test/data/sync_stamp_test.dart`, `test/library/library_scanner_test.dart`

**Interfaces:**
- Produces:
  - `TextColumn get mergedInto => text().nullable()();` on `Tracks` and `Playlists`.
  - `@DataClassName('PeerRow') class Peers extends Table` (device-local), with:
    - `deviceId` (primary key), `name`, `certFingerprint` (lowercase hex SHA-256 of the certificate DER), `pairKey` (base64);
    - `host` (nullable), `port` (nullable int);
    - `lastSentSeq` and `lastReceivedSeq` (int, default 0), `lastSyncAt` (nullable `DateTime`).
  - A `@TableIndex(name: '<sql_table>_local_seq', columns: {#localSeq})` on each of the 8 synced tables.
  - `Hlc.parse` accepts only `^\d{13}-\d{5}-.+$`.
  - `Future<List<int>> SyncStamp.reserve(int n, {String? observedClock})`: `n` fresh strictly increasing `local_seq` values. When `observedClock` is given, the clock is advanced past it (`HlcClock.receive`). Both are persisted in one settings write.
  - `AppPaths.sync` = `<appData>/sync`.

- [ ] **Step 1: Write the failing tests.**
  - `migration_test`: `v7 to v8 adds merged_into, peers and local_seq indexes`. Open a v7 file, migrate, and assert:
    - `PRAGMA table_info(tracks)` has `merged_into`;
    - `peers` exists;
    - `PRAGMA index_list(listens)` contains `listens_local_seq`.
  - `hlc_test`: `parse rejects non-canonical clocks`. These all throw `FormatException`: `'1-0-dev'`, `'+000000000001-00000-dev'`, `'0000000000001-0000-dev'`, `'0000000000001-00000-'`. `Hlc.parse(h.pack()) == h` still holds.
  - `sync_stamp_test`: `reserve advances seq and observes the clock`. Reserve 3 with an observed clock 1 h in the future. The values are `[s+1, s+2, s+3]`, the next `next().clock` sorts after the observed clock, and a reload from the DB continues from `s+3`.
  - `library_scanner_test`: `re-adding a deleted local track revives its row`. Import a file, tombstone the track (`deleted=true`), import the same bytes again. The result is the same id, `deleted == false`, `mergedInto == null`, and a larger `localSeq`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `flutter test test/data test/core/hlc_test.dart test/library/library_scanner_test.dart`
- [ ] **Step 3: Implement.**
  - Migration: `if (from < 8)` adds the two columns, creates `peers` and the 8 indexes.
  - Scanner `_handle`: when no live row has the hash but a tombstoned one does, update that row in place (as `_updateInPlace` does, plus `deleted=false`, `mergedInto=null`) instead of inserting.
- [ ] **Step 4: Run all tests.** `flutter test` passes, and `flutter analyze` is clean.
- [ ] **Step 5: Commit** (`feat: schema 8 for device sync, canonical clocks, revive deleted tracks`).

### Task 2: Sync rows, content hash and the change feed

**Files:**
- Create: `lib/sync/sync_row.dart`, `lib/sync/change_feed.dart`
- Test: `test/sync/sync_row_test.dart`, `test/sync/change_feed_test.dart`, and a `snapshot` helper in `test/helpers/sync_fixtures.dart`

**Interfaces:**
- Produces:
  - `enum SyncTable { tracks, playlists, playlistEntries, ytSeen, themes, fonts, lyrics, listens }`, with:
    - `String get wire`: `tracks`, `playlists`, `playlist_entries`, `yt_seen`, `themes`, `fonts`, `lyrics`, `listens`;
    - `bool get clashes`: true only for `playlists` and `playlistEntries`.
  - `class SyncRow`, with:
    - `SyncRow(SyncTable table, Map<String, Object?> data)`, where `data` is the drift data class `toJson()`;
    - getters `id`, `clock`, `originDevice`, `localSeq`, `deleted`;
    - `String get contentHash`: the first 16 hex chars of SHA-256 over canonical JSON (keys sorted) of `data` without `clock`, `originDevice`, `localSeq`;
    - `SyncRow withStamp({required String clock, required String originDevice})`;
    - `Map<String, Object?> toWire()`, `factory SyncRow.fromWire(Map<String, Object?>)`;
    - `Insertable<DataClass> toInsertable(int localSeq)`, through the data class `fromJson`.
  - `class ChangePage { final List<SyncRow> rows; final int? next; }`
  - `class ChangeFeed`, with:
    - `ChangeFeed(AppDatabase db)`;
    - `Future<ChangePage> since(int seq, {int limit = 500})`: rows of every synced table with `local_seq > seq`, in ascending `local_seq` across tables. `next` is the last row's seq when more remain, else null;
    - `Future<int> highSeq()`.
  - Test helper: `Future<Map<String, String>> snapshot(AppDatabase db)`, a map from `'<wire>/<id>'` to `contentHash`, for comparing two databases.

- [ ] **Step 1: Write the failing tests.**
  - `round-trips every table through the wire`: one row per table, `DateTime` columns included, equal after `fromWire(toWire())`.
  - `content hash ignores stamps but not data or deleted`.
  - `since pages across all tables in seq order`: 10 rows over 8 tables, `limit: 3`, collected pages equal all rows once, ascending.
  - `since excludes rows at or below seq`.
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/sync`
- [ ] **Step 3: Implement.** `since` queries each table with `local_seq > ? ORDER BY local_seq LIMIT limit+1`, merges the results, and cuts at `limit`.
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: sync rows and change feed`).

### Task 3: Row applier with natural-key merging

**Files:**
- Create: `lib/sync/row_applier.dart`
- Test: `test/sync/row_applier_test.dart`

**Interfaces:**
- Consumes: `SyncRow`, `SyncStamp.reserve`, `SyncStamp.next`.
- Produces:
  - `class ApplyReport { final int written; final Set<String> playlistIds; final int tracksAdded; }`
  - `class RowApplier`, with:
    - `RowApplier(AppDatabase db, SyncStamp stamp, {DateTime Function() now = DateTime.now})`;
    - `Future<ApplyReport> apply(List<SyncRow> rows)`: one transaction, joining the caller's when there is one.

**Rules, in order:**
1. **Write order.** Rows are written in this order: tracks, playlists, fonts, themes, playlist entries, yt_seen, lyrics, listens.
2. **What is skipped.** A row is skipped when the local row has the same `contentHash`, or when the local `clock` is greater than or equal to the incoming one (by `Hlc.compareTo`). A listen whose `startedAt` is older than 730 days is skipped.
3. **What is written.** Every other row is written with its own `clock` and `originDevice` and a `local_seq` from one `reserve(n, observedClock: maxIncomingClock)`.
4. **Following merges.** An incoming row that references a track or playlist whose local row has `mergedInto` set is rewritten to the end of that chain first.
5. **Natural keys:**
   - live tracks by `ytVideoId` and by `fileHash`;
   - live playlists by non-null `ytPlaylistUrl`;
   - live fonts by `fileHash`;
   - live yt_seen by (`playlistId`, `videoId`);
   - live entries of playlists with `source == 'yt'` by (`playlistId`, `trackId`).

   When two different ids share a key (incoming against local, or two local rows after rewriting), **the smaller id survives** and the loser is merged into it:
   - **The loser:** tombstoned with `mergedInto = survivor` (tracks and playlists). A track loser also gets `ytVideoId` and `fileHash` set to null, so the unique columns hold.
   - **References to the loser** are rewritten to the survivor: `playlist_entries.trackId` and `.playlistId`, `listens.trackId`, `yt_seen.playlistId`.
   - **Lyrics:** a lyrics row is keyed by track id. The loser's lyrics move to the survivor when the survivor has no live row, and the loser's lyrics row is tombstoned.
   - **Device-local rows:** `local_files` keeps the survivor's row, or takes the loser's when the survivor has none or the loser's is `done` and the survivor's isn't. `playlist_device_prefs.downloadEnabled` becomes the OR of both.

   Every row this step changes is restamped with `next()`.
6. **Merge tombstones from a peer.** An applied track or playlist row that arrives with `mergedInto` set also rewrites local references to it.

- [ ] **Step 1: Write the failing tests.**
  - `applies new rows with their clock and a fresh local_seq`.
  - `skips equal content and older clocks`.
  - `same video under two ids merges onto the smaller id` (entries, listens and lyrics follow; the loser is a tombstone with null `ytVideoId`).
  - `same file hash merges and moves local_files`.
  - `same YouTube playlist imported twice is joined, without doubled entries`.
  - `local playlist keeps the same song twice`.
  - `incoming reference to a merged track is rewritten`.
  - `listen older than 730 days is skipped`.
  - `applying the same rows twice writes nothing the second time` (`written == 0`).
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/sync/row_applier_test.dart`
- [ ] **Step 3: Implement `RowApplier`.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: row applier with duplicate merging`).

### Task 4: The merger and playlist clashes

**Files:**
- Create: `lib/sync/merger.dart`
- Test: `test/sync/merger_test.dart`

**Interfaces:**
- Consumes: `SyncRow`, `SyncStamp.next`.
- Produces:
  - `enum Resolution { keepMine, keepTheirs, keepBoth }`
  - `class PlaylistClash`, with:
    - `playlistId`, `name` (mine if live, else theirs);
    - `bool mineDeleted`, `bool theirsDeleted`;
    - `List<SyncRow> mine`, `List<SyncRow> theirs` (that playlist's changed rows from each side).
  - `class MergeResult { final List<SyncRow> settled; final List<PlaylistClash> clashes; }`
  - `abstract class LocalView { Future<SyncRow?> row(SyncTable t, String id); Future<List<SyncRow>> entriesOf(String playlistId); }`, plus `DbLocalView(AppDatabase db) implements LocalView`.
  - `class Merger`, with:
    - `Merger({required SyncStamp stamp, required String peerName})`;
    - `MergeResult merge(List<SyncRow> mine, List<SyncRow> theirs)`, which is pure;
    - `Future<List<SyncRow>> resolve(MergeResult r, Map<String, Resolution> choices, LocalView local)`, which returns the final set F.

**Rules:**
- **Matching rows:** rows are matched per table by id.
  - A row only on one side goes to `settled`.
  - A row on both sides with an equal `contentHash` goes to `settled` once.
  - Different content on a non-clashing table: the higher clock goes to `settled`.
  - Different content on `playlists` or `playlistEntries`: a clash, grouped by playlist id (the row's own id, or the entry's `playlistId`).
- **Delete against edit:** a playlist row that is a tombstone on one side, while the other side has any live changed row in that group, makes the **whole group** a clash, even when no ids overlap.
- **Same row, different fields:** a rename on one side and a cover change on the other of the same playlist row is a clash, because no base version is kept. This is a known limit, so state it in the code doc.
- **Resolving,** for each clash group:
  - **keepMine / keepTheirs:** the chosen side's version of each clashing row, restamped.
  - **When the deletion wins:** the playlist tombstone plus a restamped tombstone for every entry of that playlist (from `local.entriesOf` and both sides' rows).
  - **When the edit wins against a deletion:** the edited side's playlist row (live) and its entries view, restamped.
  - **keepBoth:**
    - mine is kept as for keepMine;
    - theirs is copied as a new playlist: fresh ids and stamps, name `"<name> (from <peerName>)"` cut to 100 chars, `source 'local'`, `ytPlaylistUrl` and `lastYtSyncAt` null;
    - the copy's entries are their view (`local.entriesOf` overlaid with their changed rows), live entries only, same positions and status.
    - `resolve` throws `ArgumentError` for keepBoth when `theirsDeleted`.

- [ ] **Step 1: Write the failing tests.**
  - `one-sided rows settle`.
  - `lww tables take the higher clock`.
  - `rename on one side and removed songs on the other do not clash` (different rows).
  - `same entry moved differently clashes`.
  - `delete against edit clashes for the whole playlist`.
  - `keepMine, keepTheirs, keepBoth produce the expected rows` (one test each).
  - `keepBoth on a YouTube playlist makes a local copy without the link`.
  - `merge of identical sets has no clashes`.
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/sync/merger_test.dart`
- [ ] **Step 3: Implement `Merger` and `DbLocalView`.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: sync merger with per-playlist clashes`).

### Task 5: Device identity and the peers store

**Files:**
- Modify: `pubspec.yaml` (add `basic_utils: ^5.8.2`)
- Create: `lib/sync/device_identity.dart`, `lib/sync/peer_repository.dart`
- Modify: `lib/providers.dart` (`deviceIdentityProvider`, overridden in `main.dart` like `appPathsProvider`; `peerRepositoryProvider`; `deviceNameProvider`)
- Test: `test/sync/device_identity_test.dart`, `test/sync/peer_repository_test.dart`

**Interfaces:**
- Produces:
  - `class DeviceIdentity`, with:
    - `final String certPem, keyPem, fingerprint`;
    - `static Future<DeviceIdentity> loadOrCreate(Directory syncDir)`: EC P-256 key and a self-signed certificate valid for 7,300 days, saved as `cert.pem` and `key.pem` (key file mode 0600 on Linux);
    - `SecurityContext serverContext()`;
    - `static String fingerprintOf(X509Certificate c)`.
  - `class PeerRepository`, with:
    - `PeerRepository(AppDatabase db)`;
    - `Stream<List<PeerRow>> watch()` (by name), `Future<PeerRow?> byId(String deviceId)`, `Future<void> save(PeerRow p)`;
    - `Future<void> setWatermarks(String deviceId, {required int sent, required int received, required DateTime at})`;
    - `Future<void> setAddress(String deviceId, String host, int port)`, `Future<void> remove(String deviceId)`.
  - **Device name:** settings key `device_name`, editable on the page (Task 11). The default is the hostname on desktop and `Android` on Android.

- [ ] **Step 1: Write the failing tests.**
  - `creates once and reloads the same fingerprint`.
  - `server context serves TLS on loopback`: bind `HttpServer.bindSecure` on `127.0.0.1:0`; a client with a `badCertificateCallback` sees a certificate whose `fingerprintOf` equals `fingerprint`.
  - Peer repository CRUD and watermarks.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: device identity and peers`).

### Task 6: SPAKE2 and the pairing code

**Files:**
- Create: `lib/sync/spake2.dart`, `lib/sync/pairing_code.dart`
- Test: `test/sync/spake2_test.dart`, `test/sync/pairing_code_test.dart`

**Interfaces:**
- Produces:
  - `class Spake2`: RFC 9382 with the P256-SHA256-HKDF-HMAC-SHA256 suite. The M and N points are copied from RFC 9382 §6. Arithmetic uses `pointycastle` `ECCurve_secp256r1`.
    - `Spake2.initiator(BigInt w, {required List<int> idA, required List<int> idB, Random? random})` and `Spake2.responder(...)`, with the same parameters;
    - `Uint8List get message` (the uncompressed point);
    - `Spake2Keys finish(Uint8List peerMessage)`, which throws `FormatException` for a point that is off the curve or the identity.
  - `class Spake2Keys { final Uint8List ke, myConfirm, peerConfirm; }` (`myConfirm` is the MAC this side sends; `peerConfirm` is the MAC it expects).
  - `BigInt pairingScalar(String code)` = `SHA-256(utf8('songies-pair-v1') ‖ utf8(code))` as an unsigned integer mod n.
  - `Uint8List pairKeyFrom(Uint8List ke)` = HKDF-SHA256(ikm `ke`, info `'songies pair key v1'`, 32 bytes). This derived key replaces §8.2's random key sent by A. Both are equally secret.
  - `class PairingCode`, with:
    - `PairingCode({Random? random, DateTime Function() now = DateTime.now})`;
    - `String get code`, `bool get usable` (not expired after 5 min and fewer than 5 failures);
    - `void chargeAttempt()`, with `static const maxAttempts = 5`.
  - **Roles:** the device that types the code is the RFC "A" (initiator), and `idA` is its certificate fingerprint. The device showing the code is "B", and `idB` is the fingerprint the initiator saw over TLS. Both use the lowercase hex strings as bytes.

- [ ] **Step 1: Write the failing tests.**
  - `matches the RFC 9382 P-256 test vector`: use the first P256-SHA256-HKDF-HMAC-SHA256 vector in RFC 9382 Appendix B, with fixed scalars x, y and its w. Assert `message` for both sides, the shared K, `ke` and both confirmation MACs.
  - `same code gives the same pair key on both sides`.
  - `different codes fail confirmation`.
  - `different idB (a MITM certificate) fails confirmation`.
  - `rejects an off-curve point`.
  - `PairingCode expires after 5 minutes and dies after 5 failures`, with an injected `now`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: SPAKE2 pairing primitives`).

### Task 7: HTTPS server, signed requests and pairing

**Files:**
- Create: `lib/sync/sync_auth.dart`, `lib/sync/sync_server.dart`, `lib/sync/sync_client.dart`, `lib/sync/pairing_service.dart`
- Test: `test/sync/sync_auth_test.dart`, `test/sync/pairing_service_test.dart` (loopback)

**Interfaces:**
- Consumes: `DeviceIdentity`, `PeerRepository`, `Spake2`, `PairingCode`.
- Produces:
  - **Request signing:**
    - `String signRequest(Uint8List pairKey, {required String method, required String pathAndQuery, required int timeMs, required String bodyHash})` returns base64 HMAC-SHA256 over `"$method\n$pathAndQuery\n$timeMs\n$bodyHash"`.
    - `bodyHash` is the hex SHA-256 of a JSON body, or the literal `stream` for file bodies, which are verified by content instead.
    - Headers: `x-songies-device`, `x-songies-time`, `x-songies-sig`.
  - **Verification:**
    - `class RequestVerifier { RequestVerifier(PeerRepository peers, {DateTime Function() now}); Future<VerifyResult> verify(HttpRequest req, String bodyHash); }`
    - `enum VerifyResult { ok, unknownDevice, stale, badSignature, replay }`; replay is a signature seen within the last 120 s.
  - **Server:**
    - `typedef Handler = Future<void> Function(HttpRequest req, String? peerId);`
    - `class SyncServer { SyncServer(DeviceIdentity id, RequestVerifier v); void route(String method, String path, Handler h, {bool open = false}); Future<int> start({int preferredPort = 47823}); Future<void> stop(); }`
    - It binds `InternetAddress.anyIPv4`. Path prefixes are matched for `/files/`. JSON bodies are capped at 32 MB. Route failures map to `401 {"error":"unknown_device"}`, `401 {"error":"auth"}`, and `409 {"error":"schema"}`.
  - **Client:**
    - `class SyncClient`, with:
      - `SyncClient.pinned({required String host, required int port, required String fingerprint, required Uint8List pairKey, required String myDeviceId, Duration clockOffset = Duration.zero})`;
      - `SyncClient.open({required String host, required int port})`, which accepts any certificate and exposes `String? seenFingerprint`;
      - `getJson`, `postJson`, `getFile(path, {int from = 0}) → Stream<List<int>>`, `putFile(path, Stream<List<int>>, {int from = 0, required int total})`, `close()`.
    - Failures throw `SyncNetError(SyncNetKind kind, String message)` with `enum SyncNetKind { unreachable, timeout, wrongCertificate, unknownDevice, auth, schema, busy, server }`.
  - **Pairing:**
    - `class PairingService`, with:
      - `PairingService({required DeviceIdentity identity, required PeerRepository peers, required String myDeviceId, required String Function() myName})`;
      - `void register(SyncServer s)`, which adds the open routes `POST /pair/start` and `POST /pair/finish`;
      - `PairingCode showCode()`, `void hideCode()`, `Stream<PeerRow> get paired`;
      - `Future<PairOutcome> pairWith(String host, int port, String code)`.
    - `enum PairOutcome { paired, wrongCode, noCodeShowing, unreachable }`.
    - Messages:
      - `/pair/start`: `{msg, id_a, device_id, name}` → `{msg, confirm, device_id, name}`;
      - `/pair/finish`: `{confirm}` → `{ok:true}`.
    - The responder accepts one pairing exchange at a time. It refuses with 403 when the code is not `usable`, and otherwise calls `chargeAttempt()` on every `/pair/start` before `Spake2.finish`, whether that succeeds or throws. Both sides save a `PeerRow` with the peer's fingerprint and `pairKeyFrom(ke)`.

- [ ] **Step 1: Write the failing tests.**
  - `verifier accepts a fresh signature and rejects stale, replayed, tampered and unknown`.
  - `pairs over loopback with the right code` (both peers saved, equal keys, each holds the other's fingerprint).
  - `wrong code five times invalidates the code`.
  - `expired code is refused`.
  - `wrong pinned fingerprint is refused` (`SyncNetKind.wrongCertificate`).
  - `a fake device showing pairing learns nothing usable`: an attacker server records the initiator's `/pair/start`, and offline trial of all 10^6 codes against the recorded message cannot confirm, because confirmation needs the attacker's own reply. Assert by construction: running `finish` on the recorded message with the right code but a different random scalar does not reproduce the initiator's `myConfirm`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: sync transport and pairing`).

### Task 8: The sync run (initiator and responder)

**Files:**
- Create: `lib/sync/sync_runner.dart`, `lib/sync/sync_responder.dart`, `lib/sync/sync_progress.dart`
- Test: `test/sync/sync_run_test.dart` (two in-memory DBs, two loopback servers)

**Interfaces:**
- Consumes: `ChangeFeed`, `RowApplier`, `Merger`, `DbLocalView`, `SyncClient`, `SyncServer`, `PeerRepository`, `DownloadRepository.queueNewInEnabled()`, `FileTransfer` (Task 9; pass a no-op until then).
- Produces:
  - **Progress:**
    - `enum SyncStage { hello, pulling, merging, choosing, applying, files, finishing }`
    - `sealed class SyncProgress`, with `SyncStep(SyncStage stage, {int done = 0, int total = 0})`, `SyncDone(SyncSummary s)` and `SyncFailed(SyncFailure f)`.
    - `class SyncSummary { final String peerName; final int playlistsChanged, songsAdded, filesCopied; }`
    - `enum SyncFailure { notFound, schemaMismatch, busy, forgotten, cancelled, network }`
  - **Runner:**
    - `class SyncRunner { Stream<SyncProgress> run(PeerRow peer, {required String host, required int port, required Future<Map<String, Resolution>?> Function(List<PlaylistClash>) choose, SyncCancel? cancel}); }`
    - A null result from `choose` means the user left, which ends as `cancelled`.
    - `class SyncCancel { void cancel(); bool get isCancelled; }`
  - **Responder:**
    - `class SyncResponder { void register(SyncServer s); Stream<ResponderState> get state; }`
    - `sealed ResponderState`: `Idle`, `WaitingFor(String peerName)`, `Receiving(SyncStage, done, total)`, `ResponderDone(SyncSummary)`.
  - **Routes** (all signed except `/hello`):
    - `GET /hello` → `{device_id, name, app_version, schema_version, time_ms}`;
    - `POST /session/begin {sync_id}` (409 `busy` if a session is open, or this device is itself running a sync);
    - `GET /changes?since=&cursor=&limit=` → `{rows, next, high}`;
    - `POST /apply/part {sync_id, rows}` (at most 500 rows per part), `POST /apply/commit {sync_id}` (applies every staged row in one transaction, returns `ApplyReport` counts);
    - `POST /commit {sync_id, initiator_high, responder_high}`, `POST /session/abort {sync_id}`;
    - `POST /unpair`.

**Run order (initiator):**
1. **Hello.** `clockOffset = time_ms − now` is used for every later signature. A schema mismatch ends as `schemaMismatch`.
2. **Begin.**
3. **Pull** R's changes since `lastReceivedSeq`, keeping `responderHigh`.
4. **Read own changes.** Read the initiator's changes since `lastSentSeq` and take `initiatorHigh = highSeq()` *before* applying anything.
5. **Merge, then `choose`** if there are clashes; R shows `WaitingFor`.
6. **Resolve,** then `RowApplier.apply(F)` locally.
7. **Send F** in parts, then `/apply/commit`.
8. **`/commit`.** R saves `lastReceivedSeq = initiatorHigh` and `lastSentSeq = responderHigh`, then the initiator saves its own mirror and `lastSyncAt`.
9. **Files.**
10. **Downloads.** `queueNewInEnabled()` runs on both sides; R does it after `/commit`.

**Ending early:**
- **Cancel before step 6:** sends `/session/abort` and changes nothing.
- **An idle responder session:** dropped after 15 minutes with its staged rows discarded.
- **Unknown device:** a 401 `unknown_device` from the peer ends as `forgotten`.

- [ ] **Step 1: Write the failing tests.**
  - `first sync makes both databases equal` (compare with `snapshot`).
  - `second sync writes nothing`.
  - `changes travel A to B to C`.
  - `first sync dedupes shared songs` (Review Focus 3).
  - `clash goes to choose and keepBoth makes a copy on both sides`.
  - `choose returning null cancels and changes nothing`.
  - `failure after pull leaves both databases and watermarks unchanged`.
  - `failure after the initiator applies leaves watermarks unchanged, and a rerun converges`.
  - `write between pull and apply survives` (Review Focus 2).
  - `clock skew of 10 minutes still syncs` (Review Focus 1, with the responder's `now` shifted).
  - `abandoned session times out` (Review Focus 5, with `fake_async` or an injected timer).
  - `schema mismatch fails cleanly`.
  - `busy peer fails as busy`.
  - `unpaired peer fails as forgotten`.
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/sync/sync_run_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: two-way sync run`).

### Task 9: File transfer

**Files:**
- Create: `lib/sync/file_transfer.dart`
- Modify: `lib/theme/font_service.dart` (`loadImported` skips families already in `_registered`), `lib/sync/sync_runner.dart`, `lib/sync/sync_responder.dart`
- Test: `test/sync/file_transfer_test.dart`

**Interfaces:**
- Consumes: `LibraryScanner.importFile(String path)`, `FontService.loadImported()`, `AppPaths` (`libraryLocal`, `fonts`, `art`).
- Produces:
  - `enum FileKind { audio, font, art }`
  - `class FileRef { final FileKind kind; final String name; final String? ext; final int have; }`. `name` is a 64-char lowercase hex hash for audio and fonts, and an art ref matching `^(yt2-)?[0-9a-f]{64}\.jpg$` for art. `have` is the size of an existing `.part`.
  - `class FileTransfer`, with:
    - `Future<List<FileRef>> needs()`, listing:
      - live local tracks with a `fileHash` and no `local_files` row in state `done`;
      - live fonts whose file is missing;
      - `artworkRef` and `coverRef` values of live tracks and playlists that look like art refs and whose file is missing;
    - `Future<File?> locate(FileRef r)`: audio comes from the `done` `local_files` path of the live track with that hash, fonts from the fonts dir, art from the art dir;
    - `Future<bool> receive(FileRef r, Stream<List<int>> bytes, {required int total})`: appends to `<dir>/<name>[.<ext>].part` from `r.have`. When complete, audio and fonts are verified by SHA-256 (art by size only, because its ref hashes the source image). The file is then renamed. Afterwards audio goes through `importFile`, fonts through `loadImported`, and art needs nothing more.
    - `Stream<FileProgress> exchange(SyncClient c, {SyncCancel? cancel})`, run by the initiator: it pulls its own needs with `GET /files/<kind>/<name>` (Range from `have`), then asks `GET /files/missing` and pushes R's needs with `PUT /files/<kind>/<name>?ext=&from=&total=`. Files go one at a time.
  - `class FileProgress { final int done, total; final String? current; }`
- **Rules:**
  - Received audio is stored at `<appData>/library/local/<sha256>.<ext>`. `ext` is the sender's lowercase extension, taken from the scanner's supported list. Anything else is refused.
  - A hash mismatch deletes the `.part` and retries once, then skips.
  - A 404 (the source is gone) skips the file.
  - A name not matching the patterns gets a 400.
  - Cancel keeps `.part` files.

- [ ] **Step 1: Write the failing tests.**
  - `needs lists missing audio, fonts and art`.
  - `copies an MP3 and attaches it to the synced track` (`local_files` is `done` at the new path).
  - `resumes from a partial file`.
  - `hash mismatch retries once then skips`.
  - `missing source is skipped and the song still syncs`.
  - `received font is registered` (fake `FontRegistrar`).
  - `rejects path traversal names`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement and wire into the run** (step 9 of Task 8; R's `Receiving(files, …)` progress).
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: copy audio, fonts and covers during sync`).

### Task 10: Discovery and the sync host

**Files:**
- Modify: `pubspec.yaml` (`bonsoir: ^7.1.0`), `android/app/src/main/AndroidManifest.xml` (the permissions bonsoir's README lists for Android NSD, at least `ACCESS_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE`)
- Create: `lib/sync/discovery.dart`, `lib/sync/sync_host.dart`
- Modify: `lib/providers.dart` (`syncHostProvider`, autoDispose)
- Test: `test/sync/sync_host_test.dart` (a `FakeDiscovery`, loopback servers)

**Interfaces:**
- Consumes: everything from Tasks 5–9.
- Produces:
  - **Discovery:**
    - `class FoundDevice { final String id, name, host; final int port; final bool pairing; }`
    - `abstract class Discovery { Future<void> advertise({required String id, required String name, required int port, required bool pairing}); Future<void> stopAdvertising(); Stream<List<FoundDevice>> get found; Future<void> startBrowsing(); Future<void> dispose(); }`, plus `BonsoirDiscovery implements Discovery`.
    - Changing `pairing` re-advertises. The device's own id is filtered out.
  - **Host:**
    - `class SyncDeviceView { final PeerRow peer; final FoundDevice? online; }`
    - `class SyncHost`, with:
      - `Future<void> start()` (server, responder, pairing routes, advertise, browse) and `Future<void> stop()`;
      - `Stream<List<SyncDeviceView>> get devices`, `Stream<ResponderState> get responder`;
      - `PairingCode showCode()` (advertises `pairing=1`), `void hideCode()`;
      - `Future<FindOutcome> pairByCode(String code)`: tries every found device with `pairing`, in turn, until one pairs, within **10 s overall**, including waiting for discovery to report devices;
      - `Future<PairOutcome> pairByAddress(String host, int port, String code)`;
      - `Stream<SyncProgress> sync(String peerId, {required Future<Map<String, Resolution>?> Function(List<PlaylistClash>) choose, SyncCancel? cancel})`. It uses the address from `found` matched by device id (and stores it with `setAddress`), falls back to the stored address, and else emits `SyncFailed(notFound)`;
      - `Future<void> unpair(String peerId)` (a best-effort signed `POST /unpair`, then removes the peer);
      - `Future<List<String>> localAddresses()` (non-loopback IPv4).
    - `enum FindOutcome { paired, noneFound, wrongCode }` (`wrongCode` when devices answered but none matched).
    - After a successful pairing, the device that typed the code starts `sync` immediately.
    - **Android:** an `AppLifecycleListener` stops the host on `paused` and restarts it on `resumed`, unless a run is in progress.

- [ ] **Step 1: Write the failing tests.**
  - `pairByCode tries each pairing device and pairs with the right one`.
  - `pairByCode reports noneFound after 10 seconds`.
  - `own advertisement is ignored`.
  - `remembered peer at a new address` (Review Focus 4: the stored address is stale, `found` has the new one, and the sync succeeds and stores it).
  - `remembered peer not on the network fails as notFound`.
  - `showCode advertises pairing and hideCode clears it`.
  - `stop closes the server and the advertisement`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests and analyze, then build `flutter build apk --release` and `flutter build linux --release` to check the plugin links.**
- [ ] **Step 5: Commit** (`feat: device discovery and sync host`).

### Task 11: The Sync devices page

**Files:**
- Create: `lib/ui/settings/sync/sync_devices_page.dart`, `pair_sheets.dart` (Show a code, Enter a code, Connect by address), `clash_dialog.dart`, `sync_progress_card.dart`
- Modify: `lib/ui/settings/settings_page.dart` (a "Sync devices" tile), `lib/router.dart` (`/settings/sync`)
- Test: `test/ui/sync_devices_page_test.dart` (a fake `SyncHost` through a provider override)

**Interfaces:**
- Consumes: `syncHostProvider`, `deviceNameProvider`, `SyncHost`, `PlaylistClash`, `Resolution`, `SyncProgress`, `ResponderState`.

**Content** (copy as in Global Constraints):
- **This device:** its name (editable) and, in the Show-a-code sheet, its IP addresses and port, for Connect by address.
- **Your devices:** name, "Last synced …" or "Never synced", and an online dot. Tap to sync. The ⋯ menu has **Unpair**, with a confirmation.
- **Pair a new device:** **Show a code** and **Enter a code**.
  - The code is shown large, with a 5-minute countdown. Pairing success closes the sheet.
  - Enter a code is a 6-digit field. `noneFound` and `wrongCode` show the no-device message and a **Connect by address** button.
- **The note** "The other device needs Sync devices open too."
- **Firewall help:**
  - Linux: `sudo firewall-cmd --permanent --add-port=47823/tcp`, `sudo firewall-cmd --permanent --add-service=mdns`, `sudo firewall-cmd --reload`, with a copy button.
  - Windows: "Windows may ask to allow Songies on private networks. Allow it."
- **While syncing:**
  - the stage label ("Connecting", "Fetching changes", "Merging", "Saving", "Copying files 3 of 12", "Finishing") with a progress bar and **Cancel**;
  - on the responder side, "Waiting for \<name\>…" or the same progress;
  - afterwards, the summary line.
- **Failures:** each `SyncFailure` has a message. `notFound` uses the spec copy with **Try again**. `forgotten` is "\<name\> no longer recognises this device. Unpair and pair again."
- **Clash dialog:** one per playlist, in turn.
  - It shows the name and "Changed on both devices", or "Deleted on \<x\>, changed on \<y\>".
  - It has three buttons, and **Keep both** is hidden when `theirsDeleted`.
  - Dismissing it, or leaving the page, returns null.

- [ ] **Step 1: Write the failing widget tests.**
  - `shows paired devices with online state`.
  - `enter code success starts a sync and shows the summary`.
  - `none found offers connect by address`.
  - `clash dialog hides keep both when theirs is deleted`.
  - `leaving during choices cancels`.
  - `linux shows firewall commands`.
  - `unpair asks first`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.** The layout follows the existing settings pages (`youtube_settings.dart`) and works at phone and desktop widths.
- [ ] **Step 4: Run all tests and analyze.**
- [ ] **Step 5: Commit** (`feat: Sync devices page`).

### Task 12: Checks, docs and builds

**Files:**
- Modify: `docs/manual-test-checklist.md` (a Plan 10 section), `docs/PROGRESS.md`, `README.md` (a sync paragraph and firewall note)
- Create: `docs/plan-10-session-log.md`

- [ ] **Step 1: Write the Plan 10 checklist section.** It covers:
  - pairing by code for phone↔Linux, phone↔Windows and Linux↔Windows;
  - a wrong code; Connect by address;
  - a sync with music playing; a clash with each choice;
  - deleting a playlist on one device and editing it on the other;
  - a large library's first sync; an MP3 and a font arriving and working;
  - A→B→C forwarding; Unpair; the firewall steps; the Android app paused mid-page.
- [ ] **Step 2: Run the full checks.** Run `flutter analyze`, `flutter test`, `flutter build apk --release` and `flutter build linux --release`. Record the counts and sizes.
- [ ] **Step 3: Update `PROGRESS.md` and the session log.** Note what is done, what is unverified on devices, and the next step (device checks, then packaging).
- [ ] **Step 4: Commit** (`docs: Plan 10 checklist and progress`).
