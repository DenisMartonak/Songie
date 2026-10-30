# Plan 10 (device sync) — session log

_2026-10-30. Paused by the user during Task 9._

## Where things stand

- **Branch:** `plan-10-device-sync` (made from `plan-9-stats`). Nothing pushed or merged. Working tree clean.
- **Spec:** [device sync design](superpowers/specs/2026-10-30-songies-device-sync-design.md) (commit `605d6ab`, which also sits on `plan-9-stats`). **Plan:** [Plan 10](superpowers/plans/2026-10-30-songies-plan-10-device-sync.md).
- **Done, each reviewed and its fixes re-reviewed:** Tasks 1–8 of 12. Last full test run: 1,880 passing, `flutter analyze` clean. No release builds yet. Nothing run on a device.
- **Stopped:** Task 9 (file transfer). Its agent was stopped before it committed anything. Not started: Task 10 (discovery and sync host), Task 11 (Sync devices page), Task 12 (checklist, docs, builds), then the whole-branch review.
- **To resume:** "Songies Plan 10 is on branch `plan-10-device-sync`; Tasks 1–8 are done and reviewed. Resume with Task 9 using subagent-driven development. Read docs/plan-10-session-log.md and the ledger at .superpowers/sdd/2026-10-30-songies-plan-10-device-sync/progress.md. Don't merge."
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

## Worth knowing

- **The other device must have Sync devices open.** There is no background server (the main design's "no idle work").
- **Known limit:** a rename on one device and a cover change on the other, to the same playlist, count as a clash, because no base version is kept.
- **Security trade-off:** the SPAKE2 elliptic-curve maths isn't constant-time, which RFC 9382 asks for. I judged the risk low (single-use secrets, a 5-minute code, 5 attempts).
- **Commit trailers:** commits by subagents name their own model (Sonnet or Opus) in Co-Authored-By.
