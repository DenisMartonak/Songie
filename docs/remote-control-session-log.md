# Remote control (roadmap 5, step 3) — session log

Spec: [remote control design](superpowers/specs/2026-11-06-remote-control-design.md). Plan: [remote control plan](superpowers/plans/2026-11-06-remote-control.md).
Branch: `remote-control`, in the worktree `.worktrees/remote-control` of the main checkout (git-ignored through `.git/info/exclude`). It starts from `origin/claude/great-mccarthy-39er0g` (the design commit `080674c`). Not pushed, not merged. The main checkout's uncommitted work (volume memory, theme edits) is untouched.

Flutter is at `/home/deno/flutter/bin` (the plan's `~/development/flutter` path is wrong on this machine). There is no `supabase` CLI here.

## Status (2026-11-06)

Run with subagent-driven development: each task gets a fresh implementer and a fresh reviewer, plus a scoped re-review after each fix round.

| Task | What | Commits | Review |
|---|---|---|---|
| 1 | Protocol messages (`lib/remote/remote_protocol.dart`) | `5c295c9` | clean |
| 2 | Channel, fake hub, Realtime RLS migration | `1d83fe1`, `ff0eb5a` | clean after 1 fix round |
| 3 | Host (`remote_host.dart`), `tracksByIds`, checked edits in PlayerService | `9690a3c`, `6f81677` | clean after 1 fix round (lock race) |
| 4 | Controller (`remote_controller.dart`) | `ce296d0`, `67655dd` | clean after 1 fix round |
| 5 | PlayerView, device name, providers, main.dart wiring | `2b8c858` | approved, 1 parked |
| 6 | Player UI reads the view | — | **next** |
| 7 | Devices button, picker, strip | — | |
| 8 | Play on… menu entries, docs, release builds | — | |

After Task 8: one whole-branch review on the most capable model, one fix wave, then finishing the branch (you decide whether to merge or push).

Tests at Task 5: `test/remote/` and `test/providers_test.dart` pass (+99), and `flutter analyze` is clean. The full suite ran 2,434 passing and 1 failing (`themes_page_test` "Import saves a valid file and rejects a bad one", which passes on its own; probably flaky under load, still to be looked at).

## To resume in a new Claude session

> Continue the remote-control plan on branch `remote-control` in `.worktrees/remote-control`, with subagent-driven development, from Task 6. Read docs/remote-control-session-log.md first. Don't merge or push.

The SDD ledger is at `.worktrees/remote-control/.superpowers/sdd/2026-11-06-remote-control/progress.md`. It is git-ignored, and this file holds its contents.

## Carry into later tasks

- **Task 6/7:** switch on the link (`remoteLinkProvider`), not only on `states`. The controller emits an empty `PlayerState` on select and deselect.
- **Task 7:** `remoteEndedProvider` is a `Provider<Stream<(RemotePresence, RemoteEndReason)>>`, not a StreamProvider, because Riverpod 3 drops values equal to the previous one. The island subscribes to the stream itself and subscribes again whenever the provider rebuilds (each controller change). It must not lose the queued `(device, signedOut)` end on sign-out; add a test for that.
- **Task 7:** `RemoteController.select` doesn't check `compatible`. The picker must grey out and disable devices with another protocol version.
- **Task 8:** `RemoteController.sendTo` is still to be added (Task 8's brief).
- **Not in this plan; for you to decide:** `container.read(cloudSyncFollowerProvider)` in `lib/main.dart`. Under Riverpod 3 it follows sign-in and sign-out only while some widget watches `accountStateProvider`. The fix is one line (`container.listen`, as the new remote follower does).

## Rulings made so far (each with its cost if wrong)

- Ruling: R-a — selectRemote is `Future<void> selectRemote(PlayerService local, RemoteController controller, RemotePresence d)` (pause local, then select) — plain function testable without WidgetRef/Ref — cost if wrong: a trivial signature change.
- Ruling: T2 Step 6 (local Supabase RLS check) can't run — no supabase CLI on this machine — implementer adds the two-user RLS check to docs/manual-test-checklist.md (Accounts/Remote section) instead — cost if wrong: a policy typo is found only on the real project
- Ruling: Task 3 may modify lib/player/player_service.dart to add checked edits (playAtIf/removeAtIf/moveIf comparing epoch + id inside _locked) — spec says a stale index never touches the wrong song, and the check outside the lock breaks it — cost if wrong: three small extra PlayerService methods
- Ruling: Task 4 optimistic previous mirrors the host (position > 3 s → restart, keep index) instead of the brief's plain −1 — plan text was wrong against PlayerService.restartThreshold — cost if wrong: none, matches host
- Ruling: Task 4 run-on position anchors on local arrival time (lag 0), not at_ms − now — cross-device clocks differ; spec intent is a smoothly running position — cost if wrong: shown position lags by transit time (~100 ms)
- Task 5: parked — cloudSyncFollowerProvider is container.read in main.dart:391, so under Riverpod 3 it follows sign-in/out only while a widget watches accountStateProvider — Ruling: real, pre-existing, outside this plan; flag to user; one-line fix (container.listen) — cost if wrong: cloud sync can miss a start/stop
- Task 5: Ruling: Task 7 contract — remoteEndedProvider is Provider<Stream<(RemotePresence, RemoteEndReason)>>; the island subscribes to the stream itself, re-subscribes when the provider rebuilds, and must not drop the queued (device, signedOut) end on sign-out (add a test) — why: Riverpod 3 dedupes equal StreamProvider values — cost if wrong: a missed island

## Deferred minor findings (for the final review to triage)

- Task 1: minor (deferred): kRemoteQueueWindow not enforced on decode; untested reject cases (remove/move w/o epoch, v mismatch on command/hello, bad repeat, bad notice, empty name); `e.key! as String`; protocol imports player_service for RepeatMode; numeric ranges unchecked (host must bounds-check)
- Task 2: minor (deferred): stream controllers never closed (dead isClosed guards); null-error closed/timedOut join not logged
- Task 2: minor (deferred): stale-callback guards in SupabaseRemoteChannel untested (manual two-device check)
- Task 3: minor (deferred): seek-on-empty test is a no-op (plan-mandated); setVolume-throws test doesn't assert volume unchanged; repeated as List<String> casts
- Task 3: minor (deferred): seeks <=400 ms unseen by host; moveIf sync can run ahead of a queued local edit (local UI indexes shift, pre-existing with move)
- Task 4: minor (deferred): unknown ids re-looked-up every state and cached tracks never refreshed; select doesn't check current presence; ticker emits identical states at the cap; no test for late-lookup guard or lost-while-connecting; flapping device keeps link alive
- Task 5: minor (deferred): RemoteHost.start/channel.join window can leak a join after dispose (join should re-check after await leave()); account-switch test shares one fake channel for both ids; device_name fallback test asserts only isNotEmpty, 'Android'/'Computer' fallback names not in spec copy; failed local pause still selects; device name not refreshed mid-session; themes_page_test flake in full suite (passes alone); convoluted follower test

## Pre-flight scan

| Pair / task | Produces vs consumes | Found |
|---|---|---|
| T1→T2,T3,T4 | RemoteMessage/RemotePresence/RemoteState/RemoteCommand/RemoteHello, kRemoteProtocol | consistent |
| T2→T3,T4,T5 | RemoteChannel (present/presences incl. self), FakeRemoteHub.sent List<RemoteMessage> | consistent |
| T3→T4,T5 | tracksByIds Map<String,Track>; host presence fn supplied by T5 | consistent |
| T4→T5 | controller cmds take ids & window-relative indexes; PlayerView takes Tracks | consistent (view maps Track→id) |
| T5 selectRemote(WidgetRef/Ref) | signature left open | Ruling R-a below |
| T4↔T8 | T8 adds RemoteController.sendTo to T4's file | fine, sequential |
| T6↔T7↔T8 | player_bar, now_playing_header, mini_player, playlist_page touched by several tasks | sequential, no conflict |
| T1 self | tests match interfaces | ok |
| T2 self | Step 6 needs local Supabase; may be absent | report, not skip silently (plan says so) |
| T3 self | real PlayerService under fake_async; repeat via cycleRepeat | ok |
| T4 self | ok |
| T5 self | move Future vs PlayerService.move sync | wrapper, fine |
| T6 self | renamed calls listed | ok |
| T7 self | ok |
| T8 self | full suite + builds | ok |
