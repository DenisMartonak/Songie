# Plan 10 (device sync) — session log

_2026-10-30. Tasks 1–12 done; the whole-branch review is next._

## Where things stand

- **Branch:** `plan-10-device-sync` (made from `plan-9-stats`). Nothing pushed or merged.
- **Spec:** [device sync design](superpowers/specs/2026-10-30-songies-device-sync-design.md) (commit `605d6ab`, which also sits on `plan-9-stats`). **Plan:** [Plan 10](superpowers/plans/2026-10-30-songies-plan-10-device-sync.md).
- **Done:** Tasks 1–11 each reviewed with fixes re-reviewed; Task 12 (checklist, docs, builds) done. Last full run: 1,940 tests passing (the known flaky `stats_repository_test` "under 500 ms" passed this time; it may fail under load), `flutter analyze` clean. `flutter build apk --release` succeeds (83.2 MB). `flutter build linux --release` succeeds (bundle 36 MB). Windows is built on the user's PC. Nothing has been run on a device.
- **Next:** the whole-branch review (the controller runs it), then the device checks in the Plan 10 section of the [manual checklist](manual-test-checklist.md), then packaging.
- The run ledger (git-ignored) is at `.superpowers/sdd/2026-10-30-songies-plan-10-device-sync/progress.md`. It holds every ruling, deferred minor, brief, report and review.

## What the user decided (brainstorming)

- Pair by code: one device shows a 6-digit code, the other types it, and the app finds the device on the network. There's no list to pick from.
- Devices remember each other. A later sync is one tap, and Unpair is available.
- Sync goes both ways, and deletions carry over.
- The conflict prompt (Keep this device's / Keep \<peer\>'s / Keep both) appears only for real clashes. Changes to different parts of a playlist combine silently.
- Execution: subagent-driven.

## Commits

| Task | Commits | What |
|---|---|---|
| Design, plan | `605d6ab`, `6b3c95c`, `49002ed` | Spec, plan, and a plan correction (pairing attempts) |
| 1 | `5191d52` | Schema 8: `peers` table, `mergedInto` on tracks and playlists, `local_seq` indexes, strict clock parsing, `SyncStamp.reserve`, re-adding a deleted MP3 revives its row |
| 2 | `46b3d2a` | `SyncRow` wire format and content hash, `ChangeFeed` |
| 3 | `4cedc0a`, `512f974` | `RowApplier`: applies rows, merges duplicates onto the smaller id. The fix made lyrics merge deterministically and let upserts write nulls |
| 4 | `6a1ea4c`, `6b5924e` | `Merger`: winners, per-playlist clashes and the three choices. The fix stopped merge tombstones from counting as user deletions |
| 5 | `2f8b868`, `9d609a6` | `DeviceIdentity` (self-signed EC certificate) and `PeerRepository`. The fix stopped silent certificate regeneration and made key writes atomic |
| 6 | `79d9df1`, `bd58905` | SPAKE2 (RFC 9382 P-256, passes the RFC vector) and `PairingCode`. The fix counts every attempt and requires exactly 6 digits |
| 7 | `c0e6e49`, `2c89be1` | HTTPS server, signed requests, pinned client, pairing endpoints. The fix: a stray finish no longer cancels pairing, peer ids are validated, the expiry is rechecked |
| 8 | `c51644d`, `4f1b27e` | `SyncRunner` and `SyncResponder` (hello, pull, merge, choose, apply, commit). The fix: a safe watermark, so a change saved mid-sync isn't skipped, plus tighter sessions |
| 9 | `103d51e`, `7d42ba4` | File transfer: audio, fonts and covers copied in both directions, with progress. The fix: files are counted both ways, only live covers are served, stalled transfers time out |
| 10 | `d6fb1fe`, `312146f` | Device discovery (mDNS) and `SyncHost`. The fix: robust teardown, and dispose cancels its own runs |
| 11 | `32f13dd`, `4fc945b` | The Sync devices page. The fix: it serves only while visible |
| 12 | docs commit | Plan 10 checklist, README note, progress docs, final checks and builds |

## Rulings I made (cost if wrong in each)

- Ruling 1: T8 takes a nullable files step `Future<int> Function(SyncClient c, SyncCancel? cancel)?` (returns files copied); T9 wires FileTransfer.exchange into it — keeps T8 testable before T9 — cost if wrong: small rewiring in T9.
- Ruling 2: Pairing order is responder-confirms-first: /pair/start returns the responder's confirm; the initiator checks it and sends /pair/finish only on a match. The fake-device test asserts that, against a responder using a wrong code, the initiator reports wrongCode and never sends /pair/finish (so nothing brute-forceable leaves the initiator) — spec anti-goal is "stranger can't pair", this tests it directly — cost if wrong: test rewrite only.
- Ruling: subagent commits carry their own model's Co-Authored-By line (e.g. Sonnet) instead of the Opus line in the plan — attribution should name the model that wrote the code — cost if wrong: trailer text only.
- Ruling: Task 3 fix round may change lib/sync/sync_row.dart (Task 2 code): toInsertable returns toCompanion(false) so upserts can set nulls — the defect is real and the applier is its first consumer — cost if wrong: none (Task 2 tests re-run).
- Ruling: PlaylistClash.name may be null when only entries clash; Task 8's runner fills it from the local playlist row before calling choose — merge stays pure — cost if wrong: one lookup moved.
- Ruling: when this device deleted the playlist, "their view" treats this device's entry tombstones as live (deletePlaylist tombstones all entries) — otherwise edit-wins / Keep both would yield an empty playlist — cost if wrong: a song removed individually before the delete reappears in the restored/copied playlist.
- Ruling: two tombstones of the same row never clash; higher clock wins — both sides want it deleted — cost if wrong: none visible.
- Ruling: Task 4 Minor 1 (entry grouped by mine's playlistId after a one-sided playlist merge) goes into fix round 1 with Important #1 — same root cause (merge tombstones vs clash grouping) — cost if wrong: slightly larger fix diff.
- Ruling: corrupt identity files — regenerate only when the PEM files exist but cannot be parsed/loaded (log a warning without secrets, keep the old files as cert.pem.bak/key.pem.bak); a read I/O error is rethrown, never overwritten — regeneration is the only way forward for a broken cert, but transient errors must not destroy pairings — cost if wrong: user re-pairs after corruption.
- Ruling: Task 5 Minors on write order/atomicity and unchecked chmod join fix round 1 — they cause the same silent regeneration — cost if wrong: slightly larger diff.
- Ruling: accept pointycastle's non-constant-time EC scalar multiplication in SPAKE2 despite RFC 9382 §7 — scalars are single-use, the code lives 5 min with 5 attempts, and a LAN timing attack on a Dart VM gains at most a narrowed online guess; no maintained constant-time P-256 exists for Dart — cost if wrong: weaker pairing against a sophisticated local attacker; surface to user.
- Ruling: each /pair/start that reaches Spake2.finish charges one attempt on the PairingCode (whether finish throws or succeeds, before replying); 5 attempts exhaust the code. Task 6 fix updates PairingCode docs/naming accordingly; Task 7 must call it on every start — with responder-confirms-first, an online attempt is one guess, so attempts not confirmations are what to cap — cost if wrong: a legit user who mistypes 5 times needs a new code (same as spec).
- Ruling: Task 6 Minors 1, 3, 4 join fix round 1 (cheap, same files, security-relevant: K-at-infinity test, 6-digit assert); Minors 2 and 5 deferred.
- Ruling: a new /pair/start replaces an unfinished exchange (no busy lock until /pair/finish is saving) — with responder-confirms-first a wrong-code initiator never finishes, so a lock would block retries; each disruption costs an attacker one of 5 attempts — cost if wrong: a LAN attacker can interrupt pairing (user retries with a fresh code).
- Ruling: SyncClient.fetchFingerprint() pre-connect to learn idB, then the open client accepts only that cert — needed to build pA — cost if wrong: none.
- Ruling: schema mismatch during pairing reports as `unreachable` (PairOutcome has no version case) — rare (both devices usually same version), and the first sync right after pairing reports schemaMismatch clearly — cost if wrong: confusing "not found" message when versions differ at pairing time.
- Ruling: responder's saved peer has no host/port; Task 10 fills it from discovery — cost if wrong: none.
- Ruling: Task 7 Minors 2 (repeated header → 500), 3 (device_id unvalidated), 4 (expiry not rechecked at finish), 5 (errors escaping SyncNetError contract) join fix round 1 — they are input-validation/contract issues on the network boundary — cost if wrong: slightly larger fix.
- Ruling: Task 8 run order stages all rows on the responder (/apply/part) before the initiator applies locally, then /apply/commit — strictly safer than the plan's order (a break or cancel before the local apply changes neither side) — cost if wrong: none.
- Ruling: summary-count fix lives in RowApplier's ApplyReport (one row_applier_test expectation 1→0) — the counts are the applier's to report honestly — cost if wrong: none.
- Ruling: if a run breaks after the initiator applied a resolved clash but before the responder committed, the rerun asks about that clash again — follows from the relaxed interruption rule; rare — cost if wrong: one repeated prompt.
- Ruling: Task 8 Important (watermark past an uncommitted stamped row) is fixed with a safe watermark, not by moving 37 stamp call sites into transactions: SyncStamp remembers seqs it issued in the last 60 s (in memory); ChangeFeed gets `safeHigh()` = min(highSeq, lowest recently-issued seq with no row in any synced table − 1); the runner and responder use safeHigh() for watermarks. A legit gap (rolled-back write, reserve without a row) only holds the watermark back ≤60 s, which just resends rows next time (applier no-ops them) — cost if wrong: a write that lands >60 s after its stamp could still be skipped (none known; scanner stamps immediately before inserting).
- Ruling: Task 8 Minors 1 (/commit uses the responder's own served high, 409 on mismatch/none), 3 (same-peer /session/begin replaces its own stale session), 4 (tests for session checks), 6 (cancelling the progress subscription cancels the run) join fix round 1 — session-correctness and user-visible behaviour — cost if wrong: larger fix.
- Ruling: Task 9 files hook returns Stream<FileProgress> (not Future<int>) so the initiator shows "3 of 12" — amends Ruling 1 — cost if wrong: none.
- Ruling: added POST /files/have and POST /files/done; file routes require the paired peer's committed session; /files/done ends the session; uploads accepted only for files the receiver lacks — needed for sizes/exts and to stop planted files — cost if wrong: two extra routes.
- Ruling: "N files copied" in the summary counts files moved in both directions on both devices — the user reads it as what the sync copied — cost if wrong: number semantics only. (Goes into Task 9 fix round.)
- Ruling: Task 9 Minors 1 (stalled transfer holds session), 2 (/files/done best effort), 3 (security-path tests), 6 (received file revives a track deleted mid-copy), 7 (attach failure re-downloads) join fix round 1 — user-visible or data-correctness — cost if wrong: larger fix.
- Ruling: SyncHost exposes a settable `choose` clash handler and `Stream<HostRun> runs` (progress replays to late listeners) so the post-pairing sync reaches the UI; the page calls start() — cost if wrong: Task 11 wiring only.
- Ruling: a pairing attempt still running at pairByCode's 10 s deadline is abandoned, not cancelled; if it later succeeds the peer is saved (shows in Your devices) without an automatic first sync — rare; one tap syncs — cost if wrong: a confusing "not found" followed by the device appearing.
- Ruling: Task 10 Minors 1 (sync() errors → SyncFailed), 2 (clear pairing=1 when the code is used up/expired), 4 (dispose services if server.start throws), 5 (dedupe found devices by id, newest wins) join fix round 1; also: if mDNS start fails (e.g. Linux without Avahi) the server still runs so Connect by address works — teardown/robustness on real devices — cost if wrong: larger fix.
- Ruling: summary uses singular forms for 1 ("1 playlist changed") — natural English over literal "N playlists" — cost if wrong: wording only.
- Ruling: isWindowsProvider added for the Windows firewall note — cost if wrong: none.
- Ruling: Sync devices open in a background tab (shell keeps branches mounted) must stop serving/advertising while the page is not visible, and resume when visible again unless a run is in progress — spec anti-goal "server left running outside the screen" — goes into Task 11 fix round — cost if wrong: a returning user waits a moment for discovery.
- Ruling: Task 11 Minors 1 (pair buttons disabled while a run is unfinished), 2 (test answers host.choose after pairing), 3 (mounted check after rename dialog), 4 (Cancel/Try again colour via readableOn), 7 (log pairByCode errors) join fix round 1 — user-visible correctness, contrast rule — cost if wrong: larger fix.

## Deferred minor findings (for the final review)

- Task 1: minor (deferred): scanner fast path does an extra PK lookup per unchanged file
- Task 1: minor (deferred): doc comment placed above `_canonical` in hlc.dart
- Task 1: minor (deferred): reserve(0) without observed clock does a no-op settings write
- Task 2: minor (deferred): SyncRow.fromWire throws StateError/TypeError on malformed payloads — carry to Task 7/8: server must answer 400, not 500
- Task 2: minor (deferred): no change_feed test with several rows of one table across a page boundary
- Task 3: minor (deferred): tracksAdded counts merges as added songs; playlistIds includes merged-away losers and tombstone-entry playlists — carry to Task 8 (summary counts)
- Task 3: minor (deferred): references restamped on already-tombstoned rows (extra traffic)
- Task 3: minor (deferred): no tests for font merging, rule 6 for playlists, prefs OR with loser false
- Task 3: minor (deferred): row_applier.dart 520 lines; ignore prefer_initializing_formals at :54 may be unneeded
- Task 4: minor (deferred): untested paths keepBoth when mineDeleted, keepMine when theirsDeleted, loser pass-through entries in _editWins
- Task 4: minor (deferred): _view(theirs:true) also overlays c.mine (harmless, confusing)
- Task 4: minor (deferred): sync→library import only for maxPlaylistNameLength
- Task 4: minor (deferred): copies spread base.data incl. localSeq/coverRef
- Task 4: minor (deferred): an entry rewritten by a merge on one side and moved by the user on the other still prompts (no-base-version limit)
- Task 5: minor (deferred): existing key.pem with looser permissions never tightened on load
- Task 5: minor (deferred): providers.dart import order; no test for deviceNameProvider default
- Task 5: minor (deferred): non-UTF-8 PEM throws FormatException outside the try (fail-safe, no regeneration); repeated regeneration overwrites .bak
- Task 6: minor (deferred): Spake2 keeps K in _k for debugSharedPoint; spake2.dart imports flutter/foundation only for @visibleForTesting
- Task 7: minor (deferred): server catches TypeError/StateError from handlers as silent 400 (log at debug)
- Task 7: minor (deferred): PairingService._paired never closed / no dispose; SyncServer.start() twice leaks — carry to Task 10 (owns lifecycle)
- Task 7: minor (deferred): no tests for 32 MB cap, 500 path, non-JSON body
- Task 7: minor (deferred): unauthenticated JSON bodies (≤32 MB) buffered before verification (Minor 10); Minor 9 per review file
- Task 8: minor (deferred): /changes checks peer but not sync_id; responder throws FormatException for >500 rows (relies on server mapping)
- Task 8: minor (deferred): SyncResponder._state never closed — carry to Task 10 (lifecycle)
- Task 8: minor (deferred): first-sync memory is O(all rows) on both sides — final review / manual large-library check
- Task 8: minor (deferred): stamp window pruning uses wall clock (forward jump >60 s reopens window); unawaited expect futures in sync_run_test:721-727
- Task 9: minor (deferred): empty .part left on refused PUT; art content not checked for JPEG magic bytes
- Task 9: minor (deferred): file_transfer.dart ~590 lines mixing concerns (split HTTP side)
- Task 9: minor (deferred): suite noise — flaky stats_repository "under 500 ms" timing test; W log lines from font_service_test
- Task 9: minor (deferred): after an attach failure the file stays at its final path and is re-downloaded next sync
- Task 10: minor (deferred): device-name change not re-advertised until next advertisement
- Task 10: minor (deferred): weak tests (localAddresses vacuous without IPv4; 50 ms _settle timing); sync_host.dart 573 lines
- Task 10: minor (deferred): no test for server.start throwing path in _startServing
- Task 11: minor (deferred): _dateTimeText duplicates settings_page helper; sync_devices_page.dart 586 lines
- Task 11: minor (deferred): fast visible→hidden→visible toggle can briefly enable pair buttons / set _startFailed from a stale start (heals itself)

## Worth knowing

- **The other device must have Sync devices open.** There is no background server (the main design's "no idle work").
- **Known limit:** a rename on one device and a cover change on the other, to the same playlist, count as a clash, because no base version is kept.
- **Security trade-off:** the SPAKE2 elliptic-curve maths isn't constant-time, which RFC 9382 asks for. I judged the risk low (single-use secrets, a 5-minute code, 5 attempts).
- **Commit trailers:** commits by subagents name their own model (Sonnet or Opus) in Co-Authored-By.
