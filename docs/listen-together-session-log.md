# Listen together (SON-5, accounts step 4) — session log

Spec: [listen together design](superpowers/specs/2026-11-08-listen-together-design.md). Plan: [listen together plan](superpowers/plans/2026-11-09-listen-together.md). Linear: SON-5 (both documents are attached there too; the repo copies are the ones the build follows).
Branch: `listen-together`, in the main checkout, from `main` at `43a3a2b`. Not pushed, not merged. It does not contain the cover fixes (branch `cover-fixes`, SON-19/SON-20, pushed, waiting for the user's device check).

Flutter is at `$HOME/development/flutter/bin`.

## Status (2026-11-09, second pause): paused by the user during Task 7 of 7

The work runs with subagent-driven development: each task gets an implementer, a task review, and a scoped re-review after each fix round. The ledger (git-ignored) is `.superpowers/sdd/2026-11-09-listen-together/progress.md`; it holds the pre-flight scan, every ruling and every deferred minor. If it is gone, this log and `git log` are the record.

| Task | What | Commits | Review |
|---|---|---|---|
| 1 | Supabase tables, functions and Realtime rules; `RoomBackend` | `a9425fe`, fix `f7f6be8` | clean after 1 fix round |
| 2 | Room messages, `RoomSong`, codes and links | `e4e4069` | approved |
| 3 | `RoomChannel`, `FakeRoomHub`, `RoomHost` | `250c512` | approved |
| 4 | The guest follows (`RoomGuest`, `RoomGuestView`) | `f774c98`, fix `984f19c` | clean after 1 fix round |
| 5 | `RoomService`, providers, remote-control changes | `c52f93b` | approved |
| 6 | Links open the app (app_links, Android/Windows/Linux) | `e9c2a0e` | approved |
| 7 | Room UI | `78eaa98` (guests see every role, unreviewed); UI not written | stopped mid-task |

Tests: after Task 6, `flutter analyze` is clean and the full suite fails only on the two known stats "under 500 ms" timing tests (they pass on their own). `flutter build apk --debug` and `flutter build linux` succeed.

Task 7 was stopped by the user (PC shutdown) while its implementer was writing tests. Left in the tree, untracked and unfinished: `test/helpers/room_rig.dart`, `test/ui/room_panel_test.dart`. No UI code was written yet.

**To resume:** re-dispatch Task 7 with `superpowers:subagent-driven-development` (brief: `.superpowers/sdd/2026-11-09-listen-together/task-7-brief.md`, base `e9c2a0e`). Tell the implementer that `78eaa98` already adds Ruling 10 and that the two untracked test files are a half-written start it can keep or redo. The Task 7 review covers `e9c2a0e..HEAD`. Then the final whole-branch review (most capable model), pointed at the deferred minors below.

**Still to do by hand (the user):** apply `supabase/migrations/20261109120000_listen_together.sql` to the Supabase project and run the checks in the "Listen together" section of `docs/supabase.md`. The SQL has never run against a database.

## Rulings (each with its cost if wrong)

1. Guests' `playAt`/`remove`/`move` requests carry `args.videoId` of the song they saw at that index plus the state's epoch; the host passes its own track id to `playAtIf`/`removeAtIf`/`moveIf` only when the video id matches, else sends fresh state (the plan's guard needs a track id a guest can't know). Cost: a stale jump could hit a neighbouring copy of the same song.
2. Leave-reason islands: ended or host gone → "The room ended"; removed → "You were removed from the room"; unreachable → "Couldn't reach the room"; outdated → "Update Songies to join this room". Cost: copy only.
3. `roomInviteProvider` is a `NotifierProvider<RoomInvite, String?>`, not a `StateProvider` (Riverpod 3 keeps that only in its legacy import). Cost: a rename.
4. The migration is written and documented but not applied; applying it is the user's step. Cost: one SQL file to run.
5. **Security, accepted for rooms among friends:** Supabase Realtime checks its rules when a client joins the channel, not per message, and broadcasts carry no verified sender. So the server only keeps non-members out; any member could pose as the host or another guest, and removing someone or ending the room cuts off an already-connected client only when it reconnects or refreshes its token. The per-event "host only" rule was dropped. Cost: a friend could disrupt a room; enforcing it would need a server-relayed design.

## Deferred minors (for the final whole-branch review to triage)

Task 1: helper comment says "not callable by apps" though granted to `authenticated`; concurrent `open_room` by one host can leave two open rooms; a removed guest can rejoin at once (no ban); `open_room` empty result unguarded; no tests for timeout/client errors → offline or unknown → other; SQL cap 10 not tied to `kRoomMaxPeople`; `gen_random_bytes(16)` called per row; `is_room_host` now unused by any policy.

Task 2: link tests lack out-of-alphabet, wrong-path and `http://` cases; `RoomSong` accepts an empty `videoId`; state decoding doesn't bound the song list or reject negative numbers (the guest should clamp); `roomSongOf` never sets `artUrl`; `repeat`'s wire value is the enum name; `tracksForSongs` is sequential.

Task 3: a connection blip makes the channel report nobody present, so the host sees a burst of left/joined events; the request chain has no `catchError`; the 250 ms "debounce" is a throttle; no guard against removing or re-roling the host's own device; `setRole` sends after `stop`; a doc comment claims channel tests that don't exist; tests miss timers-after-stop, an exact heartbeat count, `GuestLeft`, the `playAt`/`move` guards and `addNext`.

## Rulings made after the first pause

6. When the host's queue changes but the current song is the same, the guest swaps its queue in place instead of restarting the song (spec: "a seek, not by cutting or restarting the song"; the plan said reload). Adds `PlayerService.replaceQueueAroundCurrent`. Cost: a little extra player code.
7. A guest's player tries only the host's current song and never skips ahead (new `PlayerService.skipUnplayable` flag, default on, turned off while guesting and restored on leaving), so a failing song stays silent. Cost: an extra player flag.
8. The real Supabase room backend and channel are the providers' lazy defaults instead of `main.dart` overrides (the plan's way broke 30 tests). Nothing touches Supabase until a room is used. Cost: two lines to move.
9. The manual `xdg-open songies://room/ABCD2345` check (Task 6 step 5) is left to the user: it registers the link handler in the desktop session. Cost: one manual check.
10. A guest knows every person's role (the guest panel shows them), via an additive getter on `RoomGuest`. Cost: a small getter.

Also from Task 6: the Linux runner is now single-instance (a second launch raises the open window). Windows link code is unbuilt (can't build on Linux).

## Deferred minors, Tasks 4–6

Task 4: Ruling 1 clamping and "newer state replaces pending" untested; while waiting on an unplayable host song before any load, the guest shows its own queue and the view's playAt/remove/move do nothing; after a full reload a paused host's guest plays briefly then pauses; expected position not bounded by duration; a failed song is not retried within one queue epoch; a state during `join` leaves the hello timer running until the next state; stream controllers never closed; tests silence `debugPrint`; the guest's shuffle is forced off and repeat mirrored, kept after leaving; `_checkStarted` would misfire if playback ever reported "playing" late.

Task 5: tests written after the code (no RED run); provider wiring untested; no service-level test for the host vanishing (`hostGone`); remote-host test uses `pause` where the brief said `play`; leaving while `join` waits for the host relies on microtask order; leave/end during `open`'s backend call are no-ops; remote presence republished on every room status change; `dispose` leaves a guest's membership row; sign-in notice on `open` untested.

Task 6: the Linux link registration writes its file before `xdg-mime`, so a failed `xdg-mime` is never retried; `%`/`"` in an AppImage path not escaped; the link stream has no `onError`; packaging test doesn't check `local_command_line`; import order in `main.dart`.

## Build environment note

`flutter build linux` needs libcurl headers this machine lacks. The Task 6 implementer pointed the git-ignored `build/linux` CMake cache at headers extracted into a temporary session folder, which will be gone after a reboot. Lasting fix: `sudo dnf install libcurl-devel`.

Still to do by hand (the user), in addition to the migration: the `xdg-open` link check (Ruling 9).
